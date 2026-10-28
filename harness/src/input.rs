//! The mouse. A pointer moves, presses and turns the wheel over the frames the way the game sends it:
//! to the topmost frame that takes that kind of input at the point.

use crate::bind::fire;
use crate::runtime::Shared;
use crate::world::{Class, Id};
use mlua::{Lua, MultiValue, Value};

type Result<T> = mlua::Result<T>;

fn string_value(lua: &Lua, value: &str) -> Result<Value> {
    Ok(Value::String(lua.create_string(value)?))
}

/// What is under the pointer for motion, first.
pub fn focus(shared: &Shared) -> Option<Id> {
    let world = shared.world.borrow();
    world.hits(world.pointer.0, world.pointer.1, false, true).first().copied()
}

pub fn move_to(lua: &Lua, shared: &Shared, x: f32, y: f32) -> Result<()> {
    shared.world.borrow_mut().pointer = (x, y);
    let now = focus(shared);
    let before = shared.world.borrow().hovered;
    if now == before {
        return Ok(());
    }
    shared.world.borrow_mut().hovered = now;
    if let Some(old) = before {
        fire(lua, shared, old, "OnLeave", MultiValue::from_iter([Value::Boolean(true)]))?;
    }
    if let Some(new) = now {
        fire(lua, shared, new, "OnEnter", MultiValue::from_iter([Value::Boolean(true)]))?;
    }
    Ok(())
}

/// A button gets its click when the mouse (or a key bound to it) goes up over it, or down if it listens for
/// that, if it is enabled. Its scripts run in the game's order: PreClick, OnClick, PostClick, each given the
/// button and whether it was a press.
pub fn click_button(lua: &Lua, shared: &Shared, id: Id, button: &str, down: bool) -> Result<()> {
    let (enabled, listens) = {
        let world = shared.world.borrow();
        let obj = &world.objs[id];
        let wanted = format!("{button}{}", if down { "Down" } else { "Up" });
        let any = if down { "AnyDown" } else { "AnyUp" };
        (obj.enabled, obj.clicks.iter().any(|name| name == &wanted || name == any))
    };
    if !enabled || !listens {
        return Ok(());
    }
    for script in ["PreClick", "OnClick", "PostClick"] {
        if script == "PostClick" {
            record_secure_action(shared, id);
        }
        fire(lua, shared, id, script, MultiValue::from_iter([string_value(lua, button)?, Value::Boolean(down)]))?;
    }
    Ok(())
}

/// Presses and releases a mouse button at a point. It returns the frame that took it.
pub fn click(lua: &Lua, shared: &Shared, x: f32, y: f32, button: &str) -> Result<Option<Id>> {
    move_to(lua, shared, x, y)?;
    let target = {
        let world = shared.world.borrow();
        world.hits(x, y, false, false).first().copied()
    };
    let Some(target) = target else { return Ok(None) };
    fire(lua, shared, target, "OnMouseDown", MultiValue::from_iter([string_value(lua, button)?]))?;
    fire(lua, shared, target, "OnMouseUp", MultiValue::from_iter([string_value(lua, button)?, Value::Boolean(true)]))?;
    if shared.world.borrow().objs[target].class == Class::Button {
        click_button(lua, shared, target, button, false)?;
    }
    Ok(Some(target))
}

pub fn wheel(lua: &Lua, shared: &Shared, x: f32, y: f32, delta: f32) -> Result<Option<Id>> {
    let target = {
        let world = shared.world.borrow();
        world.hits(x, y, true, false).first().copied()
    };
    let Some(target) = target else { return Ok(None) };
    fire(lua, shared, target, "OnMouseWheel", MultiValue::from_iter([Value::Number(delta as f64)]))?;
    Ok(Some(target))
}

/// A secure button does what its attributes say between PreClick and PostClick, in the game's own code.
/// The harness writes down the type and the attributes that go with it.
fn record_secure_action(shared: &Shared, id: Id) {
    let world = shared.world.borrow();
    let obj = &world.objs[id];
    if !obj.template.as_deref().is_some_and(|template| template.contains("Secure")) {
        return;
    }
    let Some(Value::String(kind)) = obj.attributes.get("type") else { return };
    let mut parts = vec![kind.to_string_lossy().to_string()];
    for key in ["unit", "macrotext", "action", "marker", "spell", "item"] {
        match obj.attributes.get(key) {
            Some(Value::String(text)) => parts.push(format!("{key}={}", text.to_string_lossy())),
            Some(Value::Integer(number)) => parts.push(format!("{key}={number}")),
            Some(Value::Number(number)) => parts.push(format!("{key}={number}")),
            _ => {}
        }
    }
    shared.secure_log.borrow_mut().push(parts.join(" "));
}
