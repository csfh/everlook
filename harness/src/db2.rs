//! The game's client tables (`WDC5` files), read from the game's own storage and from nothing else.
//!
//! The file says how each column is stored (how many bits, whether it is packed, in a palette or a common value) but
//! not what the column means or whether it is signed, a float or a string offset. That is a layout, which this reader
//! does not hold: a caller names columns and reads a field as a number, a list of numbers or an offset into the string
//! table. A table's layout hash changes whenever its columns do, so a committed layout is keyed by it.

use std::collections::HashMap;

use crate::casc::Error;

const HEADER: usize = 204;
const SECTION: usize = 40;

/// How one column is stored (`storage_type` in the file).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Storage {
    /// Plain bits at the column's place in the record.
    None,
    Bitpacked,
    /// A value shared by most records, with the exceptions listed by record id.
    Common,
    /// An index into a palette of values.
    Palette,
    /// A list of palette indexes.
    PaletteArray,
    BitpackedSigned,
}

#[derive(Clone, Debug)]
pub struct Column {
    pub offset_bits: u32,
    pub size_bits: u32,
    pub storage: Storage,
    /// The default of a common column, the palette index width of a palette column.
    pub first: u32,
    /// The list length of a palette-array column.
    pub array: u32,
    palette: Vec<u32>,
    common: HashMap<u32, u32>,
}

#[derive(Debug)]
pub struct Section {
    /// The section was encrypted: its rows are not read and are not counted in `Table::rows`.
    pub encrypted: bool,
    pub records: u32,
    /// The records the section's header counts, whether or not it could be read.
    pub listed: u32,
    data: Vec<u8>,
    strings: Vec<u8>,
    ids: Vec<u32>,
    /// The records of a table with variable-length records, as (id, bytes); their text is inline, after the numbers.
    sparse: Vec<(u32, Vec<u8>)>,
    /// The foreign id of each record that has one (the file's relationship data), by record index.
    parents: HashMap<u32, u32>,
    /// Records in the sections before this one, and string bytes in them: string offsets count from the end of all
    /// the records of the file, whether or not a section could be read.
    records_before: u64,
    strings_before: u64,
}

#[derive(Debug)]
pub struct Table {
    pub table_hash: u32,
    pub layout_hash: u32,
    pub record_size: u32,
    pub min_id: u32,
    pub max_id: u32,
    pub flags: u16,
    pub id_index: u16,
    pub columns: Vec<Column>,
    pub sections: Vec<Section>,
    total_records: u64,
}

/// One row, borrowed from its section.
pub struct Row<'a> {
    pub id: u32,
    pub index: usize,
    table: &'a Table,
    section: &'a Section,
}

fn word(bytes: &[u8], at: usize) -> Result<u32, Error> {
    bytes.get(at..at + 4).map(|b| u32::from_le_bytes(b.try_into().unwrap())).ok_or_else(|| format!("a table cut short at byte {at}"))
}

fn half(bytes: &[u8], at: usize) -> Result<u16, Error> {
    bytes.get(at..at + 2).map(|b| u16::from_le_bytes(b.try_into().unwrap())).ok_or_else(|| format!("a table cut short at byte {at}"))
}

fn slice(bytes: &[u8], at: usize, len: usize) -> Result<&[u8], Error> {
    bytes.get(at..at.checked_add(len).ok_or("a table size does not fit")?).ok_or_else(|| format!("a table cut short at byte {at}, wanting {len}"))
}

