//! Reads Blizzard's generated widget documentation (`Simple*APIDocumentation.lua` in wow-ui-source) and
//! writes `api/widgets.json`: for every widget API table, each function with its arguments.
//!
//! The documentation files are plain Lua that registers a table with `APIDocumentation:AddDocumentationTable`,
//! so they are run as they are with that one call caught.

use mlua::{Lua, LuaSerdeExt, Table};
use serde_json::{Value, json};
use std::path::Path;

pub fn generate(wow_ui_source: &Path, output: &Path) -> Result<usize, Box<dyn std::error::Error>> {
    let documentation = wow_ui_source.join("Interface/AddOns/Blizzard_APIDocumentationGenerated");
    let mut files: Vec<_> = std::fs::read_dir(&documentation)?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| {
            let name = path.file_name().and_then(|name| name.to_str()).unwrap_or("");
            (name.starts_with("Simple") || name.starts_with("FrameAPICooldown") || name.starts_with("FrameAPITooltip")) && name.ends_with("Documentation.lua")
        })
        .collect();
    files.sort();

    let mut tables = serde_json::Map::new();
    for path in &files {
        let lua = Lua::new();
        let caught = lua.create_table()?;
        let catcher = lua.create_table()?;
        let sink = caught.clone();
        catcher.set(
            "AddDocumentationTable",
            lua.create_function(move |_, (_, table): (mlua::Value, Table)| {
                sink.set("table", table)?;
                Ok(())
            })?,
        )?;
        lua.globals().set("APIDocumentation", catcher)?;
        // A few files name enum values and constants from other tables. Their values are not wanted here.
        lua.load("local any = setmetatable({}, { __index = function(self) return self end, __call = function(self) return self end }); setmetatable(_G, { __index = function() return any end })").exec()?;
        lua.load(std::fs::read_to_string(path)?).set_name(path.display().to_string()).exec()?;
        let table: Table = caught.get("table")?;
        let value: Value = lua.from_value(mlua::Value::Table(table))?;
        let name = value["Name"].as_str().unwrap_or_default().to_string();
        let functions: Vec<Value> = value["Functions"]
            .as_array()
            .map(|list| {
                list.iter()
                    .map(|function| {
                        let arguments: Vec<Value> = function["Arguments"]
                            .as_array()
                            .map(|list| {
                                list.iter()
                                    .map(|argument| {
                                        json!({
                                            "name": argument["Name"],
                                            "type": argument["Type"],
                                            "nilable": argument["Nilable"].as_bool().unwrap_or(false),
                                            "default": argument.get("Default").cloned().unwrap_or(Value::Null),
                                        })
                                    })
                                    .collect()
                            })
                            .unwrap_or_default();
                        let returns = function["Returns"].as_array().map(|list| list.len()).unwrap_or(0);
                        json!({ "name": function["Name"], "arguments": arguments, "returns": returns })
                    })
                    .collect()
            })
            .unwrap_or_default();
        if !name.is_empty() {
            tables.insert(name, json!({ "functions": functions }));
        }
    }
    let count = tables.len();
    std::fs::write(output, serde_json::to_string_pretty(&Value::Object(tables))? + "\n")?;
    Ok(count)
}

#[derive(Default, Clone)]
struct RawFont {
    inherits: Option<String>,
    font: Option<String>,
    height: Option<f64>,
    outline: Option<String>,
    justify_h: Option<String>,
    color: Option<[f64; 4]>,
}

fn named_color(name: &str) -> Option<[f64; 4]> {
    Some(match name {
        "NORMAL_FONT_COLOR" => [1.0, 0.82, 0.0, 1.0],
        "WHITE_FONT_COLOR" | "HIGHLIGHT_FONT_COLOR" => [1.0, 1.0, 1.0, 1.0],
        "RED_FONT_COLOR" => [1.0, 0.1, 0.1, 1.0],
        "GREEN_FONT_COLOR" => [0.1, 1.0, 0.1, 1.0],
        "GRAY_FONT_COLOR" | "DISABLED_FONT_COLOR" => [0.5, 0.5, 0.5, 1.0],
        "YELLOW_FONT_COLOR" => [1.0, 1.0, 0.0, 1.0],
        _ => return None,
    })
}

