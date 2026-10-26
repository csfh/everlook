//! What is on the screen: every shown frame and region, in the order the game draws them, with where each
//! sits and what it is made of. The HTML page and any later picture are drawn from this.

use crate::world::{Class, Id, Rect, World};
use serde_json::{Value, json};

fn layer_rank(layer: &str) -> u8 {
    match layer {
        "BACKGROUND" => 0,
        "BORDER" => 1,
        "ARTWORK" => 2,
        "OVERLAY" => 3,
        "HIGHLIGHT" => 4,
        _ => 2,
    }
}

fn strata_rank(world: &World, id: Id) -> u8 {
    match world.objs[id].strata {
        crate::world::Strata::Background => 1,
        crate::world::Strata::Low => 2,
        crate::world::Strata::Medium => 3,
        crate::world::Strata::High => 4,
        crate::world::Strata::Dialog => 5,
        crate::world::Strata::Fullscreen => 6,
        crate::world::Strata::FullscreenDialog => 7,
        crate::world::Strata::Tooltip => 8,
    }
}

/// The part of the screen an object may draw in: the overlap of every clipping ancestor.
fn clip_of(world: &World, id: Id) -> Option<Rect> {
    let mut clip: Option<Rect> = None;
    let mut walker = world.objs[id].parent;
    while let Some(parent) = walker {
        let obj = &world.objs[parent];
        if obj.clips || obj.class == Class::ScrollFrame {
            let rect = world.rect(parent);
            clip = Some(match clip {
                None => rect,
                Some(held) => {
                    let left = held.left.max(rect.left);
                    let top = held.top.max(rect.top);
                    let right = held.right().min(rect.right());
                    let bottom = held.bottom().min(rect.bottom());
                    Rect { left, top, width: (right - left).max(0.0), height: (bottom - top).max(0.0) }
                }
            });
        }
        walker = obj.parent;
    }
    clip
}

fn rect_json(rect: Rect) -> Value {
    json!({ "x": rect.left, "y": rect.top, "w": rect.width, "h": rect.height })
}

fn item_for_region(world: &World, id: Id) -> Option<Value> {
    let obj = &world.objs[id];
    let rect = world.rect(id);
    let alpha = world.effective_alpha(id);
    if alpha <= 0.0 || !world.visible(id) {
        return None;
    }
    let clip = clip_of(world, id).map(rect_json);
    match obj.class {
        Class::Texture => {
            if obj.texture.is_mask || rect.width <= 0.0 || rect.height <= 0.0 || (obj.points.is_empty() && obj.all_points.is_none()) {
                return None;
            }
            let gradient = obj.texture.gradient.as_ref().map(|(orientation, low, high)| json!({ "orientation": orientation, "from": low, "to": high }));
            Some(json!({
                "kind": "texture", "id": id, "rect": rect_json(rect), "alpha": alpha, "clip": clip,
                "path": obj.texture.path, "atlas": obj.texture.atlas, "color": obj.texture.color, "tint": obj.texture.vertex_color,
                "texcoord": obj.texture.tex_coord, "masks": obj.texture.masks.iter().map(|mask| json!({ "path": world.objs[*mask].texture.path, "rect": rect_json(world.rect(*mask)), "rotation": world.objs[*mask].texture.rotation })).collect::<Vec<_>>(), "rotation": obj.texture.rotation, "gradient": gradient, "layer": obj.texture.layer,
            }))
        }
        Class::FontString => {
            if obj.text.text.is_empty() || (obj.points.is_empty() && obj.all_points.is_none()) {
                return None;
            }
            let (font, height) = world.font_of(id);
            let color = obj.text.color.or_else(|| obj.text.font_object.as_ref().and_then(|name| world.fonts.borrow().objects.get(name).and_then(|def| def.color))).unwrap_or([1.0; 4]);
            Some(json!({
                "kind": "text", "id": id, "rect": rect_json(rect), "alpha": alpha, "clip": clip,
                "text": World::shown_text(&obj.text.text), "font": font, "height": height, "color": color,
                "justify": obj.text.justify_h, "wrap": obj.text.wrap, "max_lines": obj.text.max_lines, "layer": obj.texture.layer,
            }))
        }
        _ => None,
    }
}

/// The draw list, back to front, and the frames' boxes for the picture's outlines.
pub fn scene(world: &World) -> Value {
    let mut frames: Vec<Id> = (0..world.objs.len()).filter(|id| world.objs[*id].class.is_frame() && world.visible(*id)).collect();
    frames.sort_by_key(|id| (strata_rank(world, *id), world.objs[*id].level, world.objs[*id].order));
    let mut items: Vec<Value> = Vec::new();
    let mut boxes: Vec<Value> = Vec::new();
    for frame in frames {
        let obj = &world.objs[frame];
        let rect = world.rect(frame);
        let alpha = world.effective_alpha(frame);
        if rect.width > 0.0 && rect.height > 0.0 && frame != 0 && obj.name.as_deref() != Some("WorldFrame") {
            boxes.push(json!({
                "id": frame, "name": obj.name, "type": obj.class.type_name(), "rect": rect_json(rect),
                "strata": obj.strata.name(), "level": obj.level, "mouse": obj.mouse_click || obj.mouse_motion, "wheel": obj.mouse_wheel,
                "clips": obj.clips || obj.class == Class::ScrollFrame, "alpha": alpha, "enabled": obj.enabled,
            }));
        }
        if alpha > 0.0 && obj.class == Class::StatusBar && rect.width > 0.0 {
            let (low, high) = obj.min_max;
            let fraction = ((obj.value.unwrap_or(0.0) - low) / (high - low).max(f32::EPSILON)).clamp(0.0, 1.0);
            items.push(json!({ "kind": "bar", "id": frame, "rect": rect_json(rect), "alpha": alpha, "fraction": fraction, "color": obj.bar_color, "clip": clip_of(world, frame).map(rect_json) }));
        }
        let mut regions: Vec<Id> = obj.regions.clone();
        regions.sort_by_key(|id| (layer_rank(&world.objs[*id].texture.layer), *id));
        for region in regions {
            if let Some(item) = item_for_region(world, region) {
                items.push(item);
            }
        }
    }
    json!({ "screen": { "w": crate::world::SCREEN_WIDTH, "h": crate::world::SCREEN_HEIGHT }, "items": items, "frames": boxes, "now": world.now })
}
