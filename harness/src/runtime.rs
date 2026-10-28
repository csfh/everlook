//! One running game: a Lua 5.1 state with the widget API, the clock, the addons' files and the small
//! `harness` table a scenario uses to look at the game and push on it. A scenario is a Lua file; it
//! runs against the same globals the addons do, as in the game.

use crate::bind::{self, fire, id_of, make_object, table_of};
use crate::world::{Class, Id, World};
use mlua::{Function, Lua, MultiValue, Table, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;

type Result<T> = mlua::Result<T>;

pub struct Inner {
    pub world: RefCell<World>,
    pub metatables: RefCell<HashMap<Class, Table>>,
    /// Every method a script looked up on a frame and did not find.
    pub missing: RefCell<Vec<String>>,
    /// Every plain field a script read off a frame and found unset, by type and name. Most are an addon
    /// checking whether it has set one yet. A name only the test frames used to have is a bug.
    pub fields_read: RefCell<Vec<String>>,
    /// Templates read from XML, by name.
    pub templates: RefCell<HashMap<String, crate::xml::Tmpl>>,
    /// Template names `CreateFrame` was given that no loaded XML defines: Blizzard's own, not in the harness.
    pub unknown_templates: RefCell<Vec<String>>,
    /// What each secure button was set to do when it was clicked, as `type key=value ...`. The game runs those
    /// actions in its own code; the harness only records them.
    pub secure_log: RefCell<Vec<String>>,
    pub results: RefCell<Vec<(String, bool)>>,
    /// Named pictures of the screen a scenario took on the way, for the static page to switch between.
    pub snapshots: RefCell<Vec<(String, serde_json::Value)>>,
    pub output: RefCell<Vec<String>>,
    pub addons: PathBuf,
}

pub type Shared = Rc<Inner>;

pub struct Harness {
    pub lua: Lua,
    pub shared: Shared,
}

const STEP: f64 = 1.0 / 60.0;

fn rect_table(lua: &Lua, shared: &Shared, id: Id) -> Result<Table> {
    let world = shared.world.borrow();
    let rect = world.rect(id);
    let table = lua.create_table()?;
    table.set("left", rect.left)?;
    table.set("top", rect.top)?;
    table.set("width", rect.width)?;
    table.set("height", rect.height)?;
    table.set("right", rect.right())?;
    table.set("bottom", rect.bottom())?;
    Ok(table)
}

fn require_object(value: &Value, what: &str) -> Result<Id> {
    match value {
        Value::Table(table) => id_of(table).ok_or_else(|| mlua::Error::runtime(format!("{what}: not a frame"))),
        _ => Err(mlua::Error::runtime(format!("{what}: not a frame"))),
    }
}

/// Moves the clock on by `seconds` in sixtieths, running what comes due in the order the game would:
/// timers, animations, then each shown frame's OnUpdate.
pub fn advance(lua: &Lua, shared: &Shared, seconds: f64) -> Result<()> {
    let mut remaining = seconds;
    while remaining > 1e-9 {
        let step = remaining.min(STEP);
        remaining -= step;
        shared.world.borrow_mut().now += step;
        run_timers(lua, shared)?;
        crate::anim::advance(lua, shared, step)?;
        let updating: Vec<Id> = {
            let world = shared.world.borrow();
            (0..world.objs.len())
                .filter(|id| world.objs[*id].class.is_frame() && (world.objs[*id].scripts.contains_key("OnUpdate") || world.objs[*id].hooks.contains_key("OnUpdate")) && world.visible(*id))
                .collect()
        };
        for id in updating {
            fire(lua, shared, id, "OnUpdate", MultiValue::from_iter([Value::Number(step)]))?;
        }
    }
    Ok(())
}

fn run_timers(lua: &Lua, shared: &Shared) -> Result<()> {
    loop {
        let due = {
            let mut world = shared.world.borrow_mut();
            let now = world.now;
            let position = world.timers.iter().position(|timer| !timer.cancelled && timer.due <= now);
            position.map(|index| {
                let timer = &mut world.timers[index];
                let handle = timer.handle;
                let callback = timer.callback.clone();
                match timer.interval {
                    Some(interval) => {
                        timer.due += interval;
                        if let Some(left) = timer.remaining.as_mut() {
                            *left -= 1;
                            if *left == 0 {
                                timer.cancelled = true;
                            }
                        }
                    }
                    None => timer.cancelled = true,
                }
                (handle, callback)
            })
        };
        let Some((handle, callback)) = due else { break };
        let handle_table: Option<Table> = lua.globals().get::<Table>("__timers").ok().and_then(|timers| timers.get::<Option<Table>>(handle).ok().flatten());
        let result = match handle_table {
            Some(table) => callback.call::<MultiValue>(table),
            None => callback.call::<MultiValue>(()),
        };
        if let Err(error) = result {
            shared.world.borrow_mut().errors.push(format!("timer: {error}"));
        }
        shared.world.borrow_mut().timers.retain(|timer| !timer.cancelled);
    }
    Ok(())
}

fn install_timers(lua: &Lua, shared: &Shared) -> Result<()> {
    let handles = lua.create_table()?;
    lua.globals().set("__timers", handles.clone())?;
    let timer_api = lua.create_table()?;
    let add = {
        let shared = shared.clone();
        let handles = handles.clone();
        move |lua: &Lua, delay: f64, callback: Function, interval: Option<f64>, iterations: Option<u32>| -> Result<Table> {
            let mut world = shared.world.borrow_mut();
            let handle = world.next_timer;
            world.next_timer += 1;
            let due = world.now + delay;
            world.timers.push(crate::world::Timer { handle, due, callback, interval, remaining: iterations, cancelled: false });
            drop(world);
            let table = lua.create_table()?;
            let cancel_shared = shared.clone();
            table.set(
                "Cancel",
                lua.create_function(move |_, _: MultiValue| {
                    for timer in cancel_shared.world.borrow_mut().timers.iter_mut() {
                        if timer.handle == handle {
                            timer.cancelled = true;
                        }
                    }
                    Ok(())
                })?,
            )?;
            let query_shared = shared.clone();
            table.set(
                "IsCancelled",
                lua.create_function(move |_, _: MultiValue| Ok(!query_shared.world.borrow().timers.iter().any(|timer| timer.handle == handle && !timer.cancelled)))?,
            )?;
            handles.set(handle, table.clone())?;
            Ok(table)
        }
    };
    let after = add.clone();
    timer_api.set(
        "After",
        lua.create_function(move |lua, (delay, callback): (f64, Function)| {
            after(lua, delay, callback, None, None)?;
            Ok(())
        })?,
    )?;
    let new_timer = add.clone();
    timer_api.set("NewTimer", lua.create_function(move |lua, (delay, callback): (f64, Function)| new_timer(lua, delay, callback, None, None))?)?;
    let new_ticker = add.clone();
    timer_api.set(
        "NewTicker",
        lua.create_function(move |lua, (interval, callback, iterations): (f64, Function, Option<u32>)| new_ticker(lua, interval, callback, Some(interval), iterations))?,
    )?;
    lua.globals().set("C_Timer", timer_api)?;
    Ok(())
}

fn install_game(lua: &Lua, shared: &Shared) -> Result<()> {
    let globals = lua.globals();

    // The game has no io, os, package, require or debug library for addons.
    for name in ["io", "os", "package", "require", "dofile", "loadfile", "debug"] {
        globals.set(name, Value::Nil)?;
    }
    lua.load(include_str!("../prelude/wow.lua")).set_name("prelude/wow.lua").exec()?;

    let clock = shared.clone();
    globals.set("GetTime", lua.create_function(move |_, _: MultiValue| Ok(clock.world.borrow().now))?)?;
    let clock = shared.clone();
    globals.set("GetServerTime", lua.create_function(move |_, _: MultiValue| Ok(1_700_000_000i64 + clock.world.borrow().now as i64))?)?;
    let clock = shared.clone();
    globals.set("time", lua.create_function(move |_, _: MultiValue| Ok(1_700_000_000i64 + clock.world.borrow().now as i64))?)?;

    // Wall-clock milliseconds, as the game's. Scenarios report it and never assert on it.
    let started = std::time::Instant::now();
    globals.set("debugprofilestop", lua.create_function(move |_, _: MultiValue| Ok(started.elapsed().as_secs_f64() * 1000.0))?)?;

    let output = shared.clone();
    globals.set(
        "print",
        lua.create_function(move |_, values: MultiValue| {
            let parts: Vec<String> = values
                .iter()
                .map(|value| match value {
                    Value::String(text) => text.to_string_lossy().to_string(),
                    Value::Nil => "nil".into(),
                    Value::Boolean(flag) => flag.to_string(),
                    Value::Integer(number) => number.to_string(),
                    Value::Number(number) => number.to_string(),
                    other => format!("{}", other.type_name()),
                })
                .collect();
            output.output.borrow_mut().push(parts.join(" "));
            Ok(())
        })?,
    )?;

    install_timers(lua, shared)?;
    bind::build_metatables(lua, shared)?;
    bind::install_fonts(lua, shared)?;

    // UIParent is the screen's root frame. A frame made with no parent hangs from it.
    let root = make_object(lua, shared, Class::Frame, Some("UIParent".into()), None)?;
    shared.world.borrow_mut().globals_named.insert("UIParent".into(), root);
    bind::install_tooltip(lua, shared, root)?;
    // Every frame in the order it was made, one after another: the walk addons use to reach all of them.
    let walk_shared = shared.clone();
    globals.set(
        "EnumerateFrames",
        lua.create_function(move |_, previous: Option<Table>| {
            let world = walk_shared.world.borrow();
            let start = previous.and_then(|table| id_of(&table)).map(|id| id + 1).unwrap_or(0);
            Ok((start..world.objs.len()).find(|id| world.objs[*id].class.is_frame()).map(|id| world.objs[id].table.clone()))
        })?,
    )?;
    // The 3D world behind the interface: what has the mouse when no frame does.
    let world_frame = make_object(lua, shared, Class::Frame, Some("WorldFrame".into()), None)?;
    {
        let mut world = shared.world.borrow_mut();
        world.globals_named.insert("WorldFrame".into(), world_frame);
        world.objs[world_frame].strata = crate::world::Strata::Background;
        world.objs[world_frame].level = 0;
        world.objs[world_frame].all_points = Some(None);
    }
    let foci_shared = shared.clone();
    globals.set(
        "GetMouseFoci",
        lua.create_function(move |lua, _: MultiValue| {
            let world = foci_shared.world.borrow();
            let list = lua.create_table()?;
            let hits = world.hits(world.pointer.0, world.pointer.1, false, true);
            match hits.first() {
                Some(top) => list.push(world.objs[*top].table.clone())?,
                None => list.push(world.objs[world_frame].table.clone())?,
            }
            Ok(list)
        })?,
    )?;
    // The cursor in screen pixels from the bottom left, as the game gives it.
    let cursor_shared = shared.clone();
    globals.set(
        "GetCursorPosition",
        lua.create_function(move |_, _: MultiValue| {
            let world = cursor_shared.world.borrow();
            Ok((world.pointer.0, crate::world::SCREEN_HEIGHT - world.pointer.1))
        })?,
    )?;
    let create_shared = shared.clone();
    globals.set(
        "CreateFrame",
        lua.create_function(move |lua, (kind, name, parent, template, id): (String, Option<String>, Option<Table>, Option<String>, Option<i64>)| {
            let class = bind::frame_class(&kind).ok_or_else(|| mlua::Error::runtime(format!("{}: CreateFrame(\"{kind}\") is not implemented", bind::GAP)))?;
            let parent = match parent {
                Some(table) => Some(id_of(&table).ok_or_else(|| mlua::Error::runtime("CreateFrame(): Wrong object type for function"))?),
                None => Some(root),
            };
            let created = make_object(lua, &create_shared, class, name.clone(), parent)?;
            if let Some(names) = &template {
                crate::xml::apply_named(lua, &create_shared, created, names)?;
            }
            {
                let mut world = create_shared.world.borrow_mut();
                world.objs[created].template = template;
                if let Some(id) = id {
                    world.objs[created].id_number = id;
                }
                if let Some(name) = name {
                    world.globals_named.insert(name, created);
                }
            }
            Ok(table_of(&create_shared, created))
        })?,
    )?;
    Ok(())
}

fn install_harness(lua: &Lua, shared: &Shared) -> Result<()> {
    let table = lua.create_table()?;

    let s = shared.clone();
    table.set(
        "advance",
        lua.create_function(move |lua, seconds: f64| advance(lua, &s, seconds))?,
    )?;
    let s = shared.clone();
    table.set("now", lua.create_function(move |_, _: ()| Ok(s.world.borrow().now))?)?;
    // What the addons have made so far: frames, event registrations, and frames that run an OnUpdate
    // every frame while shown. Counts, not times, so a scenario can hold them to a number.
    let s = shared.clone();
    table.set(
        "census",
        lua.create_function(move |lua, _: ()| {
            let world = s.world.borrow();
            let (mut frames, mut events, mut updating) = (0i64, 0i64, 0i64);
            for obj in &world.objs {
                if obj.class.is_frame() {
                    frames += 1;
                    events += obj.events.len() as i64;
                    if obj.shown && obj.scripts.contains_key("OnUpdate") {
                        updating += 1;
                    }
                }
            }
            let table = lua.create_table()?;
            table.set("frames", frames)?;
            table.set("events", events)?;
            table.set("updating", updating)?;
            Ok(table)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "rect",
        lua.create_function(move |lua, value: Value| {
            let id = require_object(&value, "harness.rect")?;
            rect_table(lua, &s, id)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "center",
        lua.create_function(move |_, value: Value| {
            let id = require_object(&value, "harness.center")?;
            let rect = s.world.borrow().rect(id);
            Ok((rect.left + rect.width / 2.0, rect.top + rect.height / 2.0))
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "hits",
        lua.create_function(move |lua, (x, y): (f32, f32)| {
            let world = s.world.borrow();
            let list = lua.create_table()?;
            for (index, id) in world.hits(x, y, false, false).into_iter().enumerate() {
                list.set(index + 1, world.objs[id].table.clone())?;
            }
            Ok(list)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "hit",
        lua.create_function(move |_, (x, y): (f32, f32)| {
            let world = s.world.borrow();
            Ok(world.hits(x, y, false, false).first().map(|id| world.objs[*id].table.clone()))
        })?,
    )?;
    let s = shared.clone();
    table.set("move", lua.create_function(move |lua, (x, y): (f32, f32)| crate::input::move_to(lua, &s, x, y))?)?;
    let s = shared.clone();
    table.set(
        "click",
        lua.create_function(move |lua, (x, y, button): (f32, f32, Option<String>)| {
            let target = crate::input::click(lua, &s, x, y, &button.unwrap_or_else(|| "LeftButton".into()))?;
            Ok(target.map(|id| s.world.borrow().objs[id].table.clone()))
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "wheel",
        lua.create_function(move |lua, (x, y, delta): (f32, f32, f32)| {
            let target = crate::input::wheel(lua, &s, x, y, delta)?;
            Ok(target.map(|id| s.world.borrow().objs[id].table.clone()))
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "hover",
        lua.create_function(move |lua, value: Value| {
            let id = require_object(&value, "harness.hover")?;
            let rect = s.world.borrow().rect(id);
            crate::input::move_to(lua, &s, rect.left + rect.width / 2.0, rect.top + rect.height / 2.0)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "event",
        lua.create_function(move |lua, values: MultiValue| {
            let mut values = values.into_iter();
            let name = match values.next() {
                Some(Value::String(text)) => text.to_str()?.to_string(),
                _ => return Err(mlua::Error::runtime("harness.event: an event name")),
            };
            let rest: Vec<Value> = values.collect();
            let targets: Vec<Id> = {
                let world = s.world.borrow();
                (0..world.objs.len()).filter(|id| world.objs[*id].events.contains(&name)).collect()
            };
            for id in targets {
                let mut args = vec![Value::String(lua.create_string(&name)?)];
                args.extend(rest.iter().cloned());
                fire(lua, &s, id, "OnEvent", MultiValue::from_iter(args))?;
            }
            Ok(())
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "find",
        lua.create_function(move |_, name: String| {
            let world = s.world.borrow();
            Ok(world.objs.iter().find(|obj| obj.name.as_deref() == Some(name.as_str())).map(|obj| obj.table.clone()))
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "frames",
        lua.create_function(move |lua, _: ()| {
            let world = s.world.borrow();
            let list = lua.create_table()?;
            for obj in world.objs.iter().filter(|obj| obj.class.is_frame()) {
                list.push(obj.table.clone())?;
            }
            Ok(list)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "info",
        lua.create_function(move |lua, value: Value| {
            let id = require_object(&value, "harness.info")?;
            let world = s.world.borrow();
            let obj = &world.objs[id];
            let info = lua.create_table()?;
            info.set("shown", obj.shown)?;
            info.set("visible", world.visible(id))?;
            info.set("alpha", obj.alpha)?;
            info.set("effective_alpha", world.effective_alpha(id))?;
            info.set("strata", obj.strata.name())?;
            info.set("level", obj.level)?;
            info.set("mouse_click", obj.mouse_click)?;
            info.set("mouse_motion", obj.mouse_motion)?;
            info.set("clips", obj.clips)?;
            info.set("text", obj.text.text.clone())?;
            info.set("enabled", obj.enabled)?;
            info.set("highlight_locked", obj.highlight_locked)?;
            info.set("class", obj.class.type_name())?;
            Ok(info)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "errors",
        lua.create_function(move |lua, clear: Option<bool>| {
            let mut world = s.world.borrow_mut();
            let list = lua.create_table()?;
            for error in &world.errors {
                list.push(error.clone())?;
            }
            if clear.unwrap_or(false) {
                world.errors.clear();
            }
            Ok(list)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "missing",
        lua.create_function(move |lua, clear: Option<bool>| {
            let list = lua.create_table()?;
            let mut seen: Vec<String> = Vec::new();
            for name in s.missing.borrow().iter() {
                if !seen.contains(name) {
                    seen.push(name.clone());
                }
            }
            for name in seen {
                list.push(name)?;
            }
            if clear.unwrap_or(false) {
                s.missing.borrow_mut().clear();
            }
            Ok(list)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "fields_read",
        lua.create_function(move |lua, clear: Option<bool>| {
            let list = lua.create_table()?;
            let mut seen: Vec<String> = Vec::new();
            for name in s.fields_read.borrow().iter() {
                if !seen.contains(name) {
                    seen.push(name.clone());
                }
            }
            for name in seen {
                list.push(name)?;
            }
            if clear.unwrap_or(false) {
                s.fields_read.borrow_mut().clear();
            }
            Ok(list)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "snapshot",
        lua.create_function(move |_, name: String| {
            let picture = crate::scene::scene(&s.world.borrow());
            s.snapshots.borrow_mut().push((name, picture));
            Ok(())
        })?,
    )?;
    // Turns candidate rules of the game on or off for what runs next: harness.rules{ clip_needs_mouse = true }.
    let s = shared.clone();
    table.set(
        "rules",
        lua.create_function(move |_, rules: Table| {
            let mut world = s.world.borrow_mut();
            // A rule not named goes back to its default.
            let defaults = crate::world::Rules::default();
            world.rules.clip_needs_mouse = rules.get::<Option<bool>>("clip_needs_mouse")?.unwrap_or(defaults.clip_needs_mouse);
            world.rules.scroll_child_limits = rules.get::<Option<bool>>("scroll_child_limits")?.unwrap_or(defaults.scroll_child_limits);
            world.rules.flatten_clips = rules.get::<Option<bool>>("flatten_clips")?.unwrap_or(defaults.flatten_clips);
            Ok(())
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "secure_log",
        lua.create_function(move |lua, clear: Option<bool>| {
            let list = lua.create_table()?;
            for entry in s.secure_log.borrow().iter() {
                list.push(entry.clone())?;
            }
            if clear.unwrap_or(false) {
                s.secure_log.borrow_mut().clear();
            }
            Ok(list)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "check",
        lua.create_function(move |_, (name, passed): (String, Value)| {
            let passed = !matches!(passed, Value::Nil | Value::Boolean(false));
            s.results.borrow_mut().push((name, passed));
            Ok(passed)
        })?,
    )?;
    let s = shared.clone();
    table.set(
        "load_addon",
        lua.create_function(move |lua, name: String| load_addon(lua, &s, &name))?,
    )?;
    // XML given as text, for a scenario that tests the loader itself.
    let s = shared.clone();
    table.set(
        "load_xml_text",
        lua.create_function(move |lua, text: String| {
            let path = std::env::temp_dir().join(format!("harness-xml-{}.xml", std::process::id()));
            std::fs::write(&path, text).map_err(mlua::Error::external)?;
            let result = crate::xml::load(lua, &s, &path);
            let _ = std::fs::remove_file(&path);
            result
        })?,
    )?;
    // The addon folders in the order the game loads them.
    let s = shared.clone();
    table.set(
        "addons",
        lua.create_function(move |lua, ()| lua.create_sequence_from(load_order(&s.addons).map_err(mlua::Error::external)?))?,
    )?;
    // The key bindings an addon declares in its Bindings.xml, which the game reads apart from the table of contents.
    let s = shared.clone();
    table.set(
        "bindings",
        lua.create_function(move |lua, addon: String| {
            let path = s.addons.join(&addon).join("Bindings.xml");
            let text = std::fs::read_to_string(&path).map_err(|error| mlua::Error::runtime(format!("{}: {error}", path.display())))?;
            let document = roxmltree::Document::parse(&text).map_err(|error| mlua::Error::runtime(error.to_string()))?;
            let list = lua.create_table()?;
            for node in document.root_element().children().filter(|node| node.is_element() && node.tag_name().name() == "Binding") {
                let entry = lua.create_table()?;
                entry.set("name", node.attribute("name"))?;
                entry.set("header", node.attribute("header"))?;
                entry.set("run_on_up", node.attribute("runOnUp") == Some("true"))?;
                entry.set("body", node.text().unwrap_or_default().trim().to_string())?;
                list.push(entry)?;
            }
            Ok(list)
        })?,
    )?;
    // Runs a file of the harness's own (scenarios/lib) in the shared globals, as an addon file would be.
    table.set(
        "include",
        lua.create_function(move |lua, path: String| {
            let full = Path::new(env!("CARGO_MANIFEST_DIR")).join("scenarios").join(&path);
            let source = std::fs::read_to_string(&full).map_err(|error| mlua::Error::runtime(format!("{}: {error}", full.display())))?;
            lua.load(source).set_name(format!("@scenarios/{path}")).exec()
        })?,
    )?;
    let s = shared.clone();
    table.set("output", lua.create_function(move |lua, _: ()| lua.create_sequence_from(s.output.borrow().clone()))?)?;
    lua.globals().set("harness", table)?;
    Ok(())
}

/// The addon folders under `addons` (each a folder with a table of contents of its own name) in the order the
/// game loads them: by name, ignoring case, with the addons named in a folder's `## Dependencies` before it.
pub fn load_order(addons: &Path) -> std::io::Result<Vec<String>> {
    let mut names: Vec<String> = std::fs::read_dir(addons)?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| addons.join(name).join(format!("{name}.toc")).is_file())
        .collect();
    names.sort_by_key(|name| name.to_lowercase());
    let mut order = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for name in &names {
        visit_dependencies_first(addons, name, &mut seen, &mut order)?;
    }
    Ok(order)
}

fn visit_dependencies_first(addons: &Path, name: &str, seen: &mut std::collections::HashSet<String>, order: &mut Vec<String>) -> std::io::Result<()> {
    if !seen.insert(name.to_string()) {
        return Ok(());
    }
    let toc = std::fs::read_to_string(addons.join(name).join(format!("{name}.toc")))?;
    for line in toc.lines() {
        if let Some(list) = line.strip_prefix("## Dependencies:") {
            for dependency in list.split(',').map(str::trim).filter(|dependency| !dependency.is_empty()) {
                visit_dependencies_first(addons, dependency, seen, order)?;
            }
        }
    }
    order.push(name.to_string());
    Ok(())
}

/// Loads an addon the way the game does: each file of its table of contents, in order, with the addon's
/// name and its private table as the file's arguments. Files that are not Lua are named, not skipped.
pub fn load_addon(lua: &Lua, shared: &Shared, name: &str) -> Result<()> {
    let folder = shared.addons.join(name);
    let toc = std::fs::read_to_string(folder.join(format!("{name}.toc"))).map_err(|error| mlua::Error::runtime(format!("{name}.toc: {error}")))?;
    let private: Table = lua.create_table()?;
    for line in toc.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let path = folder.join(line.replace('\\', "/"));
        if line.ends_with(".xml") {
            crate::xml::load(lua, shared, &path)?;
            continue;
        }
        if !line.ends_with(".lua") {
            return Err(mlua::Error::runtime(format!("{}: {name}.toc lists {line}, which is neither Lua nor XML", bind::GAP)));
        }
        let source = std::fs::read_to_string(&path).map_err(|error| mlua::Error::runtime(format!("{}: {error}", path.display())))?;
        let chunk = lua.load(source).set_name(format!("@{name}/{line}"));
        let function = chunk.into_function()?;
        function.call::<()>((name, private.clone()))?;
    }
    // The game then tells the files, and the frames that listen, that the addon is in.
    let notify: Option<Function> = lua.globals().get::<Option<Table>>("EventUtil")?.and_then(|util| util.get::<Option<Function>>("__addon_loaded").ok().flatten());
    if let Some(notify) = notify {
        notify.call::<()>(name)?;
    }
    let harness: Table = lua.globals().get("harness")?;
    let event: Function = harness.get("event")?;
    event.call::<()>(("ADDON_LOADED", name))?;
    Ok(())
}

impl Harness {
    pub fn new(addons: &Path) -> Result<Harness> {
        let lua = Lua::new();
        let shared: Shared = Rc::new(Inner {
            world: RefCell::new(World::new(addons.to_path_buf())),
            metatables: RefCell::new(HashMap::new()),
            missing: RefCell::new(Vec::new()),
            fields_read: RefCell::new(Vec::new()),
            templates: RefCell::new(HashMap::new()),
            unknown_templates: RefCell::new(Vec::new()),
            secure_log: RefCell::new(Vec::new()),
            results: RefCell::new(Vec::new()),
            snapshots: RefCell::new(Vec::new()),
            output: RefCell::new(Vec::new()),
            addons: addons.to_path_buf(),
        });
        install_game(&lua, &shared)?;
        install_harness(&lua, &shared)?;
        Ok(Harness { lua, shared })
    }

    /// Runs a scenario file. Its checks and the errors its scripts raised are what the caller reads.
    pub fn run(&self, path: &Path) -> Result<()> {
        let source = std::fs::read_to_string(path).map_err(|error| mlua::Error::runtime(format!("{}: {error}", path.display())))?;
        self.lua.load(source).set_name(format!("@{}", path.display())).exec()
    }
}
