//! Animation groups on the harness clock. A group runs its animations order by order; the animations
//! that share an order run together. While one plays, what it does to its target (an alpha factor, an
//! offset) is held on the target and taken off when the group stops, as the game does.

use crate::bind::fire;
use crate::runtime::Shared;
use crate::world::{AnimKind, Class, Id};
use mlua::{Lua, MultiValue, Value};

type Result<T> = mlua::Result<T>;

fn smooth(kind: &str, progress: f32) -> f32 {
    match kind {
        "IN" => progress * progress,
        "OUT" => 1.0 - (1.0 - progress) * (1.0 - progress),
        "IN_OUT" => {
            if progress < 0.5 {
                2.0 * progress * progress
            } else {
                1.0 - 2.0 * (1.0 - progress) * (1.0 - progress)
            }
        }
        _ => progress,
    }
}

pub fn play(lua: &Lua, shared: &Shared, group: Id) -> Result<()> {
    {
        let mut world = shared.world.borrow_mut();
        if world.objs[group].anim.playing {
            return Ok(());
        }
        world.objs[group].anim.playing = true;
        world.objs[group].anim.elapsed = 0.0;
        let members = world.objs[group].anim.members.clone();
        for member in members {
            world.objs[member].anim.progress = 0.0;
            world.objs[member].anim.finished = false;
        }
    }
    fire(lua, shared, group, "OnPlay", MultiValue::new())?;
    apply(shared, group);
    Ok(())
}

fn target_of(shared: &Shared, member: Id, group: Id) -> Option<Id> {
    let world = shared.world.borrow();
    world.objs[member].anim.target.or(world.objs[group].anim.owner)
}

fn clear_effects(shared: &Shared, group: Id) {
    let members = shared.world.borrow().objs[group].anim.members.clone();
    for member in members {
        if let Some(target) = target_of(shared, member, group) {
            let mut world = shared.world.borrow_mut();
            world.objs[target].anim_alpha = None;
            world.objs[target].anim_offset = (0.0, 0.0);
        }
    }
}

pub fn stop(lua: &Lua, shared: &Shared, group: Id) -> Result<()> {
    if !shared.world.borrow().objs[group].anim.playing {
        return Ok(());
    }
    shared.world.borrow_mut().objs[group].anim.playing = false;
    clear_effects(shared, group);
    fire(lua, shared, group, "OnStop", MultiValue::new())?;
    Ok(())
}

/// Where each animation of a playing group has come to, and what that does to its target.
fn apply(shared: &Shared, group: Id) -> bool {
    let mut world = shared.world.borrow_mut();
    let elapsed = world.objs[group].anim.elapsed;
    let members = world.objs[group].anim.members.clone();
    let mut orders: Vec<i32> = members.iter().map(|member| world.objs[*member].anim.order).collect();
    orders.sort();
    orders.dedup();
    let mut start = 0.0;
    let mut done = true;
    for order in orders {
        let mut length: f64 = 0.0;
        for member in members.iter().filter(|member| world.objs[**member].anim.order == order) {
            let anim = &world.objs[*member].anim;
            length = length.max(anim.start_delay + anim.duration + anim.end_delay);
        }
        for member in members.iter().filter(|member| world.objs[**member].anim.order == order).copied().collect::<Vec<_>>() {
            let (delay, duration, smoothing) = {
                let anim = &world.objs[member].anim;
                (anim.start_delay, anim.duration, anim.smoothing.clone())
            };
            let local = elapsed - start - delay;
            let raw = if duration <= 0.0 { if local >= 0.0 { 1.0 } else { 0.0 } } else { (local / duration).clamp(0.0, 1.0) as f32 };
            let progress = smooth(&smoothing, raw);
            world.objs[member].anim.progress = progress;
            let (kind, from_alpha, to_alpha, offset, target) = {
                let obj = &world.objs[member];
                (obj.class, obj.anim.from_alpha, obj.anim.to_alpha, obj.anim.offset, obj.anim.target.or(world.objs[group].anim.owner))
            };
            if let Some(target) = target {
                match kind {
                    Class::Anim(AnimKind::Alpha) => world.objs[target].anim_alpha = Some(from_alpha + (to_alpha - from_alpha) * progress),
                    Class::Anim(AnimKind::Translation) => world.objs[target].anim_offset = (offset.0 * progress, offset.1 * progress),
                    _ => {}
                }
            }
        }
        if elapsed < start + length {
            done = false;
        }
        start += length;
    }
    done
}

/// Moves every playing group on by `dt` seconds. A group that comes to its end is finished here.
pub fn advance(lua: &Lua, shared: &Shared, dt: f64) -> Result<()> {
    let playing: Vec<Id> = {
        let world = shared.world.borrow();
        (0..world.objs.len()).filter(|id| world.objs[*id].class == Class::AnimGroup && world.objs[*id].anim.playing).collect()
    };
    for group in playing {
        shared.world.borrow_mut().objs[group].anim.elapsed += dt;
        if apply(shared, group) {
            let (to_final, final_alpha, owner) = {
                let world = shared.world.borrow();
                let last = world.objs[group].anim.members.iter().rev().find(|member| world.objs[**member].class == Class::Anim(AnimKind::Alpha)).copied();
                (world.objs[group].anim.to_final_alpha, last.map(|member| world.objs[member].anim.to_alpha), world.objs[group].anim.owner)
            };
            shared.world.borrow_mut().objs[group].anim.playing = false;
            clear_effects(shared, group);
            if to_final {
                if let (Some(alpha), Some(owner)) = (final_alpha, owner) {
                    shared.world.borrow_mut().objs[owner].alpha = alpha;
                }
            }
            fire(lua, shared, group, "OnFinished", MultiValue::from_iter([Value::Boolean(false)]))?;
        } else {
            fire(lua, shared, group, "OnUpdate", MultiValue::from_iter([Value::Number(dt)]))?;
        }
    }
    Ok(())
}
