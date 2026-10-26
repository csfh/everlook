//! What Blizzard says each widget type can do: the method names and argument types, read from
//! `api/widgets.json`. A type's methods are those of its own documentation table and of every table
//! it inherits from. A method not in that list does not exist on the type, and a script calling it gets
//! the error the game gives.

use crate::world::{AnimKind, Class};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::OnceLock;

#[derive(Clone, Debug)]
pub struct Argument {
    pub name: String,
    pub kind: String,
    pub nilable: bool,
    pub has_default: bool,
}

#[derive(Clone, Debug)]
pub struct Signature {
    pub name: String,
    pub arguments: Vec<Argument>,
}

fn tables() -> &'static HashMap<String, Vec<Signature>> {
    static TABLES: OnceLock<HashMap<String, Vec<Signature>>> = OnceLock::new();
    TABLES.get_or_init(|| {
        let raw: Value = serde_json::from_str(include_str!("../api/widgets.json")).expect("api/widgets.json is valid");
        let mut map = HashMap::new();
        for (name, table) in raw.as_object().expect("an object") {
            let list = table["functions"]
                .as_array()
                .expect("a list")
                .iter()
                .map(|function| Signature {
                    name: function["name"].as_str().unwrap_or_default().to_string(),
                    arguments: function["arguments"]
                        .as_array()
                        .map(|list| {
                            list.iter()
                                .map(|argument| Argument {
                                    name: argument["name"].as_str().unwrap_or_default().to_string(),
                                    kind: argument["type"].as_str().unwrap_or_default().to_string(),
                                    nilable: argument["nilable"].as_bool().unwrap_or(false),
                                    has_default: !argument["default"].is_null(),
                                })
                                .collect()
                        })
                        .unwrap_or_default(),
                })
                .collect();
            map.insert(name.clone(), list);
        }
        map
    })
}

/// The documentation tables a class draws its methods from, nearest first.
pub fn chain(class: Class) -> Vec<&'static str> {
    let region = ["SimpleRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleScriptRegionAPI", "SimpleObjectAPI", "SimpleFrameScriptObjectAPI"];
    let frame = ["SimpleFrameAPI", "SimpleAnimatableObjectAPI", "SimpleFrameScriptObjectAPI"];
    let mut list: Vec<&'static str> = Vec::new();
    match class {
        Class::Frame => {}
        Class::Button => list.push("SimpleButtonAPI"),
        Class::ScrollFrame => list.push("SimpleScrollFrameAPI"),
        Class::StatusBar => list.push("SimpleStatusBarAPI"),
        Class::Cooldown => list.push("FrameAPICooldown"),
        Class::Tooltip => list.push("FrameAPITooltip"),
        Class::Texture => {
            list.extend(["SimpleTextureAPI", "SimpleTextureBaseAPI", "SimpleAnimatableObjectAPI"]);
            list.extend(region);
            return list;
        }
        Class::FontString => {
            list.extend(["SimpleFontStringAPI", "SimpleFontAPI", "SimpleAnimatableObjectAPI"]);
            list.extend(region);
            return list;
        }
        Class::AnimGroup => return vec!["SimpleAnimGroupAPI", "SimpleObjectAPI", "SimpleFrameScriptObjectAPI"],
        Class::Anim(kind) => {
            list.push(match kind {
                AnimKind::Alpha => "SimpleAnimAlphaAPI",
                AnimKind::Translation => "SimpleAnimTranslationAPI",
                AnimKind::Scale => "SimpleAnimScaleAPI",
                AnimKind::Rotation => "SimpleAnimRotationAPI",
            });
            list.extend(["SimpleAnimAPI", "SimpleObjectAPI", "SimpleFrameScriptObjectAPI"]);
            return list;
        }
    }
    list.extend(frame);
    list.extend(region);
    list
}

/// Every method a class has, with its signature.
pub fn methods(class: Class) -> Vec<Signature> {
    let mut seen: HashMap<String, Signature> = HashMap::new();
    let mut order: Vec<String> = Vec::new();
    for table in chain(class) {
        if let Some(list) = tables().get(table) {
            for signature in list {
                if !seen.contains_key(&signature.name) {
                    order.push(signature.name.clone());
                    seen.insert(signature.name.clone(), signature.clone());
                }
            }
        }
    }
    // A tooltip's main methods are in no Blizzard documentation. They come from the community wiki
    // (API_GameTooltip), and take no argument checks here.
    if class == Class::Tooltip {
        for name in TOOLTIP_METHODS {
            if !seen.contains_key(*name) {
                order.push(name.to_string());
                seen.insert(name.to_string(), Signature { name: name.to_string(), arguments: Vec::new() });
            }
        }
    }
    order.into_iter().filter_map(|name| seen.remove(&name)).collect()
}

const TOOLTIP_METHODS: &[&str] = &[
    "SetOwner", "GetOwner", "IsOwned", "AddLine", "AddDoubleLine", "ClearLines", "NumLines", "AppendText", "FadeOut", "GetUnit", "GetItem", "GetSpell",
    "SetUnit", "SetHyperlink", "SetSpellByID", "SetItemByID", "SetBagItem", "SetInventoryItem", "SetAnchorType", "GetAnchorType",
];
