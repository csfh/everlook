//! The widget API as Lua sees it. A frame is a plain Lua table with its id at `[0]` and a metatable
//! that looks methods up in the table for its type, so an addon can hang its own fields on a frame as it
//! can in the game, and a field it never wrote reads as nil.
//!
//! Which methods a type has comes from Blizzard's documentation (`api`). A documented method this file
//! does not implement raises a harness gap, which is not the same thing as the game having no such method:
//! that is an ordinary nil call.

use crate::api::{self, Signature};
use crate::runtime::Shared;
use crate::world::{AnimKind, Anchor, Class, Id, Point, Rect, Strata, TipLine, SCREEN_HEIGHT};
use mlua::{Function, IntoLuaMulti, Lua, MultiValue, Table, Value};
use std::collections::HashMap;

type Result<T> = mlua::Result<T>;
type Impl = Box<dyn Fn(&Lua, &Shared, &Args) -> Result<MultiValue>>;

/// The marker a harness gap carries, so a scenario can tell it from an error in the addon.
pub const GAP: &str = "HARNESS GAP";

pub struct Args {
    pub values: Vec<Value>,
}

impl Args {
    pub fn me(&self) -> Result<Id> {
        match self.values.first() {
            Some(Value::Table(table)) => id_of(table).ok_or_else(|| mlua::Error::runtime("Wrong object type for function")),
            _ => Err(mlua::Error::runtime("Wrong object type for function")),
        }
    }
    pub fn number(&self, index: usize) -> Option<f32> {
        match self.values.get(index) {
            Some(Value::Number(number)) => Some(*number as f32),
            Some(Value::Integer(number)) => Some(*number as f32),
            Some(Value::String(text)) => text.to_str().ok()?.parse::<f32>().ok(),
            _ => None,
        }
    }
    pub fn text(&self, index: usize) -> Option<String> {
        match self.values.get(index) {
            Some(Value::String(text)) => text.to_str().ok().map(|text| text.to_string()),
            Some(Value::Number(number)) => Some(number.to_string()),
            Some(Value::Integer(number)) => Some(number.to_string()),
            _ => None,
        }
    }
    pub fn truthy(&self, index: usize) -> bool {
        !matches!(self.values.get(index), None | Some(Value::Nil) | Some(Value::Boolean(false)))
    }
    pub fn function(&self, index: usize) -> Option<Function> {
        match self.values.get(index) {
            Some(Value::Function(function)) => Some(function.clone()),
            _ => None,
        }
    }
    pub fn table(&self, index: usize) -> Option<Table> {
        match self.values.get(index) {
            Some(Value::Table(table)) => Some(table.clone()),
            _ => None,
        }
    }
    pub fn object(&self, index: usize) -> Option<Id> {
        match self.values.get(index) {
            Some(Value::Table(table)) => id_of(table),
            _ => None,
        }
    }
    pub fn colour(&self, index: usize) -> [f32; 4] {
        [self.number(index).unwrap_or(1.0), self.number(index + 1).unwrap_or(1.0), self.number(index + 2).unwrap_or(1.0), self.number(index + 3).unwrap_or(1.0)]
    }
}

pub fn id_of(table: &Table) -> Option<Id> {
    match table.raw_get::<Value>(0) {
        Ok(Value::Integer(id)) => Some(id as usize),
        Ok(Value::Number(id)) => Some(id as usize),
        _ => None,
    }
}

fn nothing() -> Result<MultiValue> {
    Ok(MultiValue::new())
}

fn give<T: IntoLuaMulti>(lua: &Lua, values: T) -> Result<MultiValue> {
    values.into_lua_multi(lua)
}

/// Where a scenario or script finds an object's table again.
pub fn table_of(shared: &Shared, id: Id) -> Table {
    shared.world.borrow().objs[id].table.clone()
}

fn gap(what: &str) -> mlua::Error {
    mlua::Error::runtime(format!("{GAP}: {what}"))
}

/// The class of frame that `CreateFrame` knows, or a gap.
pub fn frame_class(kind: &str) -> Option<Class> {
    Some(match kind {
        "Frame" | "EditBox" | "MessageFrame" | "Slider" | "SimpleHTML" | "ModelScene" | "ColorSelect" => Class::Frame,
        "Button" | "CheckButton" => Class::Button,
        "ScrollFrame" => Class::ScrollFrame,
        "StatusBar" => Class::StatusBar,
        "Cooldown" => Class::Cooldown,
        "GameTooltip" => Class::Tooltip,
        _ => return None,
    })
}

/// Makes the table a script sees for an object, and files it in the world.
pub fn make_object(lua: &Lua, shared: &Shared, class: Class, name: Option<String>, parent: Option<Id>) -> Result<Id> {
    let table = lua.create_table()?;
    let id = shared.world.borrow_mut().add(class, table.clone(), name.clone(), parent);
    table.raw_set(0, id)?;
    let metatables = shared.metatables.borrow();
    if let Some(metatable) = metatables.get(&class) {
        table.set_metatable(Some(metatable.clone()))?;
    }
    drop(metatables);
    if let Some(name) = name {
        lua.globals().set(name.as_str(), table)?;
    }
    Ok(id)
}

/// Runs an object's script and then what hooks it, never while the world is borrowed. A script that
/// fails does not stop the game: its error is kept for the scenario to read.
pub fn fire(lua: &Lua, shared: &Shared, id: Id, script: &str, extra: MultiValue) -> Result<()> {
    let (own, hooks, table) = {
        let world = shared.world.borrow();
        let obj = &world.objs[id];
        (obj.scripts.get(script).cloned(), obj.hooks.get(script).cloned().unwrap_or_default(), obj.table.clone())
    };
    let mut all: Vec<Function> = Vec::new();
    all.extend(own);
    all.extend(hooks);
    for function in all {
        let mut values = vec![Value::Table(table.clone())];
        values.extend(extra.iter().cloned());
        if let Err(error) = function.call::<MultiValue>(MultiValue::from_iter(values)) {
            let name = shared.world.borrow().objs[id].name.clone().unwrap_or_else(|| format!("#{id}"));
            shared.world.borrow_mut().errors.push(format!("{name}:{script}: {error}"));
            let _ = lua;
        }
    }
    Ok(())
}

fn set_shown(lua: &Lua, shared: &Shared, id: Id, shown: bool) -> Result<()> {
    let before = shared.world.borrow().visible(id);
    shared.world.borrow_mut().objs[id].shown = shown;
    let after = shared.world.borrow().visible(id);
    if before == after {
        return Ok(());
    }
    // Showing or hiding a frame shows or hides what is under it that was shown on its own account.
    let mut changed: Vec<Id> = vec![id];
    let mut index = 0;
    while index < changed.len() {
        let parent = changed[index];
        let children: Vec<Id> = shared.world.borrow().objs[parent].children.clone();
        for child in children {
            if shared.world.borrow().objs[child].shown {
                changed.push(child);
            }
        }
        index += 1;
    }
    for target in changed {
        if shared.world.borrow().objs[target].class.is_frame() {
            fire(lua, shared, target, if after { "OnShow" } else { "OnHide" }, MultiValue::new())?;
        }
    }
    Ok(())
}

fn rect_in_game_space(world: &crate::world::World, id: Id) -> Rect {
    let rect = world.rect(id);
    let scale = world.effective_scale(id);
    Rect { left: rect.left / scale, top: rect.top / scale, width: rect.width / scale, height: rect.height / scale }
}

