//! A read-only reader for the game's own local file storage (CASC), found under the game folder's `Data`.
//!
//! It reads nothing from outside the folder: `.build.info` names the build, the build config names the encoding and
//! root files, the local `.idx` files say where each stored file sits in `data.NNN`, and the root says which stored
//! file a file id is. A file is found by id, or by its path through the game's own name hash, so no list of names
//! from anywhere else is needed. Every file is opened for reading only, because the game may be running.

use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

pub type Error = String;

/// Where a stored file sits: the data file's number, the offset in it and the size with its local header.
#[derive(Clone, Copy)]
struct Place {
    archive: u16,
    offset: u32,
    size: u32,
}

pub struct Casc {
    data: PathBuf,
    index: HashMap<[u8; 9], Place>,
    encoding: Vec<u8>,
    ckey_pages: Vec<([u8; 16], usize)>,
    page_size: usize,
    root: HashMap<u32, [u8; 16]>,
    names: HashMap<u64, u32>,
    pub build: String,
}

/// The header and the row of `.build.info` for the game that is installed and active: the first row when none says so.
pub fn build_row(info: &str) -> Result<(Vec<&str>, Vec<&str>), Error> {
    let mut lines = info.lines();
    let head: Vec<&str> = lines.next().ok_or("empty .build.info")?.split('|').collect();
    let column = |name: &str| head.iter().position(|h| h.split('!').next() == Some(name));
    let rows: Vec<Vec<&str>> = lines.filter(|line| !line.trim().is_empty()).map(|line| line.split('|').collect()).collect();
    let (product, active) = (column("Product"), column("Active"));
    let installed = |row: &&Vec<&str>| product.is_some_and(|i| row.get(i).is_some_and(|p| p.starts_with("wow"))) && active.is_some_and(|i| row.get(i) == Some(&"1"));
    let row = rows.iter().find(installed).or(rows.first()).ok_or("no build row")?.clone();
    Ok((head, row))
}

fn hex16(text: &str) -> Result<[u8; 16], Error> {
    if text.len() != 32 {
        return Err(format!("not a 16 byte key: {text}"));
    }
    let mut key = [0u8; 16];
    for (i, byte) in key.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&text[i * 2..i * 2 + 2], 16).map_err(|e| e.to_string())?;
    }
    Ok(key)
}

fn be32(bytes: &[u8]) -> u32 {
    u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}

fn le32(bytes: &[u8]) -> u32 {
    u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}

impl Casc {
    /// Opens the storage of the game installed in `game` (the folder holding `.build.info` and `Data`).
    pub fn open(game: &Path) -> Result<Casc, Error> {
        let info = std::fs::read_to_string(game.join(".build.info")).map_err(|e| format!(".build.info: {e}"))?;
        let (head, row) = build_row(&info)?;
        let column = |name: &str| head.iter().position(|h| h.split('!').next() == Some(name));
        let build_key = column("Build Key").ok_or("no Build Key column")?;
        let version = column("Version");
        let build_hash = row[build_key];
        let build = version.map(|i| row[i].to_string()).unwrap_or_default();
        let config = game.join("Data/config").join(&build_hash[0..2]).join(&build_hash[2..4]).join(build_hash);
        let config = std::fs::read_to_string(&config).map_err(|e| format!("build config {build_hash}: {e}"))?;
        let value = |name: &str| -> Option<Vec<String>> {
            config.lines().find_map(|line| {
                let (key, rest) = line.split_once(" = ")?;
                (key == name).then(|| rest.split_whitespace().map(str::to_string).collect())
            })
        };
        let root_ckey = hex16(&value("root").ok_or("no root in the build config")?[0])?;
        let encoding = value("encoding").ok_or("no encoding in the build config")?;
        let encoding_ekey = hex16(encoding.get(1).ok_or("no encoding key")?)?;

        let data = game.join("Data/data");
        let mut casc = Casc {
            data,
            index: HashMap::new(),
            encoding: Vec::new(),
            ckey_pages: Vec::new(),
            page_size: 0,
            root: HashMap::new(),
            names: HashMap::new(),
            build,
        };
        casc.load_index()?;
        let encoding = casc.read_ekey(&encoding_ekey)?;
        casc.parse_encoding(encoding)?;
        let root = casc.read_ckey(&root_ckey)?;
        casc.parse_root(&root)?;
        Ok(casc)
    }

