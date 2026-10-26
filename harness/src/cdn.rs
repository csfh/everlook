//! Files the install lists but does not hold, read from Blizzard's own content servers.
//!
//! The install keeps a copy of the archive indexes the servers publish (`Data/indices`), so where a file sits in a
//! server archive is known without asking. Only the bytes of one file are requested, by range, from the hosts the game's
//! own `.build.info` names. Nothing is stored in the game folder.

use std::collections::HashMap;
use std::path::Path;
use std::process::Command;

use crate::casc::{Error, blte, build_row};

const BLOCK: usize = 4096;
const ENTRY: usize = 24;
const PER_BLOCK: usize = BLOCK / ENTRY;

/// Where a file sits on the servers.
#[derive(Clone, Copy, Debug)]
pub struct Located {
    pub archive: usize,
    pub offset: u32,
    pub size: u32,
}

pub struct Cdn {
    hosts: Vec<String>,
    path: String,
    archives: Vec<String>,
    index: HashMap<[u8; 16], Located>,
}

impl Cdn {
    pub fn open(game: &Path) -> Result<Cdn, Error> {
        let info = std::fs::read_to_string(game.join(".build.info")).map_err(|e| format!(".build.info: {e}"))?;
        let (head, row) = build_row(&info)?;
        let column = |name: &str| head.iter().position(|h| h.split('!').next() == Some(name));
        let (key, path, hosts) = (column("CDN Key").ok_or("no CDN Key column")?, column("CDN Path").ok_or("no CDN Path column")?, column("CDN Hosts").ok_or("no CDN Hosts column")?);
        let cdn_key = row[key];
        let config = std::fs::read_to_string(game.join("Data/config").join(&cdn_key[0..2]).join(&cdn_key[2..4]).join(cdn_key)).map_err(|e| format!("CDN config {cdn_key}: {e}"))?;
        let archives: Vec<String> = config.lines().find_map(|line| line.strip_prefix("archives = ")).ok_or("no archives in the CDN config")?.split_whitespace().map(str::to_string).collect();

        let mut index = HashMap::new();
        for (number, archive) in archives.iter().enumerate() {
            let file = game.join("Data/indices").join(format!("{archive}.index"));
            let Ok(bytes) = std::fs::read(&file) else { continue };
            for (ekey, place) in parse_index(&bytes, number).map_err(|e| format!("{}: {e}", file.display()))? {
                index.insert(ekey, place);
            }
        }
        Ok(Cdn { hosts: row[hosts].split_whitespace().map(str::to_string).collect(), path: row[path].to_string(), archives, index })
    }

    pub fn indexed(&self) -> usize {
        self.index.len()
    }

    pub fn locate(&self, ekey: &[u8; 16]) -> Option<Located> {
        self.index.get(ekey).copied()
    }

    /// A file the servers keep on its own, not inside an archive, by its encoding key, decoded.
    pub fn fetch_loose(&self, ekey: &[u8; 16]) -> Result<Vec<u8>, Error> {
        let name: String = ekey.iter().map(|b| format!("{b:02x}")).collect();
        let mut last = String::from("no host");
        for host in &self.hosts {
            let url = format!("https://{host}/{}/data/{}/{}/{name}", self.path, &name[0..2], &name[2..4]);
            let out = Command::new("curl").args(["-sS", "-f", "-m", "120", &url]).output().map_err(|e| format!("curl: {e}"))?;
            if out.status.success() {
                return blte(&out.stdout);
            }
            last = format!("{host}: {}", String::from_utf8_lossy(&out.stderr).trim());
        }
        Err(last)
    }

    /// The file's blocks decoded. One range request to the first host that answers.
    pub fn fetch(&self, place: Located) -> Result<Vec<u8>, Error> {
        let archive = &self.archives[place.archive];
        let range = format!("{}-{}", place.offset, place.offset as u64 + place.size as u64 - 1);
        let mut last = String::from("no host");
        for host in &self.hosts {
            let url = format!("https://{host}/{}/data/{}/{}/{archive}", self.path, &archive[0..2], &archive[2..4]);
            let out = Command::new("curl").args(["-sS", "-f", "-m", "120", "-r", &range, &url]).output().map_err(|e| format!("curl: {e}"))?;
            if out.status.success() && out.stdout.len() == place.size as usize {
                return blte(&out.stdout);
            }
            last = format!("{host}: {}", String::from_utf8_lossy(&out.stderr).trim());
        }
        Err(last)
    }
}

/// The entries of one archive index: pages of 170 entries (key, size, offset; 24 bytes), then a table of contents and a
/// 28-byte footer. The footer holds the entry count at bytes 16 to 20 and the field widths this reader expects.
fn parse_index(bytes: &[u8], archive: usize) -> Result<Vec<([u8; 16], Located)>, Error> {
    if bytes.len() < 28 {
        return Err("shorter than an index footer".into());
    }
    let footer = &bytes[bytes.len() - 28..];
    if footer[8] != 1 || footer[11] != 4 || footer[12] != 4 || footer[13] != 4 || footer[14] != 16 {
        return Err("an archive index of a format this reader does not know".into());
    }
    let count = u32::from_le_bytes(footer[16..20].try_into().unwrap()) as usize;
    let mut entries = Vec::with_capacity(count);
    for i in 0..count {
        let at = (i / PER_BLOCK) * BLOCK + (i % PER_BLOCK) * ENTRY;
        let entry = bytes.get(at..at + ENTRY).ok_or_else(|| format!("entry {i} runs past the file"))?;
        let (size, offset) = (u32::from_be_bytes(entry[16..20].try_into().unwrap()), u32::from_be_bytes(entry[20..24].try_into().unwrap()));
        entries.push((entry[..16].try_into().unwrap(), Located { archive, offset, size }));
    }
    Ok(entries)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An index of `count` entries whose keys are their numbers, in pages of 170, with a footer.
    fn index(count: usize) -> Vec<u8> {
        let pages = count.div_ceil(PER_BLOCK);
        let mut bytes = vec![0u8; pages * BLOCK];
        for i in 0..count {
            let at = (i / PER_BLOCK) * BLOCK + (i % PER_BLOCK) * ENTRY;
            bytes[at + 15] = i as u8;
            bytes[at + 16..at + 20].copy_from_slice(&(100 + i as u32).to_be_bytes());
            bytes[at + 20..at + 24].copy_from_slice(&(1000 * i as u32).to_be_bytes());
        }
        bytes.extend_from_slice(&vec![0u8; pages * 24]);
        let mut footer = vec![0u8; 28];
        footer[8..15].copy_from_slice(&[1, 0, 0, 4, 4, 4, 16]);
        footer[15] = 8;
        footer[16..20].copy_from_slice(&(count as u32).to_le_bytes());
        bytes.extend_from_slice(&footer);
        bytes
    }

    #[test]
    fn reads_entries_across_pages_with_the_count_from_the_footer() {
        let entries = parse_index(&index(171), 3).unwrap();
        assert_eq!(entries.len(), 171);
        let (key, place) = &entries[170];
        assert_eq!((key[15], place.archive, place.size, place.offset), (170, 3, 270, 170_000));
    }

    #[test]
    fn refuses_a_format_it_does_not_know() {
        let mut bytes = index(2);
        let at = bytes.len() - 28 + 14;
        bytes[at] = 9;
        assert!(parse_index(&bytes, 0).unwrap_err().contains("does not know"));
        assert!(parse_index(&[0; 10], 0).is_err());
    }
}