fn font_name(args: &Args, index: usize) -> Option<String> {
    match args.values.get(index) {
        Some(Value::String(text)) => text.to_str().ok().map(|text| text.to_string()),
        Some(Value::Table(table)) => table.get::<Option<String>>("__name").ok().flatten(),
        _ => None,
    }
}

/// Every method the harness implements, by name. A method means the same on every type that has it,
/// except where the body looks at the class.
pub fn implementations(lua: &Lua, shared: &Shared) -> Result<HashMap<&'static str, Function>> {
    let mut map: HashMap<&'static str, Function> = HashMap::new();
    macro_rules! def {
        ($name:literal, |$lua:ident, $shared:ident, $args:ident| $body:expr) => {{
            let shared = shared.clone();
            let implementation: Impl = Box::new(move |$lua: &Lua, $shared: &Shared, $args: &Args| -> Result<MultiValue> { $body });
            let function = lua.create_function(move |lua, values: MultiValue| {
                let args = Args { values: values.into_iter().collect() };
                implementation(lua, &shared, &args)
            })?;
            map.insert($name, function);
        }};
    }

    // ---- every object
    def!("GetObjectType", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].class.type_name())
    });
    def!("IsObjectType", |lua, shared, a| {
        let id = a.me()?;
        let class = shared.world.borrow().objs[id].class;
        let asked = a.text(1).unwrap_or_default();
        let kinds: &[&str] = match class {
            Class::Frame => &["Frame"],
            Class::Button => &["Button", "Frame"],
            Class::ScrollFrame => &["ScrollFrame", "Frame"],
            Class::StatusBar => &["StatusBar", "Frame"],
            Class::Cooldown => &["Cooldown", "Frame"],
            Class::Texture => &["Texture", "Region"],
            Class::FontString => &["FontString", "Region"],
            _ => &[],
        };
        give(lua, kinds.contains(&asked.as_str()) || asked == class.type_name())
    });
    def!("GetName", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].name.clone())
    });
    def!("GetDebugName", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        let mut parts: Vec<String> = Vec::new();
        let mut walker = Some(id);
        while let Some(current) = walker {
            let obj = &world.objs[current];
            parts.push(obj.name.clone().unwrap_or_else(|| format!("{}", obj.class.type_name())));
            walker = obj.parent;
        }
        parts.reverse();
        give(lua, parts.join("."))
    });
    def!("IsForbidden", |lua, _shared, _a| give(lua, false));
    def!("HasAnySecretAspect", |lua, _shared, _a| give(lua, false));
    def!("HasSecretAspect", |lua, _shared, _a| give(lua, false));
    def!("HasSecretValues", |lua, _shared, _a| give(lua, false));
    def!("IsPreventingSecretValues", |lua, _shared, _a| give(lua, false));
    def!("IsProtected", |lua, _shared, _a| give(lua, (false, false)));
    def!("GetParent", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        match world.objs[id].parent {
            Some(parent) => give(lua, world.objs[parent].table.clone()),
            None => give(lua, Value::Nil),
        }
    });
    def!("SetParent", |lua, shared, a| {
        let id = a.me()?;
        let parent = a.object(1);
        shared.world.borrow_mut().set_parent(id, parent);
        let _ = lua;
        nothing()
    });

    // ---- regions: alpha, scale, colour
    def!("SetAlpha", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].alpha = a.number(1).unwrap_or(1.0).clamp(0.0, 1.0);
        nothing()
    });
    def!("GetAlpha", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].alpha)
    });
    def!("GetEffectiveAlpha", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().effective_alpha(id))
    });
    def!("SetScale", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].scale = a.number(1).unwrap_or(1.0).max(0.0001);
        nothing()
    });
    def!("GetScale", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].scale)
    });
    def!("GetEffectiveScale", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().effective_scale(id))
    });
    def!("SetVertexColor", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].texture.vertex_color = Some(a.colour(1));
        nothing()
    });
    def!("GetVertexColor", |lua, shared, a| {
        let id = a.me()?;
        let color = shared.world.borrow().objs[id].texture.vertex_color.unwrap_or([1.0; 4]);
        give(lua, (color[0], color[1], color[2], color[3]))
    });
    def!("SetDrawLayer", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].texture.layer = a.text(1).unwrap_or_default();
        nothing()
    });
    def!("GetDrawLayer", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].texture.layer.clone())
    });

    // ---- anchors and size
    def!("ClearAllPoints", |_lua, shared, a| {
        let id = a.me()?;
        let mut world = shared.world.borrow_mut();
        world.objs[id].points.clear();
        world.objs[id].all_points = None;
        nothing()
    });
    def!("SetPoint", |_lua, shared, a| {
        let id = a.me()?;
        let point = a.text(1).and_then(|text| Point::parse(&text.to_uppercase()));
        let point = point.ok_or_else(|| mlua::Error::runtime(format!("{}:SetPoint(): Unknown region point", shared.world.borrow().objs[id].class.type_name())))?;
        // relativeTo: a frame or region, a name, or nothing. A table that is neither is the mistake the game names.
        let mut index = 2;
        let mut relative: Option<Id> = None;
        match a.values.get(index) {
            Some(Value::Table(table)) => {
                relative = Some(id_of(table).ok_or_else(|| mlua::Error::runtime("SetPoint(): Wrong object type for function"))?);
                index += 1;
            }
            Some(Value::String(name)) => {
                let name = name.to_str()?.to_string();
                let found = shared.world.borrow().globals_named.get(&name).copied();
                match found {
                    Some(found) => relative = Some(found),
                    None => {
                        // A numeric string is an offset; anything else names a region that is not there.
                        if name.parse::<f32>().is_err() {
                            return Err(mlua::Error::runtime(format!("SetPoint(): Couldn't find region named '{name}'")));
                        }
                    }
                }
                if name.parse::<f32>().is_err() {
                    index += 1;
                }
            }
            Some(Value::Nil) => index += 1,
            _ => {}
        }
        let mut relative_point = point;
        if let Some(Value::String(text)) = a.values.get(index) {
            if let Some(parsed) = Point::parse(&text.to_str()?.to_uppercase()) {
                relative_point = parsed;
                index += 1;
            }
        } else if let Some(Value::Nil) = a.values.get(index) {
            index += 1;
        }
        let x = a.number(index).unwrap_or(0.0);
        let y = a.number(index + 1).unwrap_or(0.0);
        let mut world = shared.world.borrow_mut();
        let anchor = Anchor { point, relative, relative_point, x, y };
        let obj = &mut world.objs[id];
        obj.all_points = None;
        match obj.points.iter().position(|existing| existing.point == point) {
            Some(position) => obj.points[position] = anchor,
            None => obj.points.push(anchor),
        }
        nothing()
    });
    def!("GetNumPoints", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].points.len() as i64)
    });
    def!("GetPoint", |lua, shared, a| {
        let id = a.me()?;
        let index = a.number(1).unwrap_or(1.0) as usize;
        let world = shared.world.borrow();
        let obj = &world.objs[id];
        match obj.points.get(index.saturating_sub(1)) {
            Some(anchor) => {
                let relative = anchor.relative.or(obj.parent).map(|relative| world.objs[relative].table.clone());
                give(lua, (anchor.point.name(), relative, anchor.relative_point.name(), anchor.x, anchor.y))
            }
            None => nothing(),
        }
    });
    def!("SetAllPoints", |_lua, shared, a| {
        let id = a.me()?;
        let target = match a.values.get(1) {
            Some(Value::Table(table)) => Some(id_of(table).ok_or_else(|| mlua::Error::runtime("SetAllPoints(): Wrong object type for function"))?),
            _ => None,
        };
        let mut world = shared.world.borrow_mut();
        world.objs[id].points.clear();
        world.objs[id].all_points = Some(target);
        nothing()
    });
    def!("SetSize", |_lua, shared, a| {
        let id = a.me()?;
        let mut world = shared.world.borrow_mut();
        world.objs[id].width = a.number(1);
        world.objs[id].height = a.number(2);
        nothing()
    });
    def!("SetWidth", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].width = a.number(1);
        nothing()
    });
    def!("SetHeight", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].height = a.number(1);
        nothing()
    });
    def!("GetWidth", |lua, shared, a| {
        let id = a.me()?;
        give(lua, rect_in_game_space(&shared.world.borrow(), id).width)
    });
    def!("GetHeight", |lua, shared, a| {
        let id = a.me()?;
        give(lua, rect_in_game_space(&shared.world.borrow(), id).height)
    });
    def!("GetSize", |lua, shared, a| {
        let id = a.me()?;
        let rect = rect_in_game_space(&shared.world.borrow(), id);
        give(lua, (rect.width, rect.height))
    });
    // Positions come back the game's way: from the bottom left, y growing upward.
    def!("GetLeft", |lua, shared, a| {
        let id = a.me()?;
        give(lua, rect_in_game_space(&shared.world.borrow(), id).left)
    });
    def!("GetRight", |lua, shared, a| {
        let id = a.me()?;
        give(lua, rect_in_game_space(&shared.world.borrow(), id).right())
    });
    def!("GetTop", |lua, shared, a| {
        let id = a.me()?;
        let scale = shared.world.borrow().effective_scale(id);
        give(lua, SCREEN_HEIGHT / scale - rect_in_game_space(&shared.world.borrow(), id).top)
    });
    def!("GetBottom", |lua, shared, a| {
        let id = a.me()?;
        let scale = shared.world.borrow().effective_scale(id);
        give(lua, SCREEN_HEIGHT / scale - rect_in_game_space(&shared.world.borrow(), id).bottom())
    });
    def!("GetCenter", |lua, shared, a| {
        let id = a.me()?;
        let scale = shared.world.borrow().effective_scale(id);
        let rect = rect_in_game_space(&shared.world.borrow(), id);
        give(lua, (rect.left + rect.width / 2.0, SCREEN_HEIGHT / scale - (rect.top + rect.height / 2.0)))
    });
    def!("GetRect", |lua, shared, a| {
        let id = a.me()?;
        let scale = shared.world.borrow().effective_scale(id);
        let rect = rect_in_game_space(&shared.world.borrow(), id);
        give(lua, (rect.left, SCREEN_HEIGHT / scale - rect.bottom(), rect.width, rect.height))
    });

    // ---- shown, mouse, scripts
    def!("Show", |lua, shared, a| {
        let id = a.me()?;
        set_shown(lua, shared, id, true)?;
        nothing()
    });
    def!("Hide", |lua, shared, a| {
        let id = a.me()?;
        set_shown(lua, shared, id, false)?;
        nothing()
    });
    def!("SetShown", |lua, shared, a| {
        let id = a.me()?;
        set_shown(lua, shared, id, a.truthy(1))?;
        nothing()
    });
    def!("IsShown", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].shown)
    });
    def!("IsVisible", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().visible(id))
    });
    def!("EnableMouse", |_lua, shared, a| {
        let id = a.me()?;
        let enable = a.truthy(1);
        let mut world = shared.world.borrow_mut();
        world.objs[id].mouse_click = enable;
        world.objs[id].mouse_motion = enable;
        nothing()
    });
    def!("EnableMouseMotion", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].mouse_motion = a.truthy(1);
        nothing()
    });
    def!("SetMouseClickEnabled", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].mouse_click = a.truthy(1);
        nothing()
    });
    def!("SetMouseMotionEnabled", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].mouse_motion = a.truthy(1);
        nothing()
    });
    def!("EnableMouseWheel", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].mouse_wheel = a.truthy(1);
        nothing()
    });
    def!("IsMouseEnabled", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        give(lua, world.objs[id].mouse_click || world.objs[id].mouse_motion)
    });
    def!("IsMouseClickEnabled", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].mouse_click)
    });
    def!("IsMouseMotionEnabled", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].mouse_motion)
    });
    def!("IsMouseWheelEnabled", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].mouse_wheel)
    });
    def!("IsMouseOver", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        give(lua, world.visible(id) && world.holds(id, world.pointer.0, world.pointer.1))
    });
    def!("SetPassThroughButtons", |_lua, _shared, _a| nothing());
    def!("SetHitRectInsets", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].insets = [a.number(1).unwrap_or(0.0), a.number(2).unwrap_or(0.0), a.number(3).unwrap_or(0.0), a.number(4).unwrap_or(0.0)];
        nothing()
    });
    def!("GetHitRectInsets", |lua, shared, a| {
        let id = a.me()?;
        let i = shared.world.borrow().objs[id].insets;
        give(lua, (i[0], i[1], i[2], i[3]))
    });
    def!("SetClipsChildren", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].clips = a.truthy(1);
        nothing()
    });
    def!("GetEffectivelyFlattensRenderLayers", |lua, shared, a| {
        let id = a.me()?;
        // Clipping turns flattening on, as the wiki says; so a frame under a clipping one is flattened too.
        let world = shared.world.borrow();
        let mut walker = Some(id);
        let mut flat = false;
        while let Some(current) = walker {
            flat = flat || world.objs[current].clips;
            walker = world.objs[current].parent;
        }
        give(lua, flat)
    });
    def!("DoesClipChildren", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].clips)
    });
    def!("SetScript", |_lua, shared, a| {
        let id = a.me()?;
        let name = a.text(1).unwrap_or_default();
        let mut world = shared.world.borrow_mut();
        match a.function(2) {
            Some(function) => {
                world.objs[id].scripts.insert(name, function);
            }
            None => {
                world.objs[id].scripts.remove(&name);
            }
        }
        nothing()
    });
    def!("GetScript", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].scripts.get(&a.text(1).unwrap_or_default()).cloned())
    });
    def!("HasScript", |lua, shared, a| {
        let id = a.me()?;
        let _ = id;
        let _ = shared;
        give(lua, true)
    });
    def!("HookScript", |_lua, shared, a| {
        let id = a.me()?;
        if let Some(function) = a.function(2) {
            shared.world.borrow_mut().objs[id].hooks.entry(a.text(1).unwrap_or_default()).or_default().push(function);
        }
        nothing()
    });
    def!("RegisterEvent", |lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].events.insert(a.text(1).unwrap_or_default());
        give(lua, true)
    });
    // The client then sends the event only for the units named. The harness fires events by hand, so it keeps
    // the registration and leaves the unit filter to the scenario (engine fact 22).
    def!("RegisterUnitEvent", |lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].events.insert(a.text(1).unwrap_or_default());
        give(lua, true)
    });
    def!("UnregisterEvent", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].events.remove(&a.text(1).unwrap_or_default());
        nothing()
    });
    def!("UnregisterAllEvents", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].events.clear();
        nothing()
    });
    def!("IsEventRegistered", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].events.contains(&a.text(1).unwrap_or_default()))
    });

    // ---- frames
    def!("SetFrameLevel", |_lua, shared, a| {
        let id = a.me()?;
        // A frame's level moves everything under it by the same amount. Engine fact 2: the client raised the
        // island's panel one level and its buttons rose one level with it.
        let mut world = shared.world.borrow_mut();
        let level = a.number(1).unwrap_or(0.0) as i32;
        let delta = level - world.objs[id].level;
        world.objs[id].level = level;
        if delta != 0 {
            let mut stack = world.objs[id].children.clone();
            while let Some(child) = stack.pop() {
                world.objs[child].level += delta;
                stack.extend(world.objs[child].children.clone());
            }
        }
        nothing()
    });
    def!("GetFrameLevel", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].level as i64)
    });
    def!("SetFrameStrata", |_lua, shared, a| {
        let id = a.me()?;
        let strata = Strata::parse(&a.text(1).unwrap_or_default().to_uppercase()).ok_or_else(|| mlua::Error::runtime("SetFrameStrata(): Unknown strata"))?;
        // Likewise for the strata. Engine fact 3.
        shared.world.borrow_mut().objs[id].strata = strata;
        nothing()
    });
    def!("GetFrameStrata", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].strata.name())
    });
    def!("SetID", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].id_number = a.number(1).unwrap_or(0.0) as i64;
        nothing()
    });
    def!("GetID", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].id_number)
    });
    def!("SetAttribute", |_lua, shared, a| {
        let id = a.me()?;
        let value = a.values.get(2).cloned().unwrap_or(Value::Nil);
        shared.world.borrow_mut().objs[id].attributes.insert(a.text(1).unwrap_or_default(), value);
        nothing()
    });
    def!("GetAttribute", |lua, shared, a| {
        let id = a.me()?;
        let value = shared.world.borrow().objs[id].attributes.get(&a.text(1).unwrap_or_default()).cloned().unwrap_or(Value::Nil);
        give(lua, value)
    });
    for name in ["SetClampedToScreen", "SetMovable", "RegisterForDrag", "SetToplevel", "SetResizable", "SetUserPlaced", "SetDontSavePosition", "EnableKeyboard", "SetPropagateKeyboardInput", "Raise", "Lower", "StartMoving", "StopMovingOrSizing", "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetIgnoreParentAlpha", "SetIgnoreParentScale", "SetFlattensRenderLayers", "SetBlendMode", "SetDesaturated", "SetHorizTile", "SetVertTile", "SetDrawEdge", "SetDrawBling", "SetDrawSwipe", "SetHideCountdownNumbers", "SetReverse", "SetSwipeTexture", "SetSwipeColor", "SetEdgeTexture", "SetBlingTexture", "SetNonSpaceWrap", "SetShadowColor", "SetShadowOffset", "SetStatusBarDesaturated", "SetReverseFill", "SetOrientation", "SetFillStyle", "SetRotatesTexture", "SetPushedTextOffset", "SetMotionScriptsWhileDisabled", "SetIndentedWordWrap"] {
        // Settings that only change what is drawn, or that nothing in a scenario reads back.
        let function = lua.create_function(|_, _: MultiValue| Ok(()))?;
        let name: &'static str = Box::leak(name.to_string().into_boxed_str());
        map.insert(name, function);
    }
    def!("GetChildren", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        let tables: Vec<Value> = world.objs[id].children.iter().map(|child| Value::Table(world.objs[*child].table.clone())).collect();
        give(lua, MultiValue::from_iter(tables))
    });
    def!("GetNumChildren", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].children.len() as i64)
    });
    def!("GetRegions", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        let tables: Vec<Value> = world.objs[id].regions.iter().map(|child| Value::Table(world.objs[*child].table.clone())).collect();
        give(lua, MultiValue::from_iter(tables))
    });
    def!("GetNumRegions", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].regions.len() as i64)
    });
    def!("CreateTexture", |lua, shared, a| {
        let id = a.me()?;
        let name = a.text(1);
        let region = make_object(lua, shared, Class::Texture, name, Some(id))?;
        shared.world.borrow_mut().objs[region].texture.layer = a.text(2).unwrap_or_else(|| "ARTWORK".into());
        give(lua, table_of(shared, region))
    });
    def!("CreateFontString", |lua, shared, a| {
        let id = a.me()?;
        let name = a.text(1);
        let region = make_object(lua, shared, Class::FontString, name, Some(id))?;
        {
            let mut world = shared.world.borrow_mut();
            world.objs[region].texture.layer = a.text(2).unwrap_or_else(|| "OVERLAY".into());
            world.objs[region].text.font_object = a.text(3);
        }
        give(lua, table_of(shared, region))
    });

    // ---- buttons
    def!("SetText", |lua, shared, a| {
        let id = a.me()?;
        let text = a.text(1).unwrap_or_default();
        if shared.world.borrow().objs[id].class == Class::Tooltip {
            // A tooltip's text is its first line, in the colour given, and replaces what was there.
            let color = a.number(2).map(|_| a.colour(2));
            shared.world.borrow_mut().objs[id].tip = vec![TipLine { left: text, right: None, left_color: color, right_color: None, wrap: a.truthy(6) }];
            tooltip_layout(lua, shared, id)?;
        } else {
            shared.world.borrow_mut().objs[id].text.text = text;
        }
        nothing()
    });
    def!("SetOwner", |lua, shared, a| {
        let id = a.me()?;
        {
            let mut world = shared.world.borrow_mut();
            world.objs[id].tip.clear();
            world.objs[id].tip_owner = a.object(1);
            world.objs[id].tip_anchor = a.text(2).unwrap_or_else(|| "ANCHOR_NONE".into());
        }
        tooltip_layout(lua, shared, id)?;
        nothing()
    });
    def!("GetOwner", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        give(lua, world.objs[id].tip_owner.map(|owner| world.objs[owner].table.clone()))
    });
    def!("IsOwned", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].tip_owner.is_some())
    });
    def!("AddLine", |lua, shared, a| {
        let id = a.me()?;
        let color = a.number(2).map(|_| a.colour(2));
        shared.world.borrow_mut().objs[id].tip.push(TipLine { left: a.text(1).unwrap_or_default(), right: None, left_color: color, right_color: None, wrap: a.truthy(5) });
        tooltip_layout(lua, shared, id)?;
        nothing()
    });
    def!("AddDoubleLine", |lua, shared, a| {
        let id = a.me()?;
        let left = a.number(3).map(|_| a.colour(3));
        let right = a.number(6).map(|_| a.colour(6));
        shared.world.borrow_mut().objs[id].tip.push(TipLine { left: a.text(1).unwrap_or_default(), right: a.text(2), left_color: left, right_color: right, wrap: false });
        tooltip_layout(lua, shared, id)?;
        nothing()
    });
    def!("ClearLines", |lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].tip.clear();
        tooltip_layout(lua, shared, id)?;
        nothing()
    });
    def!("NumLines", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].tip.len() as i64)
    });
    def!("FadeOut", |lua, shared, a| {
        let id = a.me()?;
        set_shown(lua, shared, id, false)?;
        nothing()
    });
    def!("GetUnit", |_lua, _shared, _a| nothing());
    def!("GetItem", |_lua, _shared, _a| nothing());
    def!("GetSpell", |_lua, _shared, _a| nothing());
    def!("SetPadding", |_lua, _shared, _a| nothing());
    def!("SetMinimumWidth", |_lua, _shared, _a| nothing());
    def!("SetFormattedText", |_lua, shared, a| {
        let id = a.me()?;
        let text = a.text(1).unwrap_or_default();
        shared.world.borrow_mut().objs[id].text.text = text;
        nothing()
    });
    def!("GetText", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].text.text.clone())
    });
    def!("SetEnabled", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].enabled = a.truthy(1);
        nothing()
    });
    def!("Enable", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].enabled = true;
        nothing()
    });
    def!("Disable", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].enabled = false;
        nothing()
    });
    def!("IsEnabled", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].enabled)
    });
    def!("RegisterForClicks", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].clicks = a.values.iter().skip(1).filter_map(|value| if let Value::String(text) = value { text.to_str().ok().map(|text| text.to_string()) } else { None }).collect();
        nothing()
    });
    def!("Click", |lua, shared, a| {
        let id = a.me()?;
        let button = a.text(1).unwrap_or_else(|| "LeftButton".into());
        crate::input::click_button(lua, shared, id, &button, a.truthy(2))?;
        nothing()
    });
    def!("LockHighlight", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].highlight_locked = true;
        nothing()
    });
    def!("UnlockHighlight", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].highlight_locked = false;
        nothing()
    });
    def!("SetHighlightTexture", |lua, shared, a| {
        let id = a.me()?;
        let region = make_object(lua, shared, Class::Texture, None, Some(id))?;
        shared.world.borrow_mut().objs[region].texture.path = a.text(1);
        nothing()
    });

    // ---- scroll frames
    def!("SetScrollChild", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].scroll_child = a.object(1);
        nothing()
    });
    def!("GetScrollChild", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        give(lua, world.objs[id].scroll_child.map(|child| world.objs[child].table.clone()))
    });
    def!("SetVerticalScroll", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].scroll.1 = a.number(1).unwrap_or(0.0);
        nothing()
    });
    def!("GetVerticalScroll", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].scroll.1)
    });
    def!("SetHorizontalScroll", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].scroll.0 = a.number(1).unwrap_or(0.0);
        nothing()
    });
    def!("GetHorizontalScroll", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].scroll.0)
    });
    def!("GetVerticalScrollRange", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        let child = world.objs[id].scroll_child.map(|child| world.rect(child).height).unwrap_or(0.0);
        give(lua, (child - world.rect(id).height).max(0.0))
    });

    // ---- status bars and cooldowns
    def!("SetMinMaxValues", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].min_max = (a.number(1).unwrap_or(0.0), a.number(2).unwrap_or(1.0));
        nothing()
    });
    def!("GetMinMaxValues", |lua, shared, a| {
        let id = a.me()?;
        let range = shared.world.borrow().objs[id].min_max;
        give(lua, range)
    });
    def!("SetValue", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].value = a.number(1);
        nothing()
    });
    def!("GetValue", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].value)
    });
    def!("SetStatusBarColor", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].bar_color = Some(a.colour(1));
        nothing()
    });
    def!("SetStatusBarTexture", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].bar_texture = a.text(1);
        nothing()
    });
    def!("SetCooldown", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].cooldown = Some((a.number(1).unwrap_or(0.0) as f64, a.number(2).unwrap_or(0.0) as f64));
        nothing()
    });
    def!("Pause", |_lua, _shared, _a| nothing());

    // ---- textures
    def!("SetTexture", |_lua, shared, a| {
        let id = a.me()?;
        let mut world = shared.world.borrow_mut();
        world.objs[id].texture.path = a.text(1);
        world.objs[id].texture.atlas = None;
        nothing()
    });
    def!("GetTexture", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].texture.path.clone())
    });
    def!("SetColorTexture", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].texture.color = Some(a.colour(1));
        nothing()
    });
    def!("SetAtlas", |_lua, shared, a| {
        let id = a.me()?;
        let mut world = shared.world.borrow_mut();
        world.objs[id].texture.atlas = a.text(1);
        world.objs[id].texture.path = None;
        nothing()
    });
    def!("GetAtlas", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].texture.atlas.clone())
    });
    def!("SetTexCoord", |_lua, shared, a| {
        let id = a.me()?;
        let values: Vec<f32> = (1..a.values.len()).filter_map(|index| a.number(index)).collect();
        shared.world.borrow_mut().objs[id].texture.tex_coord = Some(values);
        nothing()
    });
    def!("SetRotation", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].texture.rotation = a.number(1).unwrap_or(0.0);
        nothing()
    });
    def!("GetRotation", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].texture.rotation)
    });
    def!("SetGradient", |_lua, shared, a| {
        let id = a.me()?;
        let color = |index: usize| -> [f32; 4] {
            match a.values.get(index) {
                Some(Value::Table(table)) => [table.get("r").unwrap_or(1.0), table.get("g").unwrap_or(1.0), table.get("b").unwrap_or(1.0), table.get("a").unwrap_or(1.0)],
                _ => [1.0; 4],
            }
        };
        shared.world.borrow_mut().objs[id].texture.gradient = Some((a.text(1).unwrap_or_default(), color(2), color(3)));
        nothing()
    });
    def!("AddMaskTexture", |_lua, shared, a| {
        let id = a.me()?;
        if let Some(mask) = a.object(1) {
            shared.world.borrow_mut().objs[id].texture.masks.push(mask);
        }
        nothing()
    });
    def!("CreateMaskTexture", |lua, shared, a| {
        let id = a.me()?;
        let region = make_object(lua, shared, Class::Texture, a.text(1), Some(id))?;
        {
            let mut world = shared.world.borrow_mut();
            world.objs[region].texture.layer = a.text(2).unwrap_or_else(|| "ARTWORK".into());
            world.objs[region].texture.is_mask = true;
        }
        give(lua, table_of(shared, region))
    });

    // ---- text
    def!("SetFont", |_lua, shared, a| {
        let id = a.me()?;
        let mut world = shared.world.borrow_mut();
        let obj = &mut world.objs[id];
        obj.text.font = a.text(1);
        obj.text.font_height = a.number(2);
        obj.text.font_flags = a.text(3).unwrap_or_default();
        nothing()
    });
    def!("GetFont", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        let (path, height) = world.font_of(id);
        give(lua, (path, height, world.objs[id].text.font_flags.clone()))
    });
    def!("SetFontObject", |_lua, shared, a| {
        let id = a.me()?;
        // The string follows the font object from now on, and its own file and height are let go.
        let mut world = shared.world.borrow_mut();
        let obj = &mut world.objs[id];
        obj.text.font_object = font_name(a, 1);
        obj.text.font = None;
        obj.text.font_height = None;
        nothing()
    });
    def!("GetFontObject", |lua, shared, a| {
        let id = a.me()?;
        let name = shared.world.borrow().objs[id].text.font_object.clone();
        let value = match name {
            Some(name) => lua.globals().get::<Value>(name.as_str())?,
            None => Value::Nil,
        };
        give(lua, value)
    });
    def!("SetJustifyH", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].text.justify_h = a.text(1).unwrap_or_default();
        nothing()
    });
    def!("GetJustifyH", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].text.justify_h.clone())
    });
    def!("SetJustifyV", |_lua, _shared, _a| nothing());
    def!("SetTextColor", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].text.color = Some(a.colour(1));
        nothing()
    });
    def!("GetTextColor", |lua, shared, a| {
        let id = a.me()?;
        let color = shared.world.borrow().objs[id].text.color.unwrap_or([1.0; 4]);
        give(lua, (color[0], color[1], color[2], color[3]))
    });
    def!("SetWordWrap", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].text.wrap = a.truthy(1);
        nothing()
    });
    def!("SetMaxLines", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].text.max_lines = a.number(1).unwrap_or(0.0) as u32;
        nothing()
    });
    def!("GetMaxLines", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].text.max_lines as f64)
    });
    def!("CanWordWrap", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].text.wrap)
    });
    def!("SetSpacing", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].text.spacing = a.number(1).unwrap_or(0.0);
        nothing()
    });
    def!("GetStringWidth", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().string_width(id))
    });
    def!("GetUnboundedStringWidth", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().string_width(id))
    });
    def!("GetStringHeight", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        let width = world.objs[id].width.filter(|width| *width > 0.0);
        give(lua, world.string_height(id, width))
    });
    def!("GetLineHeight", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().font_of(id).1)
    });

    // ---- animations
    def!("CreateAnimationGroup", |lua, shared, a| {
        let id = a.me()?;
        let group = make_object(lua, shared, Class::AnimGroup, None, None)?;
        {
            let mut world = shared.world.borrow_mut();
            world.objs[group].anim.owner = Some(id);
            world.objs[id].groups.push(group);
        }
        give(lua, table_of(shared, group))
    });
    def!("CreateAnimation", |lua, shared, a| {
        let group = a.me()?;
        let kind = match a.text(1).unwrap_or_default().as_str() {
            "Alpha" => AnimKind::Alpha,
            "Translation" => AnimKind::Translation,
            "Scale" => AnimKind::Scale,
            "Rotation" => AnimKind::Rotation,
            other => return Err(gap(&format!("CreateAnimation(\"{other}\") is not implemented"))),
        };
        let anim = make_object(lua, shared, Class::Anim(kind), None, None)?;
        {
            let mut world = shared.world.borrow_mut();
            world.objs[anim].anim.owner = Some(group);
            world.objs[anim].anim.smoothing = "NONE".into();
            world.objs[anim].anim.to_alpha = 1.0;
            world.objs[anim].anim.scale_from = (1.0, 1.0);
            world.objs[anim].anim.scale_to = (1.0, 1.0);
            world.objs[group].anim.members.push(anim);
        }
        give(lua, table_of(shared, anim))
    });
    def!("SetDuration", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.duration = a.number(1).unwrap_or(0.0) as f64;
        nothing()
    });
    def!("GetDuration", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].anim.duration)
    });
    def!("SetSmoothing", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.smoothing = a.text(1).unwrap_or_else(|| "NONE".into());
        nothing()
    });
    def!("GetSmoothing", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].anim.smoothing.clone())
    });
    def!("SetOrder", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.order = a.number(1).unwrap_or(1.0) as i32;
        nothing()
    });
    def!("SetStartDelay", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.start_delay = a.number(1).unwrap_or(0.0) as f64;
        nothing()
    });
    def!("SetEndDelay", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.end_delay = a.number(1).unwrap_or(0.0) as f64;
        nothing()
    });
    def!("SetFromAlpha", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.from_alpha = a.number(1).unwrap_or(0.0);
        nothing()
    });
    def!("SetToAlpha", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.to_alpha = a.number(1).unwrap_or(1.0);
        nothing()
    });
    def!("SetOffset", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.offset = (a.number(1).unwrap_or(0.0), a.number(2).unwrap_or(0.0));
        nothing()
    });
    def!("SetTarget", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.target = a.object(1);
        nothing()
    });
    def!("GetSmoothProgress", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].anim.progress)
    });
    def!("GetProgress", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].anim.progress)
    });
    def!("Play", |lua, shared, a| {
        let id = a.me()?;
        crate::anim::play(lua, shared, id)?;
        nothing()
    });
    def!("Stop", |lua, shared, a| {
        let id = a.me()?;
        crate::anim::stop(lua, shared, id)?;
        nothing()
    });
    def!("Finish", |lua, shared, a| {
        let id = a.me()?;
        crate::anim::stop(lua, shared, id)?;
        nothing()
    });
    def!("IsPlaying", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].anim.playing)
    });
    def!("IsDone", |lua, shared, a| {
        let id = a.me()?;
        give(lua, !shared.world.borrow().objs[id].anim.playing)
    });
    def!("SetToFinalAlpha", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.to_final_alpha = a.truthy(1);
        nothing()
    });
    def!("IsSetToFinalAlpha", |lua, shared, a| {
        let id = a.me()?;
        give(lua, shared.world.borrow().objs[id].anim.to_final_alpha)
    });
    def!("SetLooping", |_lua, shared, a| {
        let id = a.me()?;
        shared.world.borrow_mut().objs[id].anim.looping = a.text(1).unwrap_or_else(|| "NONE".into());
        nothing()
    });
    def!("GetAnimationGroups", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        let tables: Vec<Value> = world.objs[id].groups.iter().map(|group| Value::Table(world.objs[*group].table.clone())).collect();
        give(lua, MultiValue::from_iter(tables))
    });
    def!("StopAnimating", |lua, shared, a| {
        let id = a.me()?;
        let groups = shared.world.borrow().objs[id].groups.clone();
        for group in groups {
            crate::anim::stop(lua, shared, group)?;
        }
        nothing()
    });
    def!("GetAnimations", |lua, shared, a| {
        let id = a.me()?;
        let world = shared.world.borrow();
        let tables: Vec<Value> = world.objs[id].anim.members.iter().map(|member| Value::Table(world.objs[*member].table.clone())).collect();
        give(lua, MultiValue::from_iter(tables))
    });

    Ok(map)
}