impl Table {
    /// `skipped` is the byte ranges of `bytes` that were encrypted and set to zeros (`Casc::read_id_lenient`).
    pub fn parse(bytes: &[u8], skipped: &[(usize, usize)]) -> Result<Table, Error> {
        if bytes.get(0..4) != Some(b"WDC5") {
            return Err("not a WDC5 table".into());
        }
        let field_count = word(bytes, 140)? as usize;
        let storage_size = word(bytes, 188)? as usize;
        let common_size = word(bytes, 192)? as usize;
        let palette_size = word(bytes, 196)? as usize;
        let section_count = word(bytes, 200)? as usize;
        let flags = half(bytes, 172)?;
        let record_size = word(bytes, 144)?;

        let mut at = HEADER + section_count * SECTION + field_count * 4;
        let mut columns = Vec::new();
        for i in 0..storage_size / 24 {
            let entry = slice(bytes, at + i * 24, 24)?;
            let storage = match word(entry, 8)? {
                0 => Storage::None,
                1 => Storage::Bitpacked,
                2 => Storage::Common,
                3 => Storage::Palette,
                4 => Storage::PaletteArray,
                5 => Storage::BitpackedSigned,
                other => return Err(format!("column {i} has an unknown storage kind {other}")),
            };
            columns.push((entry.to_vec(), storage, word(entry, 4)? as usize));
        }
        at += storage_size;
        let palette = slice(bytes, at, palette_size)?;
        let common = slice(bytes, at + palette_size, common_size)?;
        let (mut palette_at, mut common_at) = (0, 0);
        let columns = columns
            .into_iter()
            .map(|(entry, storage, extra)| {
                let mut column = Column {
                    offset_bits: half(&entry, 0)? as u32,
                    size_bits: half(&entry, 2)? as u32,
                    storage,
                    first: word(&entry, 12)?,
                    array: if storage == Storage::PaletteArray { word(&entry, 20)? } else { 0 },
                    palette: Vec::new(),
                    common: HashMap::new(),
                };
                match storage {
                    Storage::Palette | Storage::PaletteArray => {
                        let part = slice(palette, palette_at, extra)?;
                        column.palette = part.chunks_exact(4).map(|c| u32::from_le_bytes(c.try_into().unwrap())).collect();
                        palette_at += extra;
                    }
                    Storage::Common => {
                        let part = slice(common, common_at, extra)?;
                        column.common = part.chunks_exact(8).map(|c| (u32::from_le_bytes(c[..4].try_into().unwrap()), u32::from_le_bytes(c[4..].try_into().unwrap()))).collect();
                        common_at += extra;
                    }
                    _ => {}
                }
                Ok(column)
            })
            .collect::<Result<Vec<_>, Error>>()?;

        let id_index = half(bytes, 174)?;
        let mut sections = Vec::new();
        let (mut records_before, mut strings_before) = (0u64, 0u64);
        for s in 0..section_count {
            let head = slice(bytes, HEADER + s * SECTION, SECTION)?;
            let (offset, records, strings, id_list) = (word(head, 8)? as usize, word(head, 12)?, word(head, 16)? as usize, word(head, 24)? as usize);
            let key = u64::from_le_bytes(head[..8].try_into().unwrap());
            let size = records as usize * record_size as usize;
            let encrypted = key != 0 && skipped.iter().any(|&(from, to)| offset >= from && offset < to);
            let before = (records_before, strings_before);
            records_before += records as u64;
            strings_before += strings as u64;
            if encrypted || records == 0 {
                sections.push(Section { encrypted, records: if encrypted { 0 } else { records }, listed: records, data: Vec::new(), strings: Vec::new(), ids: Vec::new(), parents: HashMap::new(), sparse: Vec::new(), records_before: before.0, strings_before: before.1 });
                continue;
            }
            if flags & 1 != 0 {
                // Variable-length records: the section runs to `offset_records_end`, then the id list, copy table,
                // offset map (absolute offset and length of each record), relationship data and the map's ids.
                let end = word(head, 20)? as usize;
                let (copies, count, relation) = (word(head, 36)? as usize * 8, word(head, 32)? as usize, word(head, 28)? as usize);
                let list = slice(bytes, end, id_list)?;
                let map = slice(bytes, end + id_list + copies, count * 6)?;
                let map_ids = slice(bytes, end + id_list + copies + count * 6 + relation, count * 4)?;
                let listed: Vec<u32> = list.chunks_exact(4).map(|c| u32::from_le_bytes(c.try_into().unwrap())).collect();
                let mut found = Vec::new();
                for (i, entry) in map.chunks_exact(6).enumerate() {
                    let (at, length) = (u32::from_le_bytes(entry[..4].try_into().unwrap()) as usize, u16::from_le_bytes(entry[4..].try_into().unwrap()) as usize);
                    let id = listed.get(i).copied().unwrap_or_else(|| u32::from_le_bytes(map_ids[i * 4..i * 4 + 4].try_into().unwrap()));
                    found.push((id, slice(bytes, at, length)?.to_vec()));
                }
                sections.push(Section { encrypted: false, records: 0, listed: records, data: Vec::new(), strings: Vec::new(), ids: Vec::new(), parents: HashMap::new(), sparse: found, records_before: before.0, strings_before: before.1 });
                continue;
            }
            let (copies, offsets, relation) = (word(head, 36)? as usize * 8, word(head, 32)? as usize * 6, word(head, 28)? as usize);
            let relation_at = offset + size + strings + id_list + copies + offsets;
            let mut parents = HashMap::new();
            if relation >= 12 {
                let data = slice(bytes, relation_at, relation)?;
                for pair in data[12..].chunks_exact(8) {
                    parents.insert(u32::from_le_bytes(pair[4..].try_into().unwrap()), u32::from_le_bytes(pair[..4].try_into().unwrap()));
                }
            }
            let ids = slice(bytes, offset + size + strings, id_list)?.chunks_exact(4).map(|c| u32::from_le_bytes(c.try_into().unwrap())).collect();
            sections.push(Section { encrypted: false, records, listed: records, data: slice(bytes, offset, size)?.to_vec(), strings: slice(bytes, offset + size, strings)?.to_vec(), ids, parents, sparse: Vec::new(), records_before: before.0, strings_before: before.1 });
        }

        Ok(Table {
            table_hash: word(bytes, 152)?,
            layout_hash: word(bytes, 156)?,
            record_size,
            min_id: word(bytes, 160)?,
            max_id: word(bytes, 164)?,
            flags,
            id_index,
            columns,
            sections,
            total_records: records_before,
        })
    }

