//! Map layouts read from the game's own tables: for each map region, its art's tiles, its layer's size and its explored
//! pieces, in the shape `stitch` takes. Each table is named by its file id and pinned by its layout hash: a build that
//! changes a table's columns changes the hash, and the reader stops instead of reading the wrong column. The columns
//! are the ones `docs/game-data-facts.md` row 23 names.

use std::collections::HashMap;

use serde_json::{Value, json};

use crate::casc::{Casc, Error};
use crate::db2::Table;

/// (file id, layout hash) of a table, and what it is.
const REGIONS: (u32, u32) = (1957206, 0xdb51d55f); // name; the row's parent is the parent region
const ART_OF: (u32, u32) = (1957217, 0xeae7da2a); // parent = region id; column 1 = art id
const ARTS: (u32, u32) = (1957202, 0x3ae7d144); // id = art id; column 2 = layer style
const LAYERS: (u32, u32) = (1957208, 0x3f597f5a); // parent = style; layer index, width, height, tile width, tile height, scales, zoom steps
const TILES: (u32, u32) = (1957210, 0x2da5b77b); // parent = art id; row, column, layer, file
const OVERLAYS: (u32, u32) = (1134579, 0x9a196494); // id; art id, width, height, offset x, offset y
const OVERLAY_TILES: (u32, u32) = (1957212, 0x2c843422); // parent = overlay id; row, column, layer, file

pub(crate) fn open(casc: &Casc, (file, hash): (u32, u32), what: &str) -> Result<Table, Error> {
    let (bytes, skipped) = casc.read_id_lenient(file).map_err(|e| format!("{what} (file {file}): {e}"))?;
    let table = Table::parse(&bytes, &skipped).map_err(|e| format!("{what} (file {file}): {e}"))?;
    if table.layout_hash != hash {
        return Err(format!("{what} (file {file}) has layout hash {:08x}, not {hash:08x}: its columns changed, so re-derive this reader (docs/game-data-facts.md row 23)", table.layout_hash));
    }
    Ok(table)
}

/// Tiles in row-major order for a grid of `columns` by `rows`; a place with no tile is 0.
fn grid(mut tiles: Vec<(u64, u64, u32)>, columns: usize, rows: usize) -> Vec<u32> {
    let mut out = vec![0u32; columns * rows];
    tiles.sort_unstable();
    for (row, column, file) in tiles {
        if (row as usize) < rows && (column as usize) < columns {
            out[row as usize * columns + column as usize] = file;
        }
    }
    out
}

/// A scale as the number it was written as: the tables hold 32-bit floats, and widening 2.14 would give 2.1400001.
fn thousandths(scale: f32) -> f64 {
    (scale as f64 * 1000.0).round() / 1000.0
}

/// Whether an explored piece draws anything: the table holds placeholder rows with no size and no tiles.
fn draws(width: u64, height: u64, files: &[u32]) -> bool {
    width > 0 && height > 0 && files.iter().any(|file| *file != 0)
}

/// A layer: (width, height, tile width, tile height, min scale, max scale, zoom steps).
type Layer = [u64; 7];

/// The layer style an art is drawn with. The art table names one for some arts (54 of its 55 rows say style 1); an art
/// without a row is not named anywhere this reader has found, so the style is the layer with the smallest grid that
/// holds the art's tiles. Both rules agree with every one of the 57 maps players' addons uploaded (all style 1: 12 tiles
/// of 256), and the single 512 by 512 tile of the three regions no one uploaded fits the 512 by 512 layer.
fn pick_style(listed: Option<u64>, last_row: u64, last_column: u64, layers: &HashMap<u64, Layer>) -> Option<u64> {
    let grid = |layer: &Layer| (layer[0].div_ceil(layer[2]), layer[1].div_ceil(layer[3]));
    let holds = |style: u64| layers.get(&style).is_some_and(|layer| grid(layer).0 > last_column && grid(layer).1 > last_row);
    listed.filter(|style| holds(*style)).or_else(|| layers.keys().copied().filter(|style| holds(*style)).min_by_key(|style| (grid(&layers[style]).0 * grid(&layers[style]).1, *style)))
}

