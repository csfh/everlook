//! Builds a map picture from a map layout (what the addon records: the base tiles and the explored pieces, as file
//! ids with sizes and places), reading every tile from the game's own storage.

use crate::blp;
use crate::casc::Casc;
use image::{imageops, RgbaImage};
use serde::Deserialize;

#[derive(Deserialize)]
pub struct Layout {
    #[serde(rename = "layerWidth")]
    pub layer_width: u32,
    #[serde(rename = "layerHeight")]
    pub layer_height: u32,
    #[serde(rename = "tileWidth")]
    pub tile_width: u32,
    #[serde(rename = "tileHeight")]
    pub tile_height: u32,
    pub tiles: Vec<u32>,
    #[serde(default)]
    pub overlays: Vec<Overlay>,
}

/// An explored piece: where it sits on the layer, how large it is and its tiles, row by row.
#[derive(Deserialize)]
pub struct Overlay {
    #[serde(rename = "offsetX")]
    pub offset_x: i64,
    #[serde(rename = "offsetY")]
    pub offset_y: i64,
    pub width: u32,
    pub height: u32,
    pub files: Vec<u32>,
}

fn draw_tiles(canvas: &mut RgbaImage, casc: &Casc, ids: &[u32], left: i64, top: i64, width: u32, height: u32, tile_w: u32, tile_h: u32) -> Result<(), String> {
    let columns = width.div_ceil(tile_w) as usize;
    let rows = height.div_ceil(tile_h) as usize;
    if ids.len() != columns * rows {
        return Err(format!("{} tiles do not fill a {columns} by {rows} grid", ids.len()));
    }
    for (i, id) in ids.iter().enumerate() {
        if *id == 0 {
            continue;
        }
        let tile = blp::decode(&casc.read_id(*id)?).map_err(|e| format!("file {id}: {e}"))?;
        let (x, y) = (left + (i % columns) as i64 * tile_w as i64, top + (i / columns) as i64 * tile_h as i64);
        imageops::overlay(canvas, &tile, x, y);
    }
    Ok(())
}

pub fn stitch(casc: &Casc, layout: &Layout) -> Result<RgbaImage, String> {
    let columns = layout.layer_width.div_ceil(layout.tile_width);
    let rows = layout.layer_height.div_ceil(layout.tile_height);
    let mut canvas = RgbaImage::new(columns * layout.tile_width, rows * layout.tile_height);
    draw_tiles(&mut canvas, casc, &layout.tiles, 0, 0, layout.layer_width, layout.layer_height, layout.tile_width, layout.tile_height)?;
    for overlay in &layout.overlays {
        draw_tiles(&mut canvas, casc, &overlay.files, overlay.offset_x, overlay.offset_y, overlay.width, overlay.height, layout.tile_width, layout.tile_height)?;
    }
    // The whole tile grid, the size the site's pins are placed on, with what lies outside the painting left black.
    for pixel in canvas.pixels_mut() {
        if pixel.0[3] == 0 {
            *pixel = image::Rgba([0, 0, 0, 255]);
        }
    }
    Ok(canvas)
}

/// The painted map of a zone as the game keeps it in its own files: `Interface\WorldMap\<Folder>\<Folder>N.blp`,
/// numbered row by row. Finds the folder from the zone's name, and returns the whole tile grid.
pub fn world_map(casc: &Casc, name: &str, folder_hint: Option<&str>) -> Result<(String, RgbaImage), String> {
    // The folder is the zone's name run together, often without a leading "The"/"Mount" or a trailing word such as
    // "Forest"; Azshara's is spelled the way the game spells it.
    let squash = |text: &str| -> String { text.chars().filter(|c| c.is_alphanumeric()).collect() };
    let words: Vec<&str> = name.split_whitespace().collect();
    let mut folders: Vec<String> = folder_hint.map(str::to_string).into_iter().collect();
    folders.push(squash(name));
    if words.len() > 1 {
        folders.push(squash(&words[1..].join(" ")));
        folders.push(squash(&words[..words.len() - 1].join(" ")));
    }
    if name == "Azshara" {
        folders.push("Aszhara".to_string());
    }
    for folder in folders {
        let ids: Vec<u32> = (1..=12).map(|n| casc.id_of(&format!("Interface\\WorldMap\\{folder}\\{folder}{n}.blp")).unwrap_or(0)).collect();
        if ids.iter().any(|id| *id == 0) {
            continue;
        }
        let mut canvas = RgbaImage::new(1024, 768);
        draw_tiles(&mut canvas, casc, &ids, 0, 0, 1024, 768, 256, 256)?;
        // The grid is taller than the painting; the rest is black, as the game shows it.
        for pixel in canvas.pixels_mut() {
            if pixel.0[3] == 0 {
                *pixel = image::Rgba([0, 0, 0, 255]);
            }
        }
        return Ok((folder, canvas));
    }
    Err(format!("no map folder for {name}"))
}
