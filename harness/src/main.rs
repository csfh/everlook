use everlook_harness::{gen_api, runtime::Harness};
use std::path::PathBuf;

fn usage() -> ! {
    eprintln!("usage: harness gen-api <wow-ui-source dir>\n       harness run <scenario.lua> [--addons <dir>]\n       harness render <scenario.lua> <out.html> [--addons <dir>]\n       harness serve <scenario.lua> [--port 7777] [--addons <dir>]\n       harness casc <game dir> info | id <file id> <out> | path <game path> <out> | scan <magic> | find <text> | findvalue <number> | blpcolumns [file id] | sparse <file id> | filestatus <table file id> <column> | instances <out.json> | maplayouts <out dir> [png] | unreadable [files] | magics [magic: list its ids] | cdnplan [ids] | cdnfetch <out dir> <first id> <last id> [tables] | locked | hotfix <DBCache.bin> | lenient <file id> <out> | db2 <file id> <out.json> [rows] | worldmaps <id, name and optional folder per line> <out dir> | stitch <layout.json> <out.png>");
    std::process::exit(2);
}

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    match arguments.get(1).map(String::as_str) {
        Some("gen-api") => {
            let source = PathBuf::from(arguments.get(2).unwrap_or_else(|| usage()));
            match gen_api::generate(&source, &PathBuf::from("api/widgets.json")) {
                Ok(count) => println!("wrote api/widgets.json from {count} documentation tables"),
                Err(error) => {
                    eprintln!("gen-api failed: {error}");
                    std::process::exit(1);
                }
            }
            match gen_api::generate_fonts(&source, &PathBuf::from("api/fonts.json")) {
                Ok(count) => println!("wrote api/fonts.json with {count} font objects"),
                Err(error) => {
                    eprintln!("gen-api (fonts) failed: {error}");
                    std::process::exit(1);
                }
            }
        }
        Some("run") => {
            let scenario = PathBuf::from(arguments.get(2).unwrap_or_else(|| usage()));
            let addons = arguments.iter().position(|argument| argument == "--addons").and_then(|index| arguments.get(index + 1)).map(PathBuf::from).unwrap_or_else(|| PathBuf::from("../addon"));
            std::process::exit(run(&scenario, &addons));
        }
        Some("render") => {
            let scenario = PathBuf::from(arguments.get(2).unwrap_or_else(|| usage()));
            let output = PathBuf::from(arguments.get(3).unwrap_or_else(|| usage()));
            let addons = addons_from(&arguments);
            let harness = start(&scenario, &addons);
            let mut assets = everlook_harness::render::Assets::new(&addons);
            let title = scenario.file_stem().map(|stem| stem.to_string_lossy().to_string()).unwrap_or_default();
            let page = everlook_harness::render::page(&harness.shared.world.borrow(), &harness.shared.snapshots.borrow(), &mut assets, false, &title);
            std::fs::write(&output, page).expect("the page is written");
            println!("wrote {}", output.display());
        }
        Some("serve") => {
            let scenario = PathBuf::from(arguments.get(2).unwrap_or_else(|| usage()));
            let port = arguments.iter().position(|argument| argument == "--port").and_then(|index| arguments.get(index + 1)).and_then(|port| port.parse().ok()).unwrap_or(7777);
            let harness = start(&scenario, &addons_from(&arguments));
            let title = scenario.file_stem().map(|stem| stem.to_string_lossy().to_string()).unwrap_or_default();
            if let Err(error) = everlook_harness::serve::serve(&harness, port, &title) {
                eprintln!("serve failed: {error}");
                std::process::exit(1);
            }
        }
        Some("casc") => {
            let game = PathBuf::from(arguments.get(2).unwrap_or_else(|| usage()));
            std::process::exit(casc(&game, &arguments[3..]));
        }
        _ => usage(),
    }
}

