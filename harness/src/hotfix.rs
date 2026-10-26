//! The client's cache of server hotfixes (`DBCache.bin`, magic `XFTH`), read from the game's own folder.
//!
//! The server sends rows that replace or remove rows of the client's tables. The cache says which table by its table
//! hash, the same number a `WDC5` table carries in its header, so a row here and a table in the file storage meet on
//! that hash. A table the cache names may not be in the local file storage at all.

use crate::casc::Error;

const MAGIC: &[u8; 4] = b"XFTH";
const HEADER: usize = 44;
const ENTRY: usize = 32;

/// The `status` byte of an entry that carries a record's data. Statuses 2, 3 and 4 also occur and none of them has
/// data in the cache on build 70450; what they mean is not established, so they are left as the raw byte.
pub const VALID: u8 = 1;

#[derive(Debug)]
pub struct Entry {
    pub push_id: u32,
    pub table_hash: u32,
    pub record_id: u32,
    pub status: u8,
    pub data: Vec<u8>,
}

#[derive(Debug)]
pub struct Cache {
    pub version: u32,
    pub build: u32,
    pub entries: Vec<Entry>,
}

fn word(bytes: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap())
}

impl Cache {
    pub fn parse(bytes: &[u8]) -> Result<Cache, Error> {
        if bytes.len() < HEADER || &bytes[..4] != MAGIC {
            return Err("not a hotfix cache".into());
        }
        let mut entries = Vec::new();
        let mut at = HEADER;
        while at < bytes.len() {
            if bytes.len() - at < ENTRY || &bytes[at..at + 4] != MAGIC {
                return Err(format!("a hotfix entry is cut short or misplaced at byte {at}"));
            }
            let size = word(bytes, at + 24) as usize;
            let data = bytes.get(at + ENTRY..at + ENTRY + size).ok_or_else(|| format!("a hotfix entry at byte {at} runs past the end"))?;
            entries.push(Entry {
                push_id: word(bytes, at + 8),
                table_hash: word(bytes, at + 16),
                record_id: word(bytes, at + 20),
                status: bytes[at + 28],
                data: data.to_vec(),
            });
            at += ENTRY + size;
        }
        Ok(Cache { version: word(bytes, 4), build: word(bytes, 8), entries })
    }

    /// The tables the cache names, with how many entries and how many carry data, most entries first.
    pub fn tables(&self) -> Vec<(u32, usize, usize)> {
        let mut counts: std::collections::HashMap<u32, (usize, usize)> = std::collections::HashMap::new();
        for entry in &self.entries {
            let count = counts.entry(entry.table_hash).or_default();
            count.0 += 1;
            count.1 += (entry.status == VALID) as usize;
        }
        let mut tables: Vec<_> = counts.into_iter().map(|(hash, (all, valid))| (hash, all, valid)).collect();
        tables.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        tables
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(push: u32, table: u32, record: u32, status: u8, data: &[u8]) -> Vec<u8> {
        let mut out = MAGIC.to_vec();
        for value in [70, push, 7, table, record, data.len() as u32] {
            out.extend_from_slice(&value.to_le_bytes());
        }
        out.extend_from_slice(&[status, 0, 0, 0]);
        out.extend_from_slice(data);
        out
    }

    fn cache(entries: &[Vec<u8>]) -> Vec<u8> {
        let mut out = MAGIC.to_vec();
        out.extend_from_slice(&9u32.to_le_bytes());
        out.extend_from_slice(&70450u32.to_le_bytes());
        out.extend_from_slice(&[0; 32]);
        for e in entries {
            out.extend_from_slice(e);
        }
        out
    }

    #[test]
    fn reads_entries_with_and_without_data() {
        let bytes = cache(&[entry(5, 0xaabbccdd, 100, 1, b"Frost\0"), entry(6, 0xaabbccdd, 101, 3, b""), entry(7, 0x11223344, 9, 1, b"x")]);
        let cache = Cache::parse(&bytes).unwrap();
        assert_eq!((cache.version, cache.build, cache.entries.len()), (9, 70450, 3));
        assert_eq!((cache.entries[0].record_id, cache.entries[0].status, cache.entries[0].data.as_slice()), (100, VALID, &b"Frost\0"[..]));
        assert_eq!((cache.entries[1].status, cache.entries[1].data.len()), (3, 0));
        assert_eq!(cache.tables(), vec![(0xaabbccdd, 2, 1), (0x11223344, 1, 1)]);
    }

    #[test]
    fn refuses_a_cut_off_file() {
        let mut bytes = cache(&[entry(5, 1, 1, 1, b"abcdef")]);
        bytes.truncate(bytes.len() - 2);
        assert!(Cache::parse(&bytes).unwrap_err().contains("runs past the end"));
        assert!(Cache::parse(b"nope").is_err());
    }
}