/// Builds the metatable for each class: methods from the documentation, implemented or a gap, and a
/// lookup that records each name asked for and not found.
pub fn build_metatables(lua: &Lua, shared: &Shared) -> Result<()> {
    let implemented = implementations(lua, shared)?;
    let classes = [
        Class::Frame,
        Class::Button,
        Class::ScrollFrame,
        Class::StatusBar,
        Class::Cooldown,
        Class::Tooltip,
        Class::Texture,
        Class::FontString,
        Class::AnimGroup,
        Class::Anim(AnimKind::Alpha),
        Class::Anim(AnimKind::Translation),
        Class::Anim(AnimKind::Scale),
        Class::Anim(AnimKind::Rotation),
    ];
    for class in classes {
        let methods = lua.create_table()?;
        for signature in api::methods(class) {
            let function = match implemented.get(signature.name.as_str()) {
                Some(function) => checked(lua, class, &signature, function.clone())?,
                None => {
                    let label = format!("{}:{} is documented but not implemented", class.type_name(), signature.name);
                    lua.create_function(move |_, _: MultiValue| -> Result<()> { Err(gap(&label)) })?
                }
            };
            methods.set(signature.name.as_str(), function)?;
        }
        // Looking up a method the type does not have is how `call(object, "Name")` skips quietly. Say so.
        let metatable = lua.create_table()?;
        let recorder = shared.clone();
        let type_name = class.type_name();
        let lookup = lua.create_function(move |_, (_, key): (Table, Value)| {
            if let Value::String(name) = &key {
                let name = name.to_str()?;
                let entry = format!("{}.{}", type_name, name);
                if name.chars().next().is_some_and(|first| first.is_uppercase()) {
                    recorder.missing.borrow_mut().push(entry);
                } else {
                    recorder.fields_read.borrow_mut().push(entry);
                }
            }
            Ok(Value::Nil)
        })?;
        let methods_meta = lua.create_table()?;
        methods_meta.set("__index", lookup)?;
        methods.set_metatable(Some(methods_meta))?;
        metatable.set("__index", methods)?;
        shared.metatables.borrow_mut().insert(class, metatable);
    }
    Ok(())
}

