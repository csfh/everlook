//! Runs every scenario in scenarios/ against the addons next to this repository, and fails on any
//! failed check, any error a script raised, or a call to a part of the game the harness has not built.

use everlook_harness::runtime::Harness;
use std::path::PathBuf;

#[test]
fn scenarios_pass() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let addons = std::env::var("EVERLOOK_ADDONS_DIR").map(PathBuf::from).unwrap_or_else(|_| root.join("../addon"));
    let mut files: Vec<PathBuf> = std::fs::read_dir(root.join("scenarios"))
        .unwrap()
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| path.extension().is_some_and(|extension| extension == "lua"))
        .collect();
    files.sort();
    let mut failures: Vec<String> = Vec::new();
    for file in &files {
        let harness = Harness::new(&addons).expect("the harness starts");
        let outcome = harness.run(file);
        let name = file.file_name().unwrap().to_string_lossy().to_string();
        if let Err(error) = outcome {
            failures.push(format!("{name}: {error}"));
        }
        for (check, passed) in harness.shared.results.borrow().iter() {
            if !passed {
                failures.push(format!("{name}: {check}"));
            }
        }
        for error in harness.shared.world.borrow().errors.iter() {
            failures.push(format!("{name}: script error: {error}"));
        }
    }
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
}