    pub fn rows(&self) -> impl Iterator<Item = Row<'_>> {
        self.sections.iter().filter(|s| !s.encrypted).flat_map(move |section| {
            (0..section.records as usize).map(move |index| {
                let id = match section.ids.get(index) {
                    Some(&id) => id,
                    // With no id list the id is one of the record's own columns.
                    None => self.columns.get(self.id_index as usize).map(|_| Row { id: 0, index, table: self, section }.number(self.id_index as usize) as u32).unwrap_or(0),
                };
                Row { id, index, table: self, section }
            })
        })
    }

    /// Each section as (rows, string table bytes, encrypted), for a dump.
    pub fn section_sizes(&self) -> Vec<(u32, usize, bool)> {
        self.sections.iter().map(|s| (s.records, s.strings.len(), s.encrypted)).collect()
    }

    /// The records of a table with variable-length records. Their columns are not split: that needs a layout.
    pub fn sparse_records(&self) -> impl Iterator<Item = &(u32, Vec<u8>)> {
        self.sections.iter().flat_map(|s| s.sparse.iter())
    }

    /// The rows the headers count and the rows that could be read, so a table that is mostly locked shows.
    pub fn listed_rows(&self) -> (u64, u64) {
        (self.sections.iter().map(|s| s.listed as u64).sum(), self.sections.iter().map(|s| s.records as u64).sum())
    }

    /// How many sections were set aside because they were encrypted.
    pub fn encrypted_sections(&self) -> usize {
        self.sections.iter().filter(|s| s.encrypted).count()
    }
}