/// A method with its arguments checked against what the documentation says: a number is a number, a
/// string is a string. Everything else passes, because the documentation names types this harness does not model.
fn checked(lua: &Lua, class: Class, signature: &Signature, function: Function) -> Result<Function> {
    let signature = signature.clone();
    let type_name = class.type_name();
    lua.create_function(move |_, values: MultiValue| {
        for (index, argument) in signature.arguments.iter().enumerate() {
            let value = values.get(index + 1).cloned().unwrap_or(Value::Nil);
            let present = !matches!(value, Value::Nil);
            let wrong = |expected: &str| {
                mlua::Error::runtime(format!(
                    "bad argument #{} to '{}' ({} expected, got {}) [{}:{}]",
                    index + 1,
                    signature.name,
                    expected,
                    value.type_name(),
                    type_name,
                    argument.name
                ))
            };
            if !present {
                continue;
            }
            // The documentation types an attribute's value as a string; the game stores any value.
            if signature.name == "SetAttribute" && argument.name == "value" {
                continue;
            }
            match argument.kind.as_str() {
                "number" | "luaIndex" | "normalizedValue" | "time_t" | "WOWMONEY" => {
                    let numeric = match &value {
                        Value::Number(_) | Value::Integer(_) => true,
                        Value::String(text) => text.to_str().map(|text| text.parse::<f64>().is_ok()).unwrap_or(false),
                        _ => false,
                    };
                    if !numeric {
                        return Err(wrong("number"));
                    }
                }
                "cstring" => {
                    if !matches!(value, Value::String(_) | Value::Number(_) | Value::Integer(_)) {
                        return Err(wrong("string"));
                    }
                }
                _ => {}
            }
        }
        function.call::<MultiValue>(values)
    })
}