/// Reads one file out of the game's own storage: a `.png` output decodes a texture, anything else is the raw file.
fn casc(game: &PathBuf, arguments: &[String]) -> i32 {
    let storage = match everlook_harness::casc::Casc::open(game) {
        Ok(storage) => storage,
        Err(error) => {
            eprintln!("casc: {error}");
            return 1;
        }
    };
    let (bytes, out) = match arguments.first().map(String::as_str) {
        Some("info") => {
            println!("build {}: {} files", storage.build, storage.file_count());
            return 0;
        }
        Some("worldmaps") => {
            let (Some(list), Some(out)) = (arguments.get(1), arguments.get(2)) else { usage() };
            let list = std::fs::read_to_string(list).unwrap_or_else(|error| {
                eprintln!("casc: {list}: {error}");
                std::process::exit(1)
            });
            let mut failed = 0;
            for line in list.lines().filter(|line| !line.trim().is_empty()) {
                let mut columns = line.split('\t');
                let (Some(id), Some(name)) = (columns.next(), columns.next()) else { continue };
                match everlook_harness::stitch::world_map(&storage, name, columns.next()) {
                    Ok((folder, image)) => {
                        match image.save(format!("{out}/{id}.png")) {
                            Ok(()) => println!("{id}\t{name}\t{folder}"),
                            Err(error) => {
                                eprintln!("{id}\t{name}\t{error}");
                                failed += 1;
                            }
                        }
                    }
                    Err(error) => {
                        eprintln!("{id}\t{name}\t{error}");
                        failed += 1;
                    }
                }
            }
            return if failed == 0 { 0 } else { 1 };
        }
        Some("scan") => {
            let magic = arguments.get(1).unwrap_or_else(|| usage()).as_bytes();
            for id in storage.ids() {
                let Ok(head) = storage.read_head(id, 192) else { continue };
                if magic == b"BLP2" && head.len() >= 20 && head.starts_with(magic) {
                    let word = |at: usize| u32::from_le_bytes(head[at..at + 4].try_into().unwrap());
                    println!("{id}\t{}\t{}\t{}", word(12), word(16), head[8]);
                } else if head.len() >= 160 && head.starts_with(magic) {
                    let word = |at: usize| u32::from_le_bytes(head[at..at + 4].try_into().unwrap());
                    println!("{id}\trecords {}\tfields {}\trecord size {}\ttable hash {:08x}\tlayout hash {:08x}", word(136), word(140), word(144), word(152), word(156));
                }
            }
            return 0;
        }
        Some("find") => {
            // Which tables hold this text in their string table: how a table is recognised with no list of names.
            let text = arguments.get(1).unwrap_or_else(|| usage());
            for id in storage.ids() {
                let Ok(head) = storage.read_head(id, 192) else { continue };
                if head.len() < 192 || !head.starts_with(b"WDC5") || head[136..140] == [0; 4] {
                    continue;
                }
                let Ok((bytes, skipped)) = storage.read_id_lenient(id) else { continue };
                let Ok(table) = everlook_harness::db2::Table::parse(&bytes, &skipped) else { continue };
                if table.sections.iter().any(|section| section.has_string(text)) {
                    println!("{id}\trows {}\tcolumns {}\trecord size {}\tlayout hash {:08x}", table.rows().count(), table.columns.len(), table.record_size, table.layout_hash);
                }
            }
            return 0;
        }
        Some("sparse") => {
            // A table of variable-length records: each one's id, size and the text inside it.
            let id: u32 = arguments.get(1).and_then(|id| id.parse().ok()).unwrap_or_else(|| usage());
            let limit = arguments.get(2).and_then(|n| n.parse::<usize>().ok()).unwrap_or(20);
            let parsed = storage.read_id_lenient(id).and_then(|(bytes, skipped)| everlook_harness::db2::Table::parse(&bytes, &skipped));
            let table = match parsed {
                Ok(table) => table,
                Err(error) => {
                    eprintln!("casc: file {id}: {error}");
                    return 1;
                }
            };
            for (row, bytes) in table.sparse_records().take(limit) {
                let text: Vec<String> = bytes.split(|b| *b == 0).filter(|part| part.len() >= 3 && part.iter().all(|b| (0x20..0x7f).contains(b))).map(|part| String::from_utf8_lossy(part).into_owned()).collect();
                let words: Vec<u32> = bytes.chunks_exact(4).map(|c| u32::from_le_bytes(c.try_into().unwrap())).take(8).collect();
                println!("{row}\t{} bytes\t{words:?}\t{text:?}", bytes.len());
            }
            return 0;
        }
        Some("filestatus") => {
            // For a table's column of file ids: how many distinct files read as a texture, are not stored locally, are
            // encrypted, or are something else (five of each, or every id with `all`). Nothing is decrypted.
            let (Some(table_id), Some(column)) = (arguments.get(1).and_then(|n| n.parse::<u32>().ok()), arguments.get(2).and_then(|n| n.parse::<usize>().ok())) else { usage() };
            let parsed = storage.read_id_lenient(table_id).and_then(|(bytes, skipped)| everlook_harness::db2::Table::parse(&bytes, &skipped));
            let table = match parsed {
                Ok(table) => table,
                Err(error) => {
                    eprintln!("casc: file {table_id}: {error}");
                    return 1;
                }
            };
            let files: std::collections::BTreeSet<u64> = table.rows().flat_map(|row| row.numbers(column)).filter(|file| *file != 0).collect();
            let mut counts: std::collections::BTreeMap<String, Vec<u64>> = std::collections::BTreeMap::new();
            for file in &files {
                let status = match u32::try_from(*file).map_err(|e| e.to_string()).and_then(|id| storage.read_head(id, 4)) {
                    Ok(head) if head.starts_with(b"BLP2") => "texture".to_string(),
                    Ok(_) => "another kind of file".to_string(),
                    Err(error) if error.contains("encrypted") => "encrypted".to_string(),
                    Err(error) if error.contains("local index") => "not stored locally".to_string(),
                    Err(error) if error.contains("not in the root") => "not in the root".to_string(),
                    Err(error) => error.chars().take(50).collect(),
                };
                counts.entry(status).or_default().push(*file);
            }
            println!("{} distinct files in column {column} of {table_id}", files.len());
            for (status, list) in counts {
                let shown = if arguments.get(3).map(String::as_str) == Some("all") { list.len() } else { list.len().min(5) };
                println!("{}\t{status}\t{:?}", list.len(), &list[..shown]);
            }
            return 0;
        }
        Some("instances") => {
            // Every dungeon and raid with its entrance and its bosses in order, as JSON.
            let out = arguments.get(1).unwrap_or_else(|| usage());
            return match everlook_harness::instances::read(&storage).and_then(|value| std::fs::write(out, serde_json::to_string_pretty(&value).unwrap()).map_err(|e| e.to_string())) {
                Ok(()) => {
                    println!("wrote {out}");
                    0
                }
                Err(error) => {
                    eprintln!("casc: {error}");
                    1
                }
            };
        }
        Some("maplayouts") => {
            // Every map region's layout from the tables, as <out dir>/<region id>.json; with `png`, its full picture too.
            let out = arguments.get(1).unwrap_or_else(|| usage());
            let png = arguments.get(2).map(String::as_str) == Some("png");
            if let Err(error) = std::fs::create_dir_all(out) {
                eprintln!("casc: {out}: {error}");
                return 1;
            }
            let layouts = match everlook_harness::maps::layouts(&storage) {
                Ok(layouts) => layouts,
                Err(error) => {
                    eprintln!("casc: {error}");
                    return 1;
                }
            };
            let mut failed = 0;
            for (region, layout) in &layouts {
                if let Err(error) = std::fs::write(format!("{out}/{region}.json"), serde_json::to_string_pretty(layout).unwrap()) {
                    eprintln!("{region}\t{error}");
                    failed += 1;
                    continue;
                }
                if png {
                    let result = serde_json::from_value::<everlook_harness::stitch::Layout>(layout.clone()).map_err(|e| e.to_string()).and_then(|l| everlook_harness::stitch::stitch(&storage, &l)).and_then(|image| image.save(format!("{out}/{region}.png")).map_err(|e| e.to_string()));
                    if let Err(error) = result {
                        eprintln!("{region}\t{error}");
                        failed += 1;
                    }
                }
            }
            println!("{} map layouts{}, {failed} failed", layouts.len(), if png { " and pictures" } else { "" });
            return if failed == 0 { 0 } else { 1 };
        }
        Some("unreadable") => {
            // Root entries stored locally whose first blocks do not read: why, and for the encrypted ones, which key.
            let mut by_reason: std::collections::BTreeMap<String, u32> = std::collections::BTreeMap::new();
            let mut by_key: std::collections::BTreeMap<u64, (u32, usize, u32)> = std::collections::BTreeMap::new();
            let absent: std::collections::HashSet<u32> = storage.missing().into_iter().map(|(id, _)| id).collect();
            for id in storage.ids() {
                if absent.contains(&id) {
                    continue;
                }
                let Err(error) = storage.read_head(id, 4) else { continue };
                let reason: String = error.chars().take(60).collect();
                *by_reason.entry(reason).or_default() += 1;
                if let Ok(stored) = storage.stored(id) {
                    let keys = everlook_harness::casc::blte_keys(&stored);
                    if arguments.get(1).map(String::as_str) == Some("files") {
                        println!("{id}\t{} bytes stored\t{} encrypted bytes\tkey {:016x}", stored.len(), keys.iter().map(|k| k.1).sum::<usize>(), keys.first().map(|k| k.0).unwrap_or(0));
                    }
                    for (key, size) in keys {
                        let entry = by_key.entry(key).or_default();
                        entry.0 += 1;
                        entry.1 += size;
                        entry.2 = entry.2.max(id);
                    }
                }
            }
            for (reason, count) in &by_reason {
                println!("{count}\t{reason}");
            }
            for (key, (blocks, bytes, last)) in by_key {
                println!("key {key:016x}\t{blocks} blocks\t{bytes} bytes\tlast id {last}");
            }
            return 0;
        }
        Some("magics") => {
            // How many files start with each four bytes: which formats the storage holds.
            let mut counts: std::collections::BTreeMap<[u8; 4], u32> = std::collections::BTreeMap::new();
            let wanted = arguments.get(1).map(|m| m.as_bytes().to_vec());
            for id in storage.ids() {
                if let Ok(head) = storage.read_head(id, 4) {
                    if wanted.as_ref().is_some_and(|m| head.starts_with(m)) {
                        println!("{id}");
                    }
                    if head.len() >= 4 {
                        *counts.entry([head[0], head[1], head[2], head[3]]).or_default() += 1;
                    }
                }
            }
            let mut counts: Vec<_> = counts.into_iter().collect();
            counts.sort_by(|a, b| b.1.cmp(&a.1));
            for (magic, count) in counts.into_iter().take(40) {
                let text: String = magic.iter().map(|b| if (0x20..0x7f).contains(b) { *b as char } else { '.' }).collect();
                println!("{count}\t{text}\t{:02x}{:02x}{:02x}{:02x}", magic[0], magic[1], magic[2], magic[3]);
            }
            return 0;
        }
        Some("cdnplan") => {
            // Which listed files the install does not hold, and where the servers keep them: no download.
            let cdn = match everlook_harness::cdn::Cdn::open(game) {
                Ok(cdn) => cdn,
                Err(error) => {
                    eprintln!("casc: {error}");
                    return 1;
                }
            };
            let missing = storage.missing();
            let (mut found, mut bytes, mut largest) = (0usize, 0u64, 0u32);
            let list = arguments.get(1).map(String::as_str) == Some("ids");
            for (id, ekey) in &missing {
                if list {
                    let name: String = ekey.iter().map(|b| format!("{b:02x}")).collect();
                    println!("{id}\t{}\t{name}", cdn.locate(ekey).map(|place| place.size.to_string()).unwrap_or_else(|| "loose".into()));
                }
                if let Some(place) = cdn.locate(ekey) {
                    found += 1;
                    bytes += place.size as u64;
                    largest = largest.max(place.size);
                }
            }
            println!("{} listed but not local; {} in the {} indexed server files ({} bytes, largest {}); {} not in an archive index", missing.len(), found, cdn.indexed(), bytes, largest, missing.len() - found);
            return 0;
        }
        Some("cdnfetch") => {
            // Missing files in an id range, fetched from the servers and decoded into <out dir>/<id>.bin.
            let (Some(out), Some(from), Some(to)) = (arguments.get(1), arguments.get(2).and_then(|n| n.parse::<u32>().ok()), arguments.get(3).and_then(|n| n.parse::<u32>().ok())) else { usage() };
            let cdn = match everlook_harness::cdn::Cdn::open(game) {
                Ok(cdn) => cdn,
                Err(error) => {
                    eprintln!("casc: {error}");
                    return 1;
                }
            };
            if let Err(error) = std::fs::create_dir_all(out) {
                eprintln!("casc: {out}: {error}");
                return 1;
            }
            // A fifth word, `tables`, keeps only the database tables among them.
            let tables_only = arguments.get(4).map(String::as_str) == Some("tables");
            let (mut got, mut failed) = (0, 0);
            for (id, ekey) in storage.missing().into_iter().filter(|(id, _)| (from..=to).contains(id)) {
                // A file in no archive index is one the servers keep on its own.
                let result = match cdn.locate(&ekey) {
                    Some(place) => cdn.fetch(place),
                    None => cdn.fetch_loose(&ekey),
                };
                match result {
                    Ok(bytes) if tables_only && !bytes.starts_with(b"WDC5") => {}
                    Ok(bytes) => match std::fs::write(format!("{out}/{id}.bin"), bytes) {
                        Ok(()) => got += 1,
                        Err(error) => eprintln!("{id}\t{error}"),
                    },
                    Err(error) => {
                        eprintln!("{id}\t{error}");
                        failed += 1;
                    }
                }
            }
            println!("fetched {got}, failed {failed}");
            return 0;
        }
        Some("locked") => {
            // Tables with encrypted sections: the rows their headers count against the rows that could be read.
            for id in storage.ids() {
                let Ok(head) = storage.read_head(id, 192) else { continue };
                if head.len() < 192 || !head.starts_with(b"WDC5") {
                    continue;
                }
                let Ok((bytes, skipped)) = storage.read_id_lenient(id) else { continue };
                let Ok(table) = everlook_harness::db2::Table::parse(&bytes, &skipped) else { continue };
                let (listed, readable) = table.listed_rows();
                if table.encrypted_sections() > 0 {
                    println!("{id}\tlisted {listed}\treadable {readable}\tlocked sections {}\tlayout hash {:08x}", table.encrypted_sections(), table.layout_hash);
                }
            }
            return 0;
        }
        Some("hotfix") => {
            // The tables the client's hotfix cache names, and which of them are in the local file storage.
            let path = arguments.get(1).unwrap_or_else(|| usage());
            let cache = match std::fs::read(path).map_err(|e| e.to_string()).and_then(|bytes| everlook_harness::hotfix::Cache::parse(&bytes)) {
                Ok(cache) => cache,
                Err(error) => {
                    eprintln!("casc: {path}: {error}");
                    return 1;
                }
            };
            let mut files: std::collections::HashMap<u32, u32> = std::collections::HashMap::new();
            for id in storage.ids() {
                let Ok(head) = storage.read_head(id, 192) else { continue };
                if head.len() >= 160 && head.starts_with(b"WDC5") {
                    files.insert(u32::from_le_bytes(head[152..156].try_into().unwrap()), id);
                }
            }
            if !storage.build.ends_with(&format!(".{}", cache.build)) {
                eprintln!("casc: the cache is of build {} but the files are of build {}: its rows belong to another build", cache.build, storage.build);
            }
            println!("cache of build {}: {} entries", cache.build, cache.entries.len());
            for (hash, all, valid) in cache.tables() {
                let file = files.get(&hash).map(|id| id.to_string()).unwrap_or_else(|| "no readable local table has this hash".into());
                println!("{hash:08x}\t{all} entries\t{valid} with data\t{file}");
            }
            return 0;
        }
        Some("lenient") => {
            // A file with its encrypted blocks as zeros, so the headers of an encrypted table can be read.
            let (Some(id), Some(out)) = (arguments.get(1).and_then(|id| id.parse::<u32>().ok()), arguments.get(2)) else { usage() };
            return match storage.read_id_lenient(id) {
                Ok((bytes, skipped)) => {
                    println!("{} bytes, {} encrypted ranges: {skipped:?}", bytes.len(), skipped.len());
                    std::fs::write(out, bytes).map(|()| 0).unwrap_or(1)
                }
                Err(error) => {
                    eprintln!("casc: {error}");
                    1
                }
            };
        }
        Some("findvalue") => {
            // Every table cell that holds this number: how a known fact is traced back to the table it lives in.
            let wanted: u64 = arguments.get(1).and_then(|n| n.parse().ok()).unwrap_or_else(|| usage());
            for id in storage.ids() {
                let Ok(head) = storage.read_head(id, 192) else { continue };
                if head.len() < 192 || !head.starts_with(b"WDC5") {
                    continue;
                }
                let Ok((bytes, skipped)) = storage.read_id_lenient(id) else { continue };
                let Ok(table) = everlook_harness::db2::Table::parse(&bytes, &skipped) else { continue };
                for row in table.rows() {
                    for column in 0..table.columns.len() {
                        if row.numbers(column).contains(&wanted) {
                            println!("{id}\tcolumn {column}\trow {}\tparent {:?}\trows {}\tlayout hash {:08x}", row.id, row.parent(), table.rows().count(), table.layout_hash);
                        }
                    }
                }
            }
            return 0;
        }
        Some("blpcolumns") => {
            // Which table columns hold the id of a texture file: a column whose values are nearly all ids of BLP files.
            let mut textures: std::collections::HashMap<u64, bool> = std::collections::HashMap::new();
            // With a table id, every column of that table is reported, whatever its share.
            let only: Option<u32> = arguments.get(1).and_then(|id| id.parse().ok());
            for id in storage.ids().into_iter().filter(|id| only.is_none_or(|only| only == *id)) {
                let Ok(head) = storage.read_head(id, 192) else { continue };
                if head.len() < 192 || !head.starts_with(b"WDC5") {
                    continue;
                }
                let Ok((bytes, skipped)) = storage.read_id_lenient(id) else { continue };
                let table = match everlook_harness::db2::Table::parse(&bytes, &skipped) {
                    Ok(table) => table,
                    Err(error) => {
                        eprintln!("{id}\tnot read: {error}");
                        continue;
                    }
                };
                for column in 0..table.columns.len() {
                    let (mut set, mut hit) = (0u32, 0u32);
                    for row in table.rows().take(3000) {
                        for value in row.numbers(column) {
                            if value == 0 {
                                continue;
                            }
                            set += 1;
                            let is_texture = *textures.entry(value).or_insert_with(|| value <= u32::MAX as u64 && storage.read_head(value as u32, 4).is_ok_and(|head| head.starts_with(b"BLP2")));
                            hit += is_texture as u32;
                        }
                    }
                    if only.is_some() || (set >= 50 && hit * 10 >= set * 9) {
                        println!("{id}\tcolumn {column}\trows {}\tset {set}\ttextures {hit}\tlayout hash {:08x}", table.rows().count(), table.layout_hash);
                    }
                }
            }
            return 0;
        }
        Some("db2") => {
            // One table as JSON: each column as numbers, and as text too when it reads as an offset to a string.
            let (Some(id), Some(out)) = (arguments.get(1).and_then(|id| id.parse::<u32>().ok()), arguments.get(2)) else { usage() };
            let limit = arguments.get(3).and_then(|n| n.parse::<usize>().ok()).unwrap_or(usize::MAX);
            let parsed = storage.read_id_lenient(id).and_then(|(bytes, skipped)| everlook_harness::db2::Table::parse(&bytes, &skipped));
            let table = match parsed {
                Ok(table) => table,
                Err(error) => {
                    eprintln!("casc: file {id}: {error}");
                    return 1;
                }
            };
            let rows: Vec<serde_json::Value> = table
                .rows()
                .take(limit)
                .map(|row| {
                    let columns: Vec<serde_json::Value> = (0..table.columns.len())
                        .map(|c| match row.string(c).filter(|text| !text.is_empty() && text.chars().all(|ch| !ch.is_control() || ch == '\n')) {
                            Some(text) if table.columns[c].size_bits == 32 => serde_json::json!({ "s": text, "n": row.numbers(c) }),
                            _ => serde_json::json!(row.numbers(c)),
                        })
                        .collect();
                    serde_json::json!({ "id": row.id, "parent": row.parent(), "columns": columns })
                })
                .collect();
            let columns: Vec<_> = table.columns.iter().map(|c| serde_json::json!({ "offsetBits": c.offset_bits, "sizeBits": c.size_bits, "storage": format!("{:?}", c.storage) })).collect();
            let document = serde_json::json!({
                "build": storage.build, "file": id, "tableHash": format!("{:08x}", table.table_hash), "layoutHash": format!("{:08x}", table.layout_hash),
                "recordSize": table.record_size, "encryptedSections": table.encrypted_sections(), "sections": table.section_sizes(), "columns": columns, "rows": rows,
            });
            return match std::fs::write(out, serde_json::to_string_pretty(&document).unwrap()) {
                Ok(()) => {
                    println!("wrote {out}");
                    0
                }
                Err(error) => {
                    eprintln!("casc: {error}");
                    1
                }
            };
        }
        Some("stitch") => {
            let (Some(layout), Some(out)) = (arguments.get(1), arguments.get(2)) else { usage() };
            let layout: everlook_harness::stitch::Layout = match std::fs::read_to_string(layout).map_err(|e| e.to_string()).and_then(|text| serde_json::from_str(&text).map_err(|e| e.to_string())) {
                Ok(layout) => layout,
                Err(error) => {
                    eprintln!("casc: {layout}: {error}");
                    return 1;
                }
            };
            return match everlook_harness::stitch::stitch(&storage, &layout).and_then(|image| image.save(out).map_err(|e| e.to_string())) {
                Ok(()) => {
                    println!("wrote {out}");
                    0
                }
                Err(error) => {
                    eprintln!("casc: {error}");
                    1
                }
            };
        }
        Some("id") => {
            let id: u32 = arguments.get(1).and_then(|id| id.parse().ok()).unwrap_or_else(|| usage());
            (storage.read_id(id), arguments.get(2).unwrap_or_else(|| usage()))
        }
        Some("path") => {
            let path = arguments.get(1).unwrap_or_else(|| usage());
            let Some(id) = storage.id_of(path) else {
                eprintln!("casc: no file at {path}");
                return 1;
            };
            println!("{path} is file {id}");
            (storage.read_id(id), arguments.get(2).unwrap_or_else(|| usage()))
        }
        _ => usage(),
    };
    let bytes = match bytes {
        Ok(bytes) => bytes,
        Err(error) => {
            eprintln!("casc: {error}");
            return 1;
        }
    };
    let written = if out.ends_with(".png") {
        everlook_harness::blp::decode(&bytes).and_then(|image| image.save(out).map_err(|error| error.to_string()))
    } else {
        std::fs::write(out, &bytes).map_err(|error| error.to_string())
    };
    match written {
        Ok(()) => {
            println!("wrote {out}");
            0
        }
        Err(error) => {
            eprintln!("casc: {error}");
            1
        }
    }
}