impl Row<'_> {
    /// The id this row points at through the file's relationship data (a spell's id on a row of its own table).
    pub fn parent(&self) -> Option<u32> {
        self.section.parents.get(&(self.index as u32)).copied()
    }

    fn record(&self) -> &[u8] {
        let size = self.table.record_size as usize;
        &self.section.data[self.index * size..(self.index + 1) * size]
    }

    fn bits(&self, from: u32, count: u32) -> u64 {
        let record = self.record();
        let mut value = 0u64;
        for i in 0..count.min(64) {
            let at = (from + i) as usize;
            if record.get(at / 8).is_some_and(|byte| byte >> (at % 8) & 1 == 1) {
                value |= 1 << i;
            }
        }
        value
    }

    /// A column as one unsigned number, the way the file stores it. A palette-array column gives its first entry.
    pub fn number(&self, column: usize) -> u64 {
        self.numbers(column).first().copied().unwrap_or(0)
    }

    /// A column as its list of numbers: one for a single value, the list for a palette array or a plain column wider
    /// than 32 bits and so cut into 32-bit words.
    pub fn numbers(&self, column: usize) -> Vec<u64> {
        let Some(c) = self.table.columns.get(column) else { return Vec::new() };
        match c.storage {
            Storage::None => {
                let mut words = Vec::new();
                let mut at = 0;
                while at < c.size_bits.max(1) {
                    words.push(self.bits(c.offset_bits + at, (c.size_bits - at).min(32)));
                    at += 32;
                }
                words
            }
            Storage::Bitpacked => vec![self.bits(c.offset_bits, c.size_bits)],
            Storage::BitpackedSigned => {
                let raw = self.bits(c.offset_bits, c.size_bits);
                let sign = 1u64 << (c.size_bits.max(1) - 1);
                vec![if raw & sign != 0 { raw | !(sign * 2 - 1) } else { raw }]
            }
            Storage::Common => vec![c.common.get(&self.id).copied().unwrap_or(c.first) as u64],
            Storage::Palette => vec![c.palette.get(self.bits(c.offset_bits, c.size_bits) as usize).copied().unwrap_or(0) as u64],
            Storage::PaletteArray => {
                let start = self.bits(c.offset_bits, c.size_bits) as usize * c.array as usize;
                (0..c.array as usize).map(|i| c.palette.get(start + i).copied().unwrap_or(0) as u64).collect()
            }
        }
    }

    /// The text a string column holds: its value is a distance from the column's own place in the record to the text,
    /// counted from the end of all the records of the file. Checked on real data for the first section only: no table
    /// of this build has a second readable section with strings, so the earlier-sections term is the synthetic test's.
    pub fn string(&self, column: usize) -> Option<String> {
        let c = self.table.columns.get(column)?;
        let value = *self.numbers(column).first()?;
        let size = self.table.record_size as u64;
        let from = (self.section.records_before + self.index as u64) * size + (c.offset_bits / 8) as u64 + value;
        let at = from.checked_sub(self.table.total_records * size + self.section.strings_before)? as usize;
        let tail = self.section.strings.get(at..)?;
        let end = tail.iter().position(|&b| b == 0)?;
        String::from_utf8(tail[..end].to_vec()).ok()
    }
}

