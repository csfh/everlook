//! A small part of the game's XML frame format: the part the Everlook addons use. A table of contents may
//! list `.xml` files; each holds templates (`virtual="true"`) that `CreateFrame(..., "Template")` applies, and
//! named frames made when the file loads.
//!
//! Only what is listed below is read. Any other element or attribute stops the load with a HARNESS GAP that
//! names it, so a file is never half understood in silence.
//!
//! Frames: name, virtual, inherits, mixin, enableMouse, hidden, parentKey, alpha, frameStrata, frameLevel, id.
//!   Children: Size, Anchors, Layers, Frames, Scripts.
//! Regions (in a Layer): Texture and FontString with name, parentKey, setAllPoints, file, atlas, hidden,
//!   inherits, text, justifyH, alpha. Children: Size, Anchors.

use crate::bind::{GAP, frame_class, id_of, make_object, table_of};
use crate::runtime::Shared;
use crate::world::{Anchor, Class, Id, Point, Strata};
use mlua::{Function, Lua, MultiValue, Table, Value};
use std::path::Path;

type Result<T> = mlua::Result<T>;

#[derive(Clone)]
pub struct AnchorSpec {
    pub point: Point,
    pub relative_to: Option<String>,
    pub relative_point: Point,
    pub x: f32,
    pub y: f32,
}

#[derive(Clone, Copy, PartialEq)]
pub enum RegionKind {
    Texture,
    FontString,
}

#[derive(Clone)]
pub struct RegionSpec {
    pub kind: RegionKind,
    pub name: Option<String>,
    pub parent_key: Option<String>,
    pub set_all_points: bool,
    pub file: Option<String>,
    pub atlas: Option<String>,
    pub hidden: bool,
    pub inherits: Option<String>,
    pub text: Option<String>,
    pub justify_h: Option<String>,
    pub alpha: Option<f32>,
    pub layer: String,
    pub size: Option<(f32, f32)>,
    pub anchors: Vec<AnchorSpec>,
}

#[derive(Clone)]
pub struct Tmpl {
    pub frame_type: String,
    pub name: Option<String>,
    pub is_virtual: bool,
    pub inherits: Vec<String>,
    pub mixins: Vec<String>,
    pub enable_mouse: Option<bool>,
    pub hidden: bool,
    pub parent_key: Option<String>,
    pub alpha: Option<f32>,
    pub strata: Option<String>,
    pub level: Option<i32>,
    pub id_number: Option<i64>,
    pub size: Option<(f32, f32)>,
    pub anchors: Vec<AnchorSpec>,
    pub regions: Vec<RegionSpec>,
    pub children: Vec<Tmpl>,
    pub scripts: Vec<(String, Function)>,
}

fn gap(what: String) -> mlua::Error {
    mlua::Error::runtime(format!("{GAP}: XML {what} is not implemented"))
}

fn number(node: roxmltree::Node, key: &str) -> Option<f32> {
    node.attribute(key).and_then(|value| value.trim().parse().ok())
}

fn flag(node: roxmltree::Node, key: &str) -> Option<bool> {
    node.attribute(key).map(|value| value == "true")
}

fn check_attributes(node: roxmltree::Node, allowed: &[&str]) -> Result<()> {
    for attribute in node.attributes() {
        if !allowed.contains(&attribute.name()) {
            return Err(gap(format!("attribute {}=\"…\" on <{}>", attribute.name(), node.tag_name().name())));
        }
    }
    Ok(())
}

/// A size or an offset, written `x`/`y` on the element or inside an `<AbsDimension>`.
fn dimension(node: roxmltree::Node) -> Result<Option<(f32, f32)>> {
    if let (Some(x), Some(y)) = (number(node, "x"), number(node, "y")) {
        return Ok(Some((x, y)));
    }
    for child in node.children().filter(|child| child.is_element()) {
        match child.tag_name().name() {
            "AbsDimension" => return Ok(Some((number(child, "x").unwrap_or(0.0), number(child, "y").unwrap_or(0.0)))),
            other => return Err(gap(format!("<{other}> inside <{}>", node.tag_name().name()))),
        }
    }
    Ok(None)
}

