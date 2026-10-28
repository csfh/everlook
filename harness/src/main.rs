use everlook_harness::{gen_api, runtime::Harness};
use std::path::PathBuf;

fn usage() -> ! {
    eprintln!("usage: harness gen-api <wow-ui-source dir>\n       harness run <scenario.lua> [--addons <dir>]\n       harness render <scenario.lua> <out.html> [--addons <dir>]\n       harness serve <scenario.lua> [--port 7777] [--addons <dir>]");
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
        _ => usage(),
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