/// The font objects: one global table for each of Blizzard's named fonts, and `CreateFont` for more. A
/// table holds only its name; the file, height and colour live in the world, so a string that follows a
/// font object sees a change to it.
pub fn install_fonts(lua: &Lua, shared: &Shared) -> Result<()> {
    let methods = lua.create_table()?;
    let name_of = |value: &Value| -> Result<String> {
        match value {
            Value::Table(table) => table.get::<Option<String>>("__name")?.ok_or_else(|| mlua::Error::runtime("Wrong object type for function")),
            _ => Err(mlua::Error::runtime("Wrong object type for function")),
        }
    };
    macro_rules! method {
        ($key:literal, |$lua:ident, $shared:ident, $name:ident, $args:ident| $body:expr) => {{
            let $shared = shared.clone();
            methods.set(
                $key,
                lua.create_function(move |$lua, values: MultiValue| -> Result<MultiValue> {
                    let $args = Args { values: values.into_iter().collect() };
                    let $name = name_of($args.values.first().unwrap_or(&Value::Nil))?;
                    $body
                })?,
            )?;
        }};
    }
    method!("GetObjectType", |lua, shared, name, a| {
        let _ = (&shared, &a, &name);
        give(lua, "Font")
    });
    method!("IsObjectType", |lua, shared, name, a| {
        let _ = (&shared, &name);
        give(lua, a.text(1).as_deref() == Some("Font"))
    });
    method!("IsForbidden", |lua, shared, name, a| {
        let _ = (&shared, &a, &name);
        give(lua, false)
    });
    method!("GetName", |lua, shared, name, a| {
        let _ = (&shared, &a);
        give(lua, name)
    });
    method!("SetFont", |lua, shared, name, a| {
        let _ = lua;
        let world = shared.world.borrow();
        let mut book = world.fonts.borrow_mut();
        let def = book.objects.entry(name).or_insert(crate::fonts::FontDef { path: String::new(), height: 12.0, flags: String::new(), color: None, justify_h: None });
        def.path = a.text(1).unwrap_or_default();
        if let Some(height) = a.number(2) {
            def.height = height;
        }
        def.flags = a.text(3).unwrap_or_default();
        nothing()
    });
    method!("GetFont", |lua, shared, name, a| {
        let _ = &a;
        let world = shared.world.borrow();
        let book = world.fonts.borrow();
        match book.objects.get(&name) {
            Some(def) => give(lua, (def.path.clone(), def.height, def.flags.clone())),
            None => nothing(),
        }
    });
    method!("SetFontObject", |lua, shared, name, a| {
        let _ = lua;
        let other = a.values.get(1).map(|value| name_of(value)).transpose()?;
        let world = shared.world.borrow();
        let mut book = world.fonts.borrow_mut();
        if let Some(def) = other.and_then(|other| book.objects.get(&other).cloned()) {
            book.objects.insert(name, def);
        }
        nothing()
    });
    method!("CopyFontObject", |lua, shared, name, a| {
        let _ = lua;
        let other = a.values.get(1).map(|value| name_of(value)).transpose()?;
        let world = shared.world.borrow();
        let mut book = world.fonts.borrow_mut();
        if let Some(def) = other.and_then(|other| book.objects.get(&other).cloned()) {
            book.objects.insert(name, def);
        }
        nothing()
    });
    method!("SetTextColor", |lua, shared, name, a| {
        let _ = lua;
        let world = shared.world.borrow();
        if let Some(def) = world.fonts.borrow_mut().objects.get_mut(&name) {
            def.color = Some(a.colour(1));
        }
        nothing()
    });
    method!("GetTextColor", |lua, shared, name, a| {
        let _ = &a;
        let world = shared.world.borrow();
        let color = world.fonts.borrow().objects.get(&name).and_then(|def| def.color).unwrap_or([1.0; 4]);
        give(lua, (color[0], color[1], color[2], color[3]))
    });
    method!("SetJustifyH", |lua, shared, name, a| {
        let _ = lua;
        let world = shared.world.borrow();
        if let Some(def) = world.fonts.borrow_mut().objects.get_mut(&name) {
            def.justify_h = a.text(1);
        }
        nothing()
    });
    method!("GetJustifyH", |lua, shared, name, a| {
        let _ = &a;
        let world = shared.world.borrow();
        let justify = world.fonts.borrow().objects.get(&name).and_then(|def| def.justify_h.clone());
        give(lua, justify)
    });
    for ignored in ["SetShadowColor", "SetShadowOffset", "SetJustifyV", "SetSpacing", "SetAlpha", "SetIndentedWordWrap", "SetFontHeight"] {
        methods.set(ignored, lua.create_function(|_, _: MultiValue| Ok(()))?)?;
    }
    let metatable = lua.create_table()?;
    metatable.set("__index", methods)?;

    let make = {
        let metatable = metatable.clone();
        move |lua: &Lua, name: &str| -> Result<Table> {
            let table = lua.create_table()?;
            table.set("__name", name)?;
            table.set_metatable(Some(metatable.clone()))?;
            lua.globals().set(name, table.clone())?;
            Ok(table)
        }
    };
    let names: Vec<String> = shared.world.borrow().fonts.borrow().objects.keys().cloned().collect();
    for name in names {
        make(lua, &name)?;
    }
    let create_shared = shared.clone();
    lua.globals().set(
        "CreateFont",
        lua.create_function(move |lua, name: String| {
            let world = create_shared.world.borrow();
            world.fonts.borrow_mut().objects.entry(name.clone()).or_insert(crate::fonts::FontDef { path: String::new(), height: 12.0, flags: String::new(), color: None, justify_h: None });
            drop(world);
            make(lua, &name)
        })?,
    )?;
    Ok(())
}