fn read_anchors(node: roxmltree::Node) -> Result<Vec<AnchorSpec>> {
    let mut list = Vec::new();
    for anchor in node.children().filter(|child| child.is_element()) {
        if anchor.tag_name().name() != "Anchor" {
            return Err(gap(format!("<{}> inside <Anchors>", anchor.tag_name().name())));
        }
        check_attributes(anchor, &["point", "relativeTo", "relativePoint", "x", "y"])?;
        let point = anchor.attribute("point").and_then(Point::parse).ok_or_else(|| mlua::Error::runtime("XML <Anchor> needs a point"))?;
        let relative_point = anchor.attribute("relativePoint").and_then(Point::parse).unwrap_or(point);
        let (mut x, mut y) = (number(anchor, "x").unwrap_or(0.0), number(anchor, "y").unwrap_or(0.0));
        for child in anchor.children().filter(|child| child.is_element()) {
            match child.tag_name().name() {
                "Offset" => {
                    if let Some((offset_x, offset_y)) = dimension(child)? {
                        x = offset_x;
                        y = offset_y;
                    }
                }
                other => return Err(gap(format!("<{other}> inside <Anchor>"))),
            }
        }
        list.push(AnchorSpec { point, relative_to: anchor.attribute("relativeTo").map(str::to_string), relative_point, x, y });
    }
    Ok(list)
}

fn read_region(node: roxmltree::Node, layer: &str) -> Result<RegionSpec> {
    let kind = match node.tag_name().name() {
        "Texture" => RegionKind::Texture,
        "FontString" => RegionKind::FontString,
        other => return Err(gap(format!("region <{other}>"))),
    };
    check_attributes(node, &["name", "parentKey", "setAllPoints", "file", "atlas", "hidden", "inherits", "text", "justifyH", "alpha"])?;
    let mut region = RegionSpec {
        kind,
        name: node.attribute("name").map(str::to_string),
        parent_key: node.attribute("parentKey").map(str::to_string),
        set_all_points: flag(node, "setAllPoints").unwrap_or(false),
        file: node.attribute("file").map(str::to_string),
        atlas: node.attribute("atlas").map(str::to_string),
        hidden: flag(node, "hidden").unwrap_or(false),
        inherits: node.attribute("inherits").map(str::to_string),
        text: node.attribute("text").map(str::to_string),
        justify_h: node.attribute("justifyH").map(str::to_string),
        alpha: number(node, "alpha"),
        layer: layer.to_string(),
        size: None,
        anchors: Vec::new(),
    };
    for child in node.children().filter(|child| child.is_element()) {
        match child.tag_name().name() {
            "Size" => region.size = dimension(child)?,
            "Anchors" => region.anchors = read_anchors(child)?,
            other => return Err(gap(format!("<{other}> inside <{}>", node.tag_name().name()))),
        }
    }
    Ok(region)
}

/// What an inline script is given besides `self`, by script name.
fn script_arguments(script: &str) -> &'static str {
    match script {
        "OnEvent" => "event",
        "OnClick" | "PostClick" | "PreClick" => "button, down",
        "OnUpdate" => "elapsed",
        "OnEnter" | "OnLeave" => "motion",
        "OnMouseDown" | "OnMouseUp" => "button",
        "OnMouseWheel" => "delta",
        "OnAttributeChanged" => "name, value",
        _ => "",
    }
}

fn read_frame(lua: &Lua, node: roxmltree::Node) -> Result<Tmpl> {
    let tag = node.tag_name().name();
    if frame_class(tag).is_none() {
        return Err(gap(format!("frame type <{tag}>")));
    }
    check_attributes(node, &["name", "virtual", "inherits", "mixin", "enableMouse", "hidden", "parentKey", "alpha", "frameStrata", "frameLevel", "id"])?;
    let list = |key: &str| -> Vec<String> { node.attribute(key).map(|value| value.split(',').map(|part| part.trim().to_string()).filter(|part| !part.is_empty()).collect()).unwrap_or_default() };
    let mut tmpl = Tmpl {
        frame_type: tag.to_string(),
        name: node.attribute("name").map(str::to_string),
        is_virtual: flag(node, "virtual").unwrap_or(false),
        inherits: list("inherits"),
        mixins: list("mixin"),
        enable_mouse: flag(node, "enableMouse"),
        hidden: flag(node, "hidden").unwrap_or(false),
        parent_key: node.attribute("parentKey").map(str::to_string),
        alpha: number(node, "alpha"),
        strata: node.attribute("frameStrata").map(str::to_string),
        level: number(node, "frameLevel").map(|level| level as i32),
        id_number: number(node, "id").map(|id| id as i64),
        size: None,
        anchors: Vec::new(),
        regions: Vec::new(),
        children: Vec::new(),
        scripts: Vec::new(),
    };
    for child in node.children().filter(|child| child.is_element()) {
        match child.tag_name().name() {
            "Size" => tmpl.size = dimension(child)?,
            "Anchors" => tmpl.anchors = read_anchors(child)?,
            "Layers" => {
                for layer in child.children().filter(|layer| layer.is_element()) {
                    if layer.tag_name().name() != "Layer" {
                        return Err(gap(format!("<{}> inside <Layers>", layer.tag_name().name())));
                    }
                    check_attributes(layer, &["level", "textureSubLevel"])?;
                    let level = layer.attribute("level").unwrap_or("ARTWORK");
                    for region in layer.children().filter(|region| region.is_element()) {
                        tmpl.regions.push(read_region(region, level)?);
                    }
                }
            }
            "Frames" => {
                for frame in child.children().filter(|frame| frame.is_element()) {
                    tmpl.children.push(read_frame(lua, frame)?);
                }
            }
            "Scripts" => {
                for script in child.children().filter(|script| script.is_element()) {
                    let name = script.tag_name().name().to_string();
                    let function = if let Some(target) = script.attribute("function") {
                        let target = target.to_string();
                        lua.load(format!("local f = _G[{target:?}]; if type(f) ~= \"function\" then error(\"script function {target} is not defined\") end; return f(...)")).into_function()?
                    } else {
                        let body = script.text().unwrap_or_default();
                        let extra = script_arguments(&name);
                        let names = if extra.is_empty() { "self".to_string() } else { format!("self, {extra}") };
                        lua.load(format!("local {names} = ...; {body}")).set_name(format!("@xml:{}:{name}", tmpl.name.clone().unwrap_or_default())).into_function()?
                    };
                    tmpl.scripts.push((name, function));
                }
            }
            other => return Err(gap(format!("<{other}> inside <{tag}>"))),
        }
    }
    Ok(tmpl)
}