    fn load_index(&mut self) -> Result<(), Error> {
        let mut newest: HashMap<u8, (u32, PathBuf)> = HashMap::new();
        for entry in std::fs::read_dir(&self.data).map_err(|e| format!("{}: {e}", self.data.display()))?.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.len() != 14 || !name.ends_with(".idx") {
                continue;
            }
            let (Ok(bucket), Ok(version)) = (u8::from_str_radix(&name[0..2], 16), u32::from_str_radix(&name[2..10], 16)) else { continue };
            if newest.get(&bucket).is_none_or(|(known, _)| version > *known) {
                newest.insert(bucket, (version, entry.path()));
            }
        }
        if newest.is_empty() {
            return Err("no .idx files in Data/data".into());
        }
        for (_, path) in newest.values() {
            let bytes = std::fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
            if bytes.len() < 40 || bytes[8] != 7 {
                return Err(format!("{} is not a version 7 index", path.display()));
            }
            let size = le32(&bytes[32..36]) as usize;
            for i in 0..size / 18 {
                let entry = &bytes[40 + i * 18..40 + i * 18 + 18];
                let mut key = [0u8; 9];
                key.copy_from_slice(&entry[..9]);
                let packed = entry[9..14].iter().fold(0u64, |value, byte| value << 8 | *byte as u64);
                self.index.entry(key).or_insert(Place { archive: (packed >> 30) as u16, offset: (packed & 0x3fff_ffff) as u32, size: le32(&entry[14..18]) });
            }
        }
        Ok(())
    }

    /// The stored file with this encoding key, with its blocks decoded.
    pub fn read_ekey(&self, ekey: &[u8; 16]) -> Result<Vec<u8>, Error> {
        let place = self.index.get(&ekey[..9]).ok_or("the key is not in the local index")?;
        let path = self.data.join(format!("data.{:03}", place.archive));
        let mut file = File::open(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        file.seek(SeekFrom::Start(place.offset as u64)).map_err(|e| e.to_string())?;
        let mut stored = vec![0u8; place.size as usize];
        file.read_exact(&mut stored).map_err(|e| e.to_string())?;
        if stored.len() < 30 {
            return Err("a stored file shorter than its header".into());
        }
        blte(&stored[30..])
    }

    /// The file with this content key.
    pub fn read_ckey(&self, ckey: &[u8; 16]) -> Result<Vec<u8>, Error> {
        let ekey = self.ekey_for(ckey).ok_or("the content key is not in the encoding file")?;
        self.read_ekey(&ekey)
    }

    /// The first `limit` bytes or so of the file with this id: only as many blocks as that needs are read.
    pub fn read_head(&self, id: u32, limit: usize) -> Result<Vec<u8>, Error> {
        let ckey = self.root.get(&id).ok_or_else(|| format!("file {id} is not in the root"))?;
        let ekey = self.ekey_for(ckey).ok_or("the content key is not in the encoding file")?;
        let place = self.index.get(&ekey[..9]).ok_or("the key is not in the local index")?;
        let path = self.data.join(format!("data.{:03}", place.archive));
        let mut file = File::open(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        file.seek(SeekFrom::Start(place.offset as u64 + 30)).map_err(|e| e.to_string())?;
        // The block table comes first. Read it, then take exactly the blocks that hold `limit` bytes of output: a fixed
        // buffer cuts a long table or a large first block short, and a block cut short reads as no data at all.
        let total = (place.size as usize).saturating_sub(30);
        let mut lead = [0u8; 8];
        let table = if file.read_exact(&mut lead).is_ok() && &lead[0..4] == b"BLTE" { be32(&lead[4..8]) as usize } else { 0 };
        let want = if &lead[0..4] != b"BLTE" {
            total.min(limit.saturating_mul(2).saturating_add(4096))
        } else if table == 0 {
            total
        } else {
            let mut entries = vec![0u8; table.saturating_sub(8).min(total)];
            file.read_exact(&mut entries).map_err(|e| e.to_string())?;
            let (mut stored, mut decoded) = (0usize, 0usize);
            for entry in entries.get(4..).unwrap_or(&[]).chunks_exact(24) {
                stored += be32(&entry[0..4]) as usize;
                decoded += be32(&entry[4..8]) as usize;
                if decoded >= limit {
                    break;
                }
            }
            (table + stored).min(total)
        };
        file.seek(SeekFrom::Start(place.offset as u64 + 30)).map_err(|e| e.to_string())?;
        let mut stored = vec![0u8; want];
        let got = file.read(&mut stored).map_err(|e| e.to_string())?;
        stored.truncate(got);
        blte_limited(&stored, limit)
    }

    /// The file with this id, with each encrypted block left as zeros of its decoded size. The second value is the
    /// byte ranges of the output those blocks stand for, so a reader can set aside what it could not read.
    pub fn read_id_lenient(&self, id: u32) -> Result<(Vec<u8>, Vec<(usize, usize)>), Error> {
        blte_lenient(&self.stored(id)?)
    }

    /// The stored blocks of the file with this id, as they sit in the data files, header cut off.
    pub fn stored(&self, id: u32) -> Result<Vec<u8>, Error> {
        let ckey = self.root.get(&id).ok_or_else(|| format!("file {id} is not in the root"))?;
        let ekey = self.ekey_for(ckey).ok_or("the content key is not in the encoding file")?;
        let place = self.index.get(&ekey[..9]).ok_or("the key is not in the local index")?;
        let path = self.data.join(format!("data.{:03}", place.archive));
        let mut file = File::open(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        file.seek(SeekFrom::Start(place.offset as u64)).map_err(|e| e.to_string())?;
        let mut stored = vec![0u8; place.size as usize];
        file.read_exact(&mut stored).map_err(|e| e.to_string())?;
        if stored.len() < 30 {
            return Err("a stored file shorter than its header".into());
        }
        Ok(stored[30..].to_vec())
    }

    /// The root entries whose data is not in the local files: file id and encoding key. An entry the encoding file
    /// does not know is left out.
    pub fn missing(&self) -> Vec<(u32, [u8; 16])> {
        let mut out: Vec<(u32, [u8; 16])> = self
            .root
            .iter()
            .filter_map(|(id, ckey)| self.ekey_for(ckey).filter(|ekey| !self.index.contains_key(&ekey[..9])).map(|ekey| (*id, ekey)))
            .collect();
        out.sort_unstable();
        out
    }

    /// Every file id the root lists, in order.
    pub fn ids(&self) -> Vec<u32> {
        let mut ids: Vec<u32> = self.root.keys().copied().collect();
        ids.sort_unstable();
        ids
    }

    /// The file with this id, if the root lists it.
    pub fn read_id(&self, id: u32) -> Result<Vec<u8>, Error> {
        let ckey = self.root.get(&id).ok_or_else(|| format!("file {id} is not in the root"))?;
        self.read_ckey(ckey)
    }

    /// The id of a file by its path, through the game's own name hash.
    pub fn id_of(&self, path: &str) -> Option<u32> {
        self.names.get(&name_hash(path)).copied()
    }

    pub fn has(&self, id: u32) -> bool {
        self.root.contains_key(&id)
    }

    pub fn file_count(&self) -> usize {
        self.root.len()
    }

    fn parse_encoding(&mut self, bytes: Vec<u8>) -> Result<(), Error> {
        if bytes.len() < 22 || &bytes[0..2] != b"EN" || bytes[3] != 16 || bytes[4] != 16 {
            return Err("the encoding file is not the format this reader knows".into());
        }
        let page_size = u16::from_be_bytes([bytes[5], bytes[6]]) as usize * 1024;
        let pages = be32(&bytes[9..13]) as usize;
        let spec_size = be32(&bytes[18..22]) as usize;
        let index = 22 + spec_size;
        let pages_at = index + pages * 32;
        let mut ckey_pages = Vec::with_capacity(pages);
        for page in 0..pages {
            let mut first = [0u8; 16];
            first.copy_from_slice(&bytes[index + page * 32..index + page * 32 + 16]);
            ckey_pages.push((first, pages_at + page * page_size));
        }
        self.ckey_pages = ckey_pages;
        self.page_size = page_size;
        self.encoding = bytes;
        Ok(())
    }

    fn ekey_for(&self, ckey: &[u8; 16]) -> Option<[u8; 16]> {
        let page = self.ckey_pages.partition_point(|(first, _)| first <= ckey).checked_sub(1)?;
        let start = self.ckey_pages[page].1;
        let bytes = &self.encoding[start..(start + self.page_size).min(self.encoding.len())];
        let mut at = 0;
        while at + 22 <= bytes.len() {
            let keys = bytes[at] as usize;
            if keys == 0 {
                return None;
            }
            let entry = &bytes[at + 6..at + 22];
            if entry == ckey {
                let mut ekey = [0u8; 16];
                ekey.copy_from_slice(&bytes[at + 22..at + 38]);
                return Some(ekey);
            }
            at += 22 + keys * 16;
        }
        None
    }

    fn parse_root(&mut self, bytes: &[u8]) -> Result<(), Error> {
        if bytes.len() < 24 || &bytes[0..4] != b"TSFM" || le32(&bytes[4..8]) != 24 || le32(&bytes[8..12]) != 2 {
            return Err("the root file is not the version 2 MFST this reader knows".into());
        }
        let mut at = 24;
        while at + 17 <= bytes.len() {
            let records = le32(&bytes[at..at + 4]) as usize;
            let locale = le32(&bytes[at + 4..at + 8]);
            let content = le32(&bytes[at + 8..at + 12]) | le32(&bytes[at + 12..at + 16]) | (bytes[at + 16] as u32) << 17;
            at += 17;
            let named = content & 0x1000_0000 == 0;
            let stride = 16;
            if at + records * (4 + stride + if named { 8 } else { 0 }) > bytes.len() {
                return Err("the root file ends inside a block".into());
            }
            let first = at + records * 4;
            let mut id: i64 = -1;
            for i in 0..records {
                id += le32(&bytes[at + i * 4..at + i * 4 + 4]) as i32 as i64 + 1;
                let id = id as u32;
                let entry = first + i * stride;
                let mut ckey = [0u8; 16];
                ckey.copy_from_slice(&bytes[entry..entry + 16]);
                // A file that has a version for each language keeps the English one.
                if locale & ENGLISH != 0 || !self.root.contains_key(&id) {
                    self.root.insert(id, ckey);
                }
                if named {
                    let hash = first + records * stride + i * 8;
                    self.names.entry(u64::from_le_bytes(bytes[hash..hash + 8].try_into().unwrap())).or_insert(id);
                }
            }
            at = first + records * (stride + if named { 8 } else { 0 });
        }
        Ok(())
    }
}

const ENGLISH: u32 = 0x2;

/// Decodes the blocks of a stored file. Plain and deflated blocks only: an encrypted block is reported.
pub fn blte(bytes: &[u8]) -> Result<Vec<u8>, Error> {
    blte_limited(bytes, usize::MAX)
}

/// Like `blte`, but stops after the block that takes the output past `limit`. A cut-off file is fine for this.
pub fn blte_limited(bytes: &[u8], limit: usize) -> Result<Vec<u8>, Error> {
    if bytes.len() < 8 || &bytes[0..4] != b"BLTE" {
        return Err("not a BLTE file".into());
    }
    let header = be32(&bytes[4..8]) as usize;
    let mut out = Vec::new();
    if header == 0 {
        block(&bytes[8..], &mut out)?;
        return Ok(out);
    }
    let count = ((bytes[9] as usize) << 16) | ((bytes[10] as usize) << 8) | bytes[11] as usize;
    let mut at = header;
    for i in 0..count {
        let entry = 12 + i * 24;
        let stored = be32(&bytes[entry..entry + 4]) as usize;
        if at + stored > bytes.len() {
            break;
        }
        block(&bytes[at..at + stored], &mut out)?;
        at += stored;
        if out.len() >= limit {
            break;
        }
    }
    Ok(out)
}

/// The key names (as the 8 bytes the file gives them) of the encrypted blocks of a stored file, with each block's decoded
/// size. A file with no block table gives none.
pub fn blte_keys(bytes: &[u8]) -> Vec<(u64, usize)> {
    if bytes.len() < 12 || &bytes[0..4] != b"BLTE" || be32(&bytes[4..8]) == 0 {
        return Vec::new();
    }
    let header = be32(&bytes[4..8]) as usize;
    let count = ((bytes[9] as usize) << 16) | ((bytes[10] as usize) << 8) | bytes[11] as usize;
    let (mut at, mut keys) = (header, Vec::new());
    for i in 0..count {
        let entry = 12 + i * 24;
        let (Some(stored), Some(decoded)) = (bytes.get(entry..entry + 4), bytes.get(entry + 4..entry + 8)) else { break };
        let (stored, decoded) = (be32(stored) as usize, be32(decoded) as usize);
        if bytes.get(at) == Some(&b'E') {
            if let Some(name) = bytes.get(at + 2..at + 10) {
                keys.push((u64::from_le_bytes(name.try_into().unwrap()), decoded));
            }
        }
        at += stored;
    }
    keys
}

/// Like `blte`, but an encrypted block becomes zeros of its decoded size and its range is returned beside the bytes.
/// A file with no block table has no size to give an encrypted block, so that stays an error.
pub fn blte_lenient(bytes: &[u8]) -> Result<(Vec<u8>, Vec<(usize, usize)>), Error> {
    if bytes.len() < 8 || &bytes[0..4] != b"BLTE" {
        return Err("not a BLTE file".into());
    }
    let header = be32(&bytes[4..8]) as usize;
    let mut out = Vec::new();
    let mut skipped = Vec::new();
    if header == 0 {
        block(&bytes[8..], &mut out)?;
        return Ok((out, skipped));
    }
    let count = ((bytes[9] as usize) << 16) | ((bytes[10] as usize) << 8) | bytes[11] as usize;
    let mut at = header;
    for i in 0..count {
        let entry = 12 + i * 24;
        let stored = be32(&bytes[entry..entry + 4]) as usize;
        let decoded = be32(&bytes[entry + 4..entry + 8]) as usize;
        if at + stored > bytes.len() {
            return Err("a block runs past the end of the stored file".into());
        }
        if bytes[at] == b'E' {
            skipped.push((out.len(), out.len() + decoded));
            out.resize(out.len() + decoded, 0);
        } else {
            block(&bytes[at..at + stored], &mut out)?;
        }
        at += stored;
    }
    Ok((out, skipped))
}

fn block(chunk: &[u8], out: &mut Vec<u8>) -> Result<(), Error> {
    match chunk.first() {
        Some(b'N') => out.extend_from_slice(&chunk[1..]),
        Some(b'Z') => {
            flate2::read::ZlibDecoder::new(&chunk[1..]).read_to_end(out).map_err(|e| format!("inflate: {e}"))?;
        }
        Some(b'E') => return Err("an encrypted block: the key is not something this reader holds".into()),
        other => return Err(format!("unknown block kind {other:?}")),
    }
    Ok(())
}

/// The game's name hash of a path: Bob Jenkins' lookup3 over the upper-cased path with backslashes.
pub fn name_hash(path: &str) -> u64 {
    let normal: Vec<u8> = path.bytes().map(|b| if b == b'/' { b'\\' } else { b.to_ascii_uppercase() }).collect();
    let (c, b) = hashlittle2(&normal, 0, 0);
    (c as u64) << 32 | b as u64
}

fn hashlittle2(key: &[u8], pc: u32, pb: u32) -> (u32, u32) {
    let rot = |x: u32, k: u32| x.rotate_left(k);
    let mut a = 0xdeadbeefu32.wrapping_add(key.len() as u32).wrapping_add(pc);
    let mut b = a;
    let mut c = a.wrapping_add(pb);
    let mix = |a: &mut u32, b: &mut u32, c: &mut u32| {
        *a = a.wrapping_sub(*c);
        *a ^= rot(*c, 4);
        *c = c.wrapping_add(*b);
        *b = b.wrapping_sub(*a);
        *b ^= rot(*a, 6);
        *a = a.wrapping_add(*c);
        *c = c.wrapping_sub(*b);
        *c ^= rot(*b, 8);
        *b = b.wrapping_add(*a);
        *a = a.wrapping_sub(*c);
        *a ^= rot(*c, 16);
        *c = c.wrapping_add(*b);
        *b = b.wrapping_sub(*a);
        *b ^= rot(*a, 19);
        *a = a.wrapping_add(*c);
        *c = c.wrapping_sub(*b);
        *c ^= rot(*b, 4);
        *b = b.wrapping_add(*a);
    };
    let word = |bytes: &[u8]| -> u32 { bytes.iter().enumerate().fold(0u32, |v, (i, byte)| v | (*byte as u32) << (8 * i)) };
    let mut rest = key;
    while rest.len() > 12 {
        a = a.wrapping_add(word(&rest[0..4]));
        b = b.wrapping_add(word(&rest[4..8]));
        c = c.wrapping_add(word(&rest[8..12]));
        mix(&mut a, &mut b, &mut c);
        rest = &rest[12..];
    }
    if rest.is_empty() {
        return (c, b);
    }
    let mut tail = [0u8; 12];
    tail[..rest.len()].copy_from_slice(rest);
    a = a.wrapping_add(word(&tail[0..4]));
    b = b.wrapping_add(word(&tail[4..8]));
    c = c.wrapping_add(word(&tail[8..12]));
    c ^= b;
    c = c.wrapping_sub(rot(b, 14));
    a ^= c;
    a = a.wrapping_sub(rot(c, 11));
    b ^= a;
    b = b.wrapping_sub(rot(a, 25));
    c ^= b;
    c = c.wrapping_sub(rot(b, 16));
    a ^= c;
    a = a.wrapping_sub(rot(c, 4));
    b ^= a;
    b = b.wrapping_sub(rot(a, 14));
    c ^= b;
    c = c.wrapping_sub(rot(b, 24));
    (c, b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_path_hashes_to_what_the_game_root_holds() {
        // Read out of the game's own root file, where this icon's entry carries the hash.
        assert_eq!(name_hash("Interface\\Icons\\INV_Sword_04.blp"), 0x814e3081babfb584);
        assert_eq!(name_hash("interface/icons/inv_sword_04.blp"), 0x814e3081babfb584);
    }

    #[test]
    fn blocks_are_joined_in_order() {
        let mut file = b"BLTE".to_vec();
        file.extend_from_slice(&(12u32 + 2 * 24).to_be_bytes());
        file.extend_from_slice(&[0x0f, 0, 0, 2]);
        for (stored, plain) in [(4u32, 3u32), (3, 2)] {
            file.extend_from_slice(&stored.to_be_bytes());
            file.extend_from_slice(&plain.to_be_bytes());
            file.extend_from_slice(&[0; 16]);
        }
        file.extend_from_slice(b"Nabc");
        file.extend_from_slice(b"Nde");
        assert_eq!(blte(&file).unwrap(), b"abcde");
    }

    #[test]
    fn an_encrypted_block_is_reported_not_guessed() {
        let mut file = b"BLTE".to_vec();
        file.extend_from_slice(&0u32.to_be_bytes());
        file.extend_from_slice(b"Exxxx");
        assert!(blte(&file).unwrap_err().contains("encrypted"));
    }
}