impl Section {
    /// Whether the section's string table holds this exact text.
    pub fn has_string(&self, text: &str) -> bool {
        let mut needle = vec![0u8];
        needle.extend_from_slice(text.as_bytes());
        needle.push(0);
        self.strings.windows(needle.len()).any(|w| w == needle.as_slice())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn put(bytes: &mut [u8], at: usize, value: u64, width: usize) {
        bytes[at..at + width].copy_from_slice(&value.to_le_bytes()[..width]);
    }

    /// A header for one 32-bit column and the given sections as (key, offset, records, strings, end, id bytes,
    /// relationship bytes, map entries). The column is plain bits at the start of the record.
    fn table(flags: u16, sections: &[[u64; 8]]) -> Vec<u8> {
        let head = HEADER + sections.len() * SECTION + 4 + 24;
        let mut bytes = vec![0u8; head];
        bytes[..4].copy_from_slice(b"WDC5");
        put(&mut bytes, 4, 5, 4);
        put(&mut bytes, 140, 1, 4);
        put(&mut bytes, 144, 4, 4);
        put(&mut bytes, 152, 0xfeed, 4);
        put(&mut bytes, 156, 0xbeef, 4);
        put(&mut bytes, 172, flags as u64, 2);
        put(&mut bytes, 188, 24, 4);
        put(&mut bytes, 200, sections.len() as u64, 4);
        for (i, s) in sections.iter().enumerate() {
            let at = HEADER + i * SECTION;
            for (k, (offset, width)) in [(0, 8), (8, 4), (12, 4), (16, 4), (20, 4), (24, 4), (28, 4), (32, 4)].into_iter().enumerate() {
                put(&mut bytes, at + offset, s[k], width);
            }
        }
        // The one column: 32 bits at bit 0, stored as plain bits.
        put(&mut bytes, HEADER + sections.len() * SECTION + 4 + 2, 32, 2);
        bytes
    }

    #[test]
    fn string_offsets_count_from_the_end_of_every_sections_records_and_parents_come_from_relationship_data() {
        // Section 0 is readable (2 records, ids 10 and 20); section 1 is encrypted (3 records, 4 bytes of strings).
        let head = HEADER + 2 * SECTION + 4 + 24;
        let strings = b"\0Hi\0There\0";
        let one = head + 8 + strings.len() + 8 + 28;
        let mut bytes = table(0, &[[0, head as u64, 2, strings.len() as u64, 0, 8, 28, 0], [0x1234, one as u64, 3, 4, 0, 12, 0, 0]]);
        // Both sections hold 4-byte records, five in all, so a string's offset starts counting after 20 bytes.
        bytes.extend_from_slice(&21u32.to_le_bytes()); // record 0: "Hi" is at 1 in the table; 0 * 4 + 21 - 20
        bytes.extend_from_slice(&20u32.to_le_bytes()); // record 1: "There" is at 4; 1 * 4 + 20 - 20
        bytes.extend_from_slice(strings);
        for id in [10u32, 20] {
            bytes.extend_from_slice(&id.to_le_bytes());
        }
        for value in [2u32, 0, 1, 500, 0, 600, 1] {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        bytes.extend_from_slice(&[0; 4 * 3 + 4 + 12]); // the encrypted section, as zeros
        let table = Table::parse(&bytes, &[(one, bytes.len())]).unwrap();

        assert_eq!((table.table_hash, table.layout_hash, table.encrypted_sections()), (0xfeed, 0xbeef, 1));
        let rows: Vec<_> = table.rows().collect();
        assert_eq!(rows.len(), 2);
        assert_eq!((rows[0].id, rows[0].string(0).as_deref(), rows[0].parent()), (10, Some("Hi"), Some(500)));
        assert_eq!((rows[1].id, rows[1].string(0).as_deref(), rows[1].parent()), (20, Some("There"), Some(600)));
    }

    #[test]
    fn variable_length_records_are_read_with_their_ids() {
        let head = HEADER + SECTION + 4 + 24;
        let end = head + 7;
        let mut bytes = table(1, &[[0, head as u64, 2, 0, end as u64, 0, 0, 2]]);
        bytes.extend_from_slice(b"ab\0xyz\0");
        for (at, length) in [(head, 3u16), (head + 3, 4)] {
            bytes.extend_from_slice(&(at as u32).to_le_bytes());
            bytes.extend_from_slice(&length.to_le_bytes());
        }
        for id in [7u32, 9] {
            bytes.extend_from_slice(&id.to_le_bytes());
        }
        let table = Table::parse(&bytes, &[]).unwrap();
        let records: Vec<_> = table.sparse_records().map(|(id, data)| (*id, data.clone())).collect();
        assert_eq!(records, vec![(7, b"ab\0".to_vec()), (9, b"xyz\0".to_vec())]);
    }
}
