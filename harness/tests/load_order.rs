//! The game loads addons by name, ignoring case, each after the addons its table of contents depends on.

use everlook_harness::runtime::load_order;

#[test]
fn an_addon_loads_by_name_after_what_it_depends_on() {
    let addons = std::env::temp_dir().join(format!("harness-load-order-{}", std::process::id()));
    for (name, toc) in [("Alpha", Some("## Dependencies: Zulu\n")), ("beta", Some("")), ("Zulu", Some("")), ("scripts", None)] {
        let folder = addons.join(name);
        std::fs::create_dir_all(&folder).unwrap();
        if let Some(toc) = toc {
            std::fs::write(folder.join(format!("{name}.toc")), toc).unwrap();
        }
    }
    let order = load_order(&addons);
    std::fs::remove_dir_all(&addons).unwrap();
    assert_eq!(order.unwrap(), ["Zulu", "Alpha", "beta"]);
}