fn point_args(anchor: &AnchorSpec, shared: &Shared, parent: Option<Id>, frame: Id) -> Result<Anchor> {
    let relative = match anchor.relative_to.as_deref() {
        None => None,
        Some("$parent") => parent,
        Some(name) => {
            let name = match (name.strip_prefix("$parent"), parent) {
                (Some(rest), Some(parent)) => format!("{}{rest}", shared.world.borrow().objs[parent].name.clone().unwrap_or_default()),
                _ => name.to_string(),
            };
            Some(shared.world.borrow().globals_named.get(&name).copied().ok_or_else(|| mlua::Error::runtime(format!("XML: anchor relativeTo '{name}' is not a frame")))?)
        }
    };
    let _ = frame;
    Ok(Anchor { point: anchor.point, relative, relative_point: anchor.relative_point, x: anchor.x, y: anchor.y })
}

fn set_key(lua: &Lua, parent_table: &Table, key: &Option<String>, value: Table) -> Result<()> {
    let _ = lua;
    if let Some(key) = key {
        parent_table.set(key.as_str(), value)?;
    }
    Ok(())
}

/// Puts a template on a frame that already exists, inherited templates first, then makes its regions and
/// child frames. Scripts are set here and `OnLoad` is run by the caller once everything is in place.
pub fn apply(lua: &Lua, shared: &Shared, frame: Id, tmpl: &Tmpl, depth: usize) -> Result<()> {
    if depth > 16 {
        return Err(mlua::Error::runtime("XML: templates inherit too deeply"));
    }
    for name in &tmpl.inherits {
        let parent = shared.templates.borrow().get(name).cloned();
        if let Some(parent) = parent {
            apply(lua, shared, frame, &parent, depth + 1)?;
        }
    }
    let table = table_of(shared, frame);
    for mixin in &tmpl.mixins {
        match lua.globals().get::<Value>(mixin.as_str())? {
            Value::Table(source) => {
                for pair in source.pairs::<Value, Value>() {
                    let (key, value) = pair?;
                    table.set(key, value)?;
                }
            }
            _ => return Err(mlua::Error::runtime(format!("XML: mixin '{mixin}' is not a global table"))),
        }
    }
    {
        let mut world = shared.world.borrow_mut();
        let parent = world.objs[frame].parent;
        let obj = &mut world.objs[frame];
        if let Some(enable) = tmpl.enable_mouse {
            obj.mouse_click = enable;
            obj.mouse_motion = enable;
        }
        if tmpl.hidden {
            obj.shown = false;
        }
        if let Some(alpha) = tmpl.alpha {
            obj.alpha = alpha;
        }
        if let Some(strata) = tmpl.strata.as_deref().and_then(Strata::parse) {
            obj.strata = strata;
        }
        if let Some(level) = tmpl.level {
            obj.level = level;
        }
        if let Some(id) = tmpl.id_number {
            obj.id_number = id;
        }
        if let Some((width, height)) = tmpl.size {
            obj.width = Some(width);
            obj.height = Some(height);
        }
        drop(world);
        let _ = parent;
    }
    if !tmpl.anchors.is_empty() {
        let parent = shared.world.borrow().objs[frame].parent;
        let mut points = Vec::new();
        for anchor in &tmpl.anchors {
            points.push(point_args(anchor, shared, parent, frame)?);
        }
        shared.world.borrow_mut().objs[frame].points = points;
    }
    for region in &tmpl.regions {
        let class = if region.kind == RegionKind::Texture { Class::Texture } else { Class::FontString };
        let name = region.name.as_ref().map(|name| match name.strip_prefix("$parent") {
            Some(rest) => format!("{}{rest}", shared.world.borrow().objs[frame].name.clone().unwrap_or_default()),
            None => name.clone(),
        });
        let id = make_object(lua, shared, class, name, Some(frame))?;
        {
            let mut world = shared.world.borrow_mut();
            let obj = &mut world.objs[id];
            obj.texture.layer = region.layer.clone();
            obj.shown = !region.hidden;
            if let Some(alpha) = region.alpha {
                obj.alpha = alpha;
            }
            if let Some((width, height)) = region.size {
                obj.width = Some(width);
                obj.height = Some(height);
            }
            if region.set_all_points {
                obj.all_points = Some(None);
            }
            obj.texture.path = region.file.clone();
            obj.texture.atlas = region.atlas.clone();
            if let Some(font) = &region.inherits {
                obj.text.font_object = Some(font.clone());
            }
            if let Some(text) = &region.text {
                obj.text.text = text.clone();
            }
            if let Some(justify) = &region.justify_h {
                obj.text.justify_h = justify.clone();
            }
        }
        if !region.anchors.is_empty() {
            let mut points = Vec::new();
            for anchor in &region.anchors {
                points.push(point_args(anchor, shared, Some(frame), id)?);
            }
            shared.world.borrow_mut().objs[id].points = points;
        }
        set_key(lua, &table, &region.parent_key, table_of(shared, id))?;
    }
    for child in &tmpl.children {
        let class = frame_class(&child.frame_type).unwrap_or(Class::Frame);
        let name = child.name.as_ref().map(|name| match name.strip_prefix("$parent") {
            Some(rest) => format!("{}{rest}", shared.world.borrow().objs[frame].name.clone().unwrap_or_default()),
            None => name.clone(),
        });
        let id = make_object(lua, shared, class, name, Some(frame))?;
        apply(lua, shared, id, child, depth + 1)?;
        set_key(lua, &table, &child.parent_key, table_of(shared, id))?;
        crate::bind::fire(lua, shared, id, "OnLoad", MultiValue::new())?;
    }
    for (name, function) in &tmpl.scripts {
        shared.world.borrow_mut().objs[frame].scripts.insert(name.clone(), function.clone());
    }
    Ok(())
}