/// One layout per map region that has art, as (region id, JSON).
pub fn layouts(casc: &Casc) -> Result<Vec<(u32, Value)>, Error> {
    let regions = open(casc, REGIONS, "the map regions")?;
    let art_of = open(casc, ART_OF, "the link from a region to its art")?;
    let arts = open(casc, ARTS, "the arts")?;
    let layers = open(casc, LAYERS, "the art layers")?;
    let tiles = open(casc, TILES, "the art tiles")?;
    let overlays = open(casc, OVERLAYS, "the explored pieces")?;
    let overlay_tiles = open(casc, OVERLAY_TILES, "the explored pieces' tiles")?;

    let style_of: HashMap<u32, u64> = arts.rows().map(|row| (row.id, row.number(2))).collect();
    // Layer 0 of each style: (width, height, tile width, tile height, min scale, max scale, zoom steps).
    let mut layer_of: HashMap<u64, Layer> = HashMap::new();
    for row in layers.rows() {
        if row.number(0) == 0 {
            if let Some(style) = row.parent() {
                layer_of.insert(style as u64, [row.number(1), row.number(2), row.number(3), row.number(4), row.number(5), row.number(6), row.number(7)]);
            }
        }
    }
    let mut tiles_of: HashMap<u32, Vec<(u64, u64, u32)>> = HashMap::new();
    for row in tiles.rows() {
        if let (Some(art), 0) = (row.parent(), row.number(2)) {
            tiles_of.entry(art).or_default().push((row.number(0), row.number(1), row.number(3) as u32));
        }
    }
    let mut overlay_tiles_of: HashMap<u32, Vec<(u64, u64, u32)>> = HashMap::new();
    for row in overlay_tiles.rows() {
        if let (Some(overlay), 0) = (row.parent(), row.number(2)) {
            overlay_tiles_of.entry(overlay).or_default().push((row.number(0), row.number(1), row.number(3) as u32));
        }
    }
    let mut overlays_of: HashMap<u32, Vec<(u32, [u64; 4])>> = HashMap::new();
    for row in overlays.rows() {
        overlays_of.entry(row.number(1) as u32).or_default().push((row.id, [row.number(2), row.number(3), row.number(4), row.number(5)]));
    }
    let names: HashMap<u32, String> = regions.rows().map(|row| (row.id, row.string(0).unwrap_or_default())).collect();

    let mut out = Vec::new();
    for row in art_of.rows() {
        let (Some(region), art) = (row.parent(), row.number(1) as u32) else { continue };
        let Some(base) = tiles_of.get(&art) else { continue };
        let (last_row, last_column) = (base.iter().map(|t| t.0).max().unwrap_or(0), base.iter().map(|t| t.1).max().unwrap_or(0));
        let Some(style) = pick_style(style_of.get(&art).copied(), last_row, last_column, &layer_of) else { continue };
        let Some(&[width, height, tile_w, tile_h, min_scale, max_scale, zoom]) = layer_of.get(&style) else { continue };
        let (columns, rows) = (width.div_ceil(tile_w) as usize, height.div_ceil(tile_h) as usize);
        let mut pieces = overlays_of.get(&art).cloned().unwrap_or_default();
        pieces.sort_unstable_by_key(|(id, _)| *id);
        let pieces: Vec<Value> = pieces
            .into_iter()
            .filter_map(|(id, [w, h, x, y])| {
                let files = grid(overlay_tiles_of.get(&id).cloned().unwrap_or_default(), w.div_ceil(tile_w) as usize, h.div_ceil(tile_h) as usize);
                draws(w, h, &files).then(|| json!({ "id": id, "offsetX": x, "offsetY": y, "width": w, "height": h, "files": files }))
            })
            .collect();
        out.push((
            region,
            json!({
                "build": casc.build, "uiMapId": region, "name": names.get(&region), "artId": art, "style": style,
                "layerWidth": width, "layerHeight": height, "tileWidth": tile_w, "tileHeight": tile_h,
                "minScale": thousandths(f32::from_bits(min_scale as u32)), "maxScale": thousandths(f32::from_bits(max_scale as u32)), "zoomSteps": zoom,
                "tiles": grid(base.clone(), columns, rows), "overlays": pieces,
            }),
        ));
    }
    out.sort_by_key(|(region, _)| *region);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_grid_is_row_major_and_leaves_gaps_as_zero() {
        let tiles = vec![(1, 0, 30), (0, 1, 20), (0, 0, 10)];
        assert_eq!(grid(tiles, 2, 2), vec![10, 20, 30, 0]);
    }

    #[test]
    fn a_style_is_the_listed_one_when_it_holds_the_tiles_else_the_smallest_that_does() {
        let layers = HashMap::from([(1, [1002, 668, 256, 256, 0, 0, 0]), (4, [512, 512, 512, 512, 0, 0, 0]), (5, [3840, 2560, 256, 256, 0, 0, 0])]);
        assert_eq!(pick_style(Some(1), 2, 3, &layers), Some(1));
        assert_eq!(pick_style(None, 2, 3, &layers), Some(1));
        assert_eq!(pick_style(None, 0, 0, &layers), Some(4));
        assert_eq!(pick_style(Some(1), 9, 14, &layers), Some(5));
        assert_eq!(pick_style(None, 99, 99, &layers), None);
    }

    #[test]
    fn a_scale_keeps_the_digits_it_was_written_with() {
        assert_eq!(thousandths(2.14), 2.14);
        assert_eq!(thousandths(1.0), 1.0);
    }

    #[test]
    fn a_placeholder_piece_with_no_size_or_no_tiles_draws_nothing() {
        assert!(draws(256, 256, &[0, 5]));
        assert!(!draws(0, 0, &[]));
        assert!(!draws(256, 256, &[0, 0]));
        assert!(!draws(0, 256, &[7]));
    }

    #[test]
    fn a_tile_outside_the_grid_is_left_out() {
        assert_eq!(grid(vec![(0, 0, 1), (5, 5, 2)], 1, 1), vec![1]);
    }
}