fn read_font_element(node: roxmltree::Node) -> RawFont {
    let mut raw = RawFont {
        inherits: node.attribute("inherits").map(str::to_string),
        font: node.attribute("font").map(str::to_string),
        height: node.attribute("height").and_then(|value| value.parse().ok()),
        outline: node.attribute("outline").map(str::to_string),
        justify_h: node.attribute("justifyH").map(str::to_string),
        color: None,
    };
    for child in node.children().filter(|child| child.is_element()) {
        if child.tag_name().name() == "Color" {
            raw.color = if let Some(name) = child.attribute("color") {
                named_color(name)
            } else {
                let channel = |key: &str, fallback: f64| child.attribute(key).and_then(|value| value.parse().ok()).unwrap_or(fallback);
                Some([channel("r", 1.0), channel("g", 1.0), channel("b", 1.0), channel("a", 1.0)])
            };
        }
    }
    raw
}

/// Reads Blizzard's font XML (the shared files, then Mainline's on top) and writes `api/fonts.json`: every
/// named font object with the file, height, outline and colour it ends up with once what it inherits is applied.
pub fn generate_fonts(wow_ui_source: &Path, output: &Path) -> Result<usize, Box<dyn std::error::Error>> {
    let base = wow_ui_source.join("Interface/AddOns/Blizzard_Fonts_Shared");
    let mut raw: std::collections::HashMap<String, RawFont> = std::collections::HashMap::new();
    for folder in ["Shared", "Mainline"] {
        for file in ["Fonts.xml", "FontStyles.xml", "GameFonts.xml", "GameFontStyles.xml"] {
            let path = base.join(folder).join(file);
            let Ok(text) = std::fs::read_to_string(&path) else { continue };
            let document = roxmltree::Document::parse(&text)?;
            for node in document.root_element().children().filter(|node| node.is_element()) {
                let Some(name) = node.attribute("name") else { continue };
                match node.tag_name().name() {
                    "Font" => {
                        raw.insert(name.to_string(), read_font_element(node));
                    }
                    "FontFamily" => {
                        // The roman member is the one an English client uses.
                        let member = node.children().find(|child| child.is_element() && child.attribute("alphabet") == Some("roman"));
                        if let Some(font) = member.and_then(|member| member.children().find(|child| child.is_element() && child.tag_name().name() == "Font")) {
                            raw.insert(name.to_string(), read_font_element(font));
                        }
                    }
                    _ => {}
                }
            }
        }
    }
    fn resolve(name: &str, raw: &std::collections::HashMap<String, RawFont>, depth: usize) -> RawFont {
        let Some(own) = raw.get(name) else { return RawFont::default() };
        let mut result = match (&own.inherits, depth < 16) {
            (Some(parent), true) => resolve(parent, raw, depth + 1),
            _ => RawFont::default(),
        };
        result.font = own.font.clone().or(result.font);
        result.height = own.height.or(result.height);
        result.outline = own.outline.clone().or(result.outline);
        result.justify_h = own.justify_h.clone().or(result.justify_h);
        result.color = own.color.or(result.color);
        result
    }
    let mut names: Vec<&String> = raw.keys().collect();
    names.sort();
    let mut fonts = serde_json::Map::new();
    for name in names {
        let font = resolve(name, &raw, 0);
        if let (Some(file), Some(height)) = (&font.font, font.height) {
            fonts.insert(name.clone(), json!({ "font": file, "height": height, "outline": font.outline, "justify_h": font.justify_h, "color": font.color }));
        }
    }
    let count = fonts.len();
    std::fs::write(output, serde_json::to_string_pretty(&Value::Object(fonts))? + "\n")?;
    Ok(count)
}