/// Reads a file of templates and frames. Templates are kept by name; a frame that is not virtual is made.
pub fn load(lua: &Lua, shared: &Shared, path: &Path) -> Result<()> {
    let text = std::fs::read_to_string(path).map_err(|error| mlua::Error::runtime(format!("{}: {error}", path.display())))?;
    let document = roxmltree::Document::parse(&text).map_err(|error| mlua::Error::runtime(format!("{}: {error}", path.display())))?;
    for node in document.root_element().children().filter(|node| node.is_element()) {
        match node.tag_name().name() {
            "Include" => {
                let file = node.attribute("file").ok_or_else(|| mlua::Error::runtime("XML <Include> needs a file"))?;
                load(lua, shared, &path.parent().unwrap_or(Path::new(".")).join(file.replace('\\', "/")))?;
            }
            _ => {
                let tmpl = read_frame(lua, node)?;
                if tmpl.is_virtual {
                    let name = tmpl.name.clone().ok_or_else(|| mlua::Error::runtime("XML: a virtual frame needs a name"))?;
                    shared.templates.borrow_mut().insert(name, tmpl);
                } else {
                    let class = frame_class(&tmpl.frame_type).unwrap_or(Class::Frame);
                    let root = shared.world.borrow().globals_named.get("UIParent").copied();
                    let id = make_object(lua, shared, class, tmpl.name.clone(), root)?;
                    if let Some(name) = &tmpl.name {
                        shared.world.borrow_mut().globals_named.insert(name.clone(), id);
                    }
                    apply(lua, shared, id, &tmpl, 0)?;
                    crate::bind::fire(lua, shared, id, "OnLoad", MultiValue::new())?;
                }
            }
        }
    }
    let _ = id_of;
    Ok(())
}

/// Applies each named template to a frame `CreateFrame` has just made, then runs its `OnLoad`. A name that is
/// not a template from XML is one of Blizzard's, which the harness does not have; it is recorded and left.
pub fn apply_named(lua: &Lua, shared: &Shared, frame: Id, names: &str) -> Result<()> {
    let mut applied = false;
    for name in names.split(',').map(str::trim).filter(|name| !name.is_empty()) {
        let found = shared.templates.borrow().get(name).cloned();
        match found {
            Some(tmpl) => {
                apply(lua, shared, frame, &tmpl, 0)?;
                applied = true;
            }
            None => shared.unknown_templates.borrow_mut().push(name.to_string()),
        }
    }
    if applied {
        crate::bind::fire(lua, shared, frame, "OnLoad", MultiValue::new())?;
    }
    Ok(())
}