const TIP_PAD: f32 = 10.0;
const TIP_GAP: f32 = 2.0;
const TIP_WRAP: f32 = 300.0;

/// The tooltip's strings, which the game makes for it and names GameTooltipTextLeft1, TextRight1 and so on.
fn tip_string(lua: &Lua, shared: &Shared, tip: Id, side: &str, number: usize) -> Result<Id> {
    let base = shared.world.borrow().objs[tip].name.clone().unwrap_or_else(|| format!("Tooltip{tip}"));
    let name = format!("{base}Text{side}{number}");
    if let Some(found) = shared.world.borrow().globals_named.get(&name).copied() {
        return Ok(found);
    }
    let id = make_object(lua, shared, Class::FontString, Some(name.clone()), Some(tip))?;
    let mut world = shared.world.borrow_mut();
    world.globals_named.insert(name, id);
    world.objs[id].texture.layer = "ARTWORK".into();
    world.objs[id].text.justify_h = side.to_uppercase();
    world.objs[id].text.wrap = false;
    Ok(id)
}

/// Lays a tooltip out the way the game does: ten in from every edge, a line under the last with two between,
/// the width the widest line wants, and the whole put by its owner. Engine fact 15.
pub fn tooltip_layout(lua: &Lua, shared: &Shared, tip: Id) -> Result<()> {
    let lines = shared.world.borrow().objs[tip].tip.clone();
    {
        let world = shared.world.borrow();
        let has_back = world.objs[tip].regions.iter().any(|region| world.objs[*region].class == Class::Texture);
        drop(world);
        if !has_back {
            let back = make_object(lua, shared, Class::Texture, None, Some(tip))?;
            let mut world = shared.world.borrow_mut();
            world.objs[back].texture.layer = "BACKGROUND".into();
            world.objs[back].texture.color = Some([0.04, 0.05, 0.07, 0.94]);
            world.objs[back].all_points = Some(None);
        }
    }
    let mut y = TIP_PAD;
    let mut width: f32 = 0.0;
    for (index, line) in lines.iter().enumerate() {
        let number = index + 1;
        let left = tip_string(lua, shared, tip, "Left", number)?;
        let right = tip_string(lua, shared, tip, "Right", number)?;
        let font = if number == 1 { "GameTooltipHeaderText" } else { "GameTooltipText" };
        {
            let mut world = shared.world.borrow_mut();
            for (id, text, color) in [(left, Some(line.left.clone()), line.left_color), (right, line.right.clone(), line.right_color)] {
                let obj = &mut world.objs[id];
                obj.text.text = text.clone().unwrap_or_default();
                obj.text.font_object = Some(font.to_string());
                obj.text.font = None;
                obj.text.color = color;
                obj.shown = text.is_some();
                obj.width = None;
                obj.text.wrap = line.wrap;
            }
            // A line that may wrap takes the room it wants up to a limit, and wraps there.
            for id in [left, right] {
                if line.wrap && world.string_width(id) > TIP_WRAP {
                    world.objs[id].width = Some(TIP_WRAP);
                }
            }
            world.objs[left].points = vec![Anchor { point: Point::TopLeft, relative: Some(tip), relative_point: Point::TopLeft, x: TIP_PAD, y: -y }];
            world.objs[right].points = vec![Anchor { point: Point::TopRight, relative: Some(tip), relative_point: Point::TopRight, x: -TIP_PAD, y: -y }];
        }
        let world = shared.world.borrow();
        let left_rect = world.rect(left);
        let right_rect = world.rect(right);
        let right_width = if line.right.is_some() { right_rect.width + 20.0 } else { 0.0 };
        width = width.max(left_rect.width + right_width);
        y += left_rect.height.max(right_rect.height) + TIP_GAP;
    }
    // Strings left over from a longer tooltip are hidden.
    let used = lines.len();
    let base = shared.world.borrow().objs[tip].name.clone().unwrap_or_else(|| format!("Tooltip{tip}"));
    let mut world = shared.world.borrow_mut();
    let mut number = used + 1;
    while let Some(id) = world.globals_named.get(&format!("{base}TextLeft{number}")).copied() {
        world.objs[id].shown = false;
        if let Some(id) = world.globals_named.get(&format!("{base}TextRight{number}")).copied() {
            world.objs[id].shown = false;
        }
        number += 1;
    }
    let (w, h) = (width + 2.0 * TIP_PAD, (y - TIP_GAP) + TIP_PAD);
    world.objs[tip].width = Some(w);
    world.objs[tip].height = Some(h);
    if let Some(owner) = world.objs[tip].tip_owner {
        let anchor = world.objs[tip].tip_anchor.clone();
        let pointer = world.pointer;
        let (point, relative_point, x, y) = match anchor.as_str() {
            "ANCHOR_RIGHT" => (Point::BottomLeft, Point::TopRight, 0.0, 0.0),
            "ANCHOR_LEFT" => (Point::BottomRight, Point::TopLeft, 0.0, 0.0),
            "ANCHOR_TOP" => (Point::Bottom, Point::Top, 0.0, 0.0),
            "ANCHOR_BOTTOM" => (Point::Top, Point::Bottom, 0.0, 0.0),
            "ANCHOR_TOPRIGHT" => (Point::BottomLeft, Point::TopRight, 0.0, 0.0),
            "ANCHOR_CURSOR" => (Point::BottomLeft, Point::TopLeft, pointer.0, -pointer.1),
            _ => (Point::BottomLeft, Point::TopRight, 0.0, 0.0),
        };
        if anchor != "ANCHOR_NONE" {
            let relative = if anchor == "ANCHOR_CURSOR" { None } else { Some(owner) };
            world.objs[tip].points = vec![Anchor { point, relative, relative_point, x, y }];
            world.objs[tip].all_points = None;
        }
    }
    Ok(())
}

/// GameTooltip, there from the start, hidden, in the tooltip strata, above every other frame.
pub fn install_tooltip(lua: &Lua, shared: &Shared, parent: Id) -> Result<()> {
    let tip = make_object(lua, shared, Class::Tooltip, Some("GameTooltip".into()), Some(parent))?;
    let mut world = shared.world.borrow_mut();
    world.globals_named.insert("GameTooltip".into(), tip);
    world.objs[tip].strata = Strata::Tooltip;
    world.objs[tip].shown = false;
    Ok(())
}
