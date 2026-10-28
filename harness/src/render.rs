//! The screen as an HTML page. `page` takes the world as it is and gives one self-contained file: the
//! draw list, the addon's own textures (as PNG) and its fonts, and a few lines of script that draw them.
//! With `interactive` the page also sends the pointer and the wheel back to a server and redraws.

use crate::scene;
use crate::world::World;
use base64::Engine;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::io::Cursor;
use std::path::{Path, PathBuf};

pub struct Assets {
    addons: PathBuf,
    textures: HashMap<String, Option<String>>,
}

impl Assets {
    pub fn new(addons: &Path) -> Assets {
        Assets { addons: addons.to_path_buf(), textures: HashMap::new() }
    }

    /// A texture file of an addon as a PNG data URI. Blizzard's own art is not here, and gives None.
    fn texture(&mut self, path: &str) -> Option<String> {
        if let Some(found) = self.textures.get(path) {
            return found.clone();
        }
        let normal = path.replace('\\', "/");
        let lower = normal.to_lowercase();
        let relative = lower.find("interface/addons/").map(|index| normal[index + "interface/addons/".len()..].to_string());
        let mut result = None;
        if let Some(relative) = relative {
            let mut file = self.addons.join(&relative);
            if file.extension().is_none() {
                file.set_extension("tga");
            }
            if let Ok(image) = image::open(&file) {
                let mut bytes: Vec<u8> = Vec::new();
                if image.write_to(&mut Cursor::new(&mut bytes), image::ImageFormat::Png).is_ok() {
                    result = Some(format!("data:image/png;base64,{}", base64::engine::general_purpose::STANDARD.encode(bytes)));
                }
            }
        }
        self.textures.insert(path.to_string(), result.clone());
        result
    }
}

/// The textures and fonts the scene uses, by path, ready for the page.
pub fn assets_for(world: &World, scene: &Value, assets: &mut Assets) -> Value {
    let mut textures = serde_json::Map::new();
    let mut fonts = serde_json::Map::new();
    for item in scene["items"].as_array().into_iter().flatten() {
        let mut paths: Vec<&str> = item["path"].as_str().into_iter().collect();
        paths.extend(item["masks"].as_array().into_iter().flatten().filter_map(|mask| mask["path"].as_str()));
        for path in paths {
            if !textures.contains_key(path) {
                textures.insert(path.to_string(), assets.texture(path).map(Value::String).unwrap_or(Value::Null));
            }
        }
        if let Some(path) = item["font"].as_str() {
            if !fonts.contains_key(path) {
                let bytes = world.fonts.borrow_mut().file_bytes(path);
                let uri = bytes.map(|bytes| format!("data:font/ttf;base64,{}", base64::engine::general_purpose::STANDARD.encode(bytes.as_slice())));
                fonts.insert(path.to_string(), json!({ "family": format!("f{}", fonts.len()), "uri": uri }));
            }
        }
    }
    json!({ "textures": textures, "fonts": fonts })
}

/// The page for the game as it is, or, when a scenario took snapshots, one page that switches between them.
pub fn page(world: &World, snapshots: &[(String, Value)], assets: &mut Assets, interactive: bool, title: &str) -> String {
    let current = scene::scene(world);
    let pictures: Vec<(String, Value)> = if interactive || snapshots.is_empty() { vec![("now".to_string(), current.clone())] } else { snapshots.to_vec() };
    let mut merged = json!({ "items": [] });
    for (_, picture) in &pictures {
        for item in picture["items"].as_array().into_iter().flatten() {
            merged["items"].as_array_mut().unwrap().push(item.clone());
        }
    }
    let assets_json = assets_for(world, &merged, assets);
    let scenes: Vec<Value> = pictures.iter().map(|(name, picture)| json!({ "name": name, "scene": picture })).collect();
    let scene = &scenes[0]["scene"];
    let _ = scene;
    include_str!("page.html")
        .replace("__TITLE__", title)
        .replace("__INTERACTIVE__", if interactive { "true" } else { "false" })
        .replace("__ASSETS__", &assets_json.to_string())
        .replace("__SCENES__", &Value::Array(scenes).to_string())
}
