//! Fonts as the game has them: named font objects with a file, a height and a colour (generated from
//! Blizzard's own font XML into `api/fonts.json`), and text measured by the glyphs of the real font files.
//!
//! Blizzard's own typefaces are not in this repository, so a font file that cannot be found is measured
//! with Expressway, which the addon ships. That is a stand-in, and `FontBook::stand_ins` lists each use.
//! A line is as tall as its font is high (engine fact 13).

use serde_json::Value;
use std::collections::HashMap;
use std::path::PathBuf;
use std::rc::Rc;

#[derive(Clone, Debug)]
pub struct FontDef {
    pub path: String,
    pub height: f32,
    pub flags: String,
    pub color: Option<[f32; 4]>,
    pub justify_h: Option<String>,
}

pub struct FontBook {
    pub objects: HashMap<String, FontDef>,
    addons: PathBuf,
    files: HashMap<String, Option<Rc<Vec<u8>>>>,
    /// Font files that were asked for and not found, which a stand-in measured.
    pub stand_ins: Vec<String>,
}

impl FontBook {
    pub fn new(addons: PathBuf) -> FontBook {
        let raw: Value = serde_json::from_str(include_str!("../api/fonts.json")).expect("api/fonts.json is valid");
        let mut objects = HashMap::new();
        for (name, font) in raw.as_object().expect("an object") {
            objects.insert(
                name.clone(),
                FontDef {
                    path: font["font"].as_str().unwrap_or_default().to_string(),
                    height: font["height"].as_f64().unwrap_or(12.0) as f32,
                    flags: font["outline"].as_str().unwrap_or_default().to_string(),
                    color: font["color"].as_array().map(|list| {
                        let channel = |index: usize| list.get(index).and_then(Value::as_f64).unwrap_or(1.0) as f32;
                        [channel(0), channel(1), channel(2), channel(3)]
                    }),
                    justify_h: font["justify_h"].as_str().map(str::to_string),
                },
            );
        }
        FontBook { objects, addons, files: HashMap::new(), stand_ins: Vec::new() }
    }

    fn file_for(&mut self, path: &str) -> Option<Rc<Vec<u8>>> {
        let key = path.to_lowercase().replace('\\', "/");
        if let Some(found) = self.files.get(&key) {
            return found.clone();
        }
        let direct = key.strip_prefix("interface/addons/").map(|_| self.addons.join(rest_in_original_case(path)));
        let loaded = direct.and_then(|file| std::fs::read(file).ok()).map(Rc::new);
        let loaded = loaded.or_else(|| {
            // Blizzard's typefaces are not here. Expressway stands in, and the use is kept.
            self.stand_ins.push(path.to_string());
            std::fs::read(self.addons.join("Everlook_Fonts/assets/expressway.ttf")).ok().map(Rc::new)
        });
        self.files.insert(key, loaded.clone());
        loaded
    }

    /// The width of one line of text in a font at a height, in screen units.
    pub fn line_width(&mut self, path: &str, height: f32, text: &str) -> f32 {
        let Some(data) = self.file_for(path) else { return text.chars().count() as f32 * height * 0.5 };
        let Ok(face) = ttf_parser::Face::parse(&data, 0) else { return text.chars().count() as f32 * height * 0.5 };
        let scale = height / face.units_per_em() as f32;
        text.chars()
            .map(|character| {
                face.glyph_index(character).and_then(|glyph| face.glyph_hor_advance(glyph)).map(|advance| advance as f32 * scale).unwrap_or(height * 0.5)
            })
            .sum()
    }

    /// How many lines text takes in a width, breaking at spaces and, for a word wider than the width, anywhere.
    pub fn wrapped_lines(&mut self, path: &str, height: f32, text: &str, width: f32) -> usize {
        let mut lines = 0;
        for paragraph in text.split('\n') {
            let mut used = 0.0f32;
            let mut paragraph_lines = 1;
            let space = self.line_width(path, height, " ");
            for word in paragraph.split(' ') {
                let size = self.line_width(path, height, word);
                if used > 0.0 && used + space + size > width {
                    paragraph_lines += 1;
                    used = size;
                } else {
                    used += if used > 0.0 { space + size } else { size };
                }
                while used > width && width > 0.0 {
                    // A word wider than the line is broken across lines.
                    paragraph_lines += 1;
                    used -= width;
                }
            }
            lines += paragraph_lines;
        }
        lines
    }
}

fn rest_in_original_case(path: &str) -> String {
    let normal = path.replace('\\', "/");
    match normal.to_lowercase().find("interface/addons/") {
        Some(index) => normal[index + "interface/addons/".len()..].to_string(),
        None => normal,
    }
}

impl FontBook {
    /// The bytes of the file a font path names, or the stand-in, for a page to embed.
    pub fn file_bytes(&mut self, path: &str) -> Option<Rc<Vec<u8>>> {
        self.file_for(path)
    }
}