fn addons_from(arguments: &[String]) -> PathBuf {
    arguments.iter().position(|argument| argument == "--addons").and_then(|index| arguments.get(index + 1)).map(PathBuf::from).unwrap_or_else(|| PathBuf::from("../addon"))
}

/// Starts the game and runs a scenario into it, then hands the game back, whatever the scenario's checks said.
fn start(scenario: &PathBuf, addons: &PathBuf) -> Harness {
    let harness = Harness::new(addons).unwrap_or_else(|error| {
        eprintln!("harness failed to start: {error}");
        std::process::exit(1);
    });
    if let Err(error) = harness.run(scenario) {
        eprintln!("scenario stopped: {error}");
    }
    for error in harness.shared.world.borrow().errors.iter() {
        eprintln!("script error: {error}");
    }
    harness.shared.world.borrow_mut().errors.clear();
    harness
}

fn run(scenario: &PathBuf, addons: &PathBuf) -> i32 {
    let harness = match Harness::new(addons) {
        Ok(harness) => harness,
        Err(error) => {
            eprintln!("harness failed to start: {error}");
            return 1;
        }
    };
    let outcome = harness.run(scenario);
    for line in harness.shared.output.borrow().iter() {
        println!("{line}");
    }
    let mut failed = 0;
    for (name, passed) in harness.shared.results.borrow().iter() {
        println!("{} {name}", if *passed { "ok  " } else { "FAIL" });
        if !*passed {
            failed += 1;
        }
    }
    for error in harness.shared.world.borrow().errors.iter() {
        println!("ERROR {error}");
        failed += 1;
    }
    if let Err(error) = outcome {
        println!("ERROR {error}");
        failed += 1;
    }
    if failed > 0 { 1 } else { 0 }
}
