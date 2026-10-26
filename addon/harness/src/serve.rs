//! A local page to look at the game and push on it. `GET /` is the page, `POST /input` takes a pointer
//! move, a click, a wheel turn or a step of the clock and answers with the new picture and what has the
//! mouse. One request at a time, on this machine only: the game state lives in one thread.

use crate::input;
use crate::render::{self, Assets};
use crate::runtime::Harness;
use crate::scene;
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;

fn name_of(world: &crate::world::World, id: usize) -> String {
    let obj = &world.objs[id];
    format!("{} L{} {}{}", obj.name.clone().unwrap_or_else(|| format!("{} #{id}", obj.class.type_name())), obj.level, obj.strata.name(), if obj.mouse_click { "" } else { "  (motion only)" })
}

fn answer(harness: &Harness, x: f32, y: f32) -> Value {
    let world = harness.shared.world.borrow();
    let hits = world.hits(x, y, false, false);
    let names: Vec<String> = hits.iter().map(|id| name_of(&world, *id)).collect();
    let errors: Vec<String> = world.errors.clone();
    drop(world);
    harness.shared.world.borrow_mut().errors.clear();
    let world = harness.shared.world.borrow();
    json!({ "scene": scene::scene(&world), "hits": names, "focus": hits.first(), "errors": errors })
}

pub fn serve(harness: &Harness, port: u16, title: &str) -> std::io::Result<()> {
    let listener = TcpListener::bind(("127.0.0.1", port))?;
    println!("open http://127.0.0.1:{port}/");
    let mut assets = Assets::new(&harness.shared.addons);
    for stream in listener.incoming() {
        let mut stream = stream?;
        let mut reader = BufReader::new(stream.try_clone()?);
        let mut request_line = String::new();
        reader.read_line(&mut request_line)?;
        let mut length = 0usize;
        loop {
            let mut line = String::new();
            reader.read_line(&mut line)?;
            if line.trim().is_empty() {
                break;
            }
            if let Some(value) = line.to_lowercase().strip_prefix("content-length:") {
                length = value.trim().parse().unwrap_or(0);
            }
        }
        let mut body = vec![0u8; length];
        reader.read_exact(&mut body)?;
        let (status, kind, payload) = if request_line.starts_with("GET / ") {
            let world = harness.shared.world.borrow();
            ("200 OK", "text/html; charset=utf-8", render::page(&world, &[], &mut assets, true, title))
        } else if request_line.starts_with("POST /input") {
            let message: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
            let (x, y) = (message["x"].as_f64().unwrap_or(-1.0) as f32, message["y"].as_f64().unwrap_or(-1.0) as f32);
            let result = match message["type"].as_str() {
                Some("move") => input::move_to(&harness.lua, &harness.shared, x, y),
                Some("click") => input::click(&harness.lua, &harness.shared, x, y, message["button"].as_str().unwrap_or("LeftButton")).map(|_| ()),
                Some("wheel") => input::wheel(&harness.lua, &harness.shared, x, y, message["delta"].as_f64().unwrap_or(0.0) as f32).map(|_| ()),
                Some("advance") => crate::runtime::advance(&harness.lua, &harness.shared, message["seconds"].as_f64().unwrap_or(0.1)),
                _ => Ok(()),
            };
            if let Err(error) = result {
                harness.shared.world.borrow_mut().errors.push(error.to_string());
            }
            let pointer = harness.shared.world.borrow().pointer;
            ("200 OK", "application/json", answer(harness, pointer.0, pointer.1).to_string())
        } else {
            ("404 Not Found", "text/plain", "not found".to_string())
        };
        write!(stream, "HTTP/1.1 {status}\r\nContent-Type: {kind}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n", payload.len())?;
        stream.write_all(payload.as_bytes())?;
    }
    Ok(())
}
