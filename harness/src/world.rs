//! The frames, regions and animations of one running game, and the rules that act on them: where an
//! anchor puts a frame, what is under a point, how far an animation has come. Nothing here calls Lua,
//! so a script can run while the world is borrowed by no one.

use crate::fonts::FontBook;
use mlua::{Function, Table};
use std::collections::{HashMap, HashSet};

pub type Id = usize;

pub const SCREEN_WIDTH: f32 = 1920.0;
pub const SCREEN_HEIGHT: f32 = 1080.0;

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Class {
    Frame,
    Button,
    ScrollFrame,
    StatusBar,
    Cooldown,
    Tooltip,
    Texture,
    FontString,
    AnimGroup,
    Anim(AnimKind),
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum AnimKind {
    Alpha,
    Translation,
    Scale,
    Rotation,
}

impl Class {
    pub fn is_frame(self) -> bool {
        matches!(self, Class::Frame | Class::Button | Class::ScrollFrame | Class::StatusBar | Class::Cooldown | Class::Tooltip)
    }
    pub fn is_region(self) -> bool {
        matches!(self, Class::Texture | Class::FontString)
    }
    pub fn type_name(self) -> &'static str {
        match self {
            Class::Frame => "Frame",
            Class::Button => "Button",
            Class::ScrollFrame => "ScrollFrame",
            Class::StatusBar => "StatusBar",
            Class::Cooldown => "Cooldown",
            Class::Tooltip => "GameTooltip",
            Class::Texture => "Texture",
            Class::FontString => "FontString",
            Class::AnimGroup => "AnimationGroup",
            Class::Anim(AnimKind::Alpha) => "Alpha",
            Class::Anim(AnimKind::Translation) => "Translation",
            Class::Anim(AnimKind::Scale) => "Scale",
            Class::Anim(AnimKind::Rotation) => "Rotation",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Point {
    TopLeft,
    Top,
    TopRight,
    Left,
    Center,
    Right,
    BottomLeft,
    Bottom,
    BottomRight,
}

impl Point {
    pub fn parse(text: &str) -> Option<Point> {
        Some(match text {
            "TOPLEFT" => Point::TopLeft,
            "TOP" => Point::Top,
            "TOPRIGHT" => Point::TopRight,
            "LEFT" => Point::Left,
            "CENTER" => Point::Center,
            "RIGHT" => Point::Right,
            "BOTTOMLEFT" => Point::BottomLeft,
            "BOTTOM" => Point::Bottom,
            "BOTTOMRIGHT" => Point::BottomRight,
            _ => return None,
        })
    }
    pub fn name(self) -> &'static str {
        match self {
            Point::TopLeft => "TOPLEFT",
            Point::Top => "TOP",
            Point::TopRight => "TOPRIGHT",
            Point::Left => "LEFT",
            Point::Center => "CENTER",
            Point::Right => "RIGHT",
            Point::BottomLeft => "BOTTOMLEFT",
            Point::Bottom => "BOTTOM",
            Point::BottomRight => "BOTTOMRIGHT",
        }
    }
    /// How far along the width, 0 for the left edge and 1 for the right.
    pub fn across(self) -> f32 {
        match self {
            Point::TopLeft | Point::Left | Point::BottomLeft => 0.0,
            Point::TopRight | Point::Right | Point::BottomRight => 1.0,
            _ => 0.5,
        }
    }
    /// How far down the height, 0 for the top edge and 1 for the bottom.
    pub fn down(self) -> f32 {
        match self {
            Point::TopLeft | Point::Top | Point::TopRight => 0.0,
            Point::BottomLeft | Point::Bottom | Point::BottomRight => 1.0,
            _ => 0.5,
        }
    }
    fn has_left(self) -> bool {
        self.across() == 0.0
    }
    fn has_right(self) -> bool {
        self.across() == 1.0
    }
    fn has_top(self) -> bool {
        self.down() == 0.0
    }
    fn has_bottom(self) -> bool {
        self.down() == 1.0
    }
}

#[derive(Clone, Debug)]
pub struct Anchor {
    pub point: Point,
    /// None means the parent.
    pub relative: Option<Id>,
    pub relative_point: Point,
    pub x: f32,
    pub y: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct Rect {
    pub left: f32,
    pub top: f32,
    pub width: f32,
    pub height: f32,
}

impl Rect {
    pub fn right(&self) -> f32 {
        self.left + self.width
    }
    pub fn bottom(&self) -> f32 {
        self.top + self.height
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Strata {
    Background,
    Low,
    Medium,
    High,
    Dialog,
    Fullscreen,
    FullscreenDialog,
    Tooltip,
}

impl Strata {
    pub fn parse(text: &str) -> Option<Strata> {
        Some(match text {
            "BACKGROUND" => Strata::Background,
            "LOW" => Strata::Low,
            "MEDIUM" => Strata::Medium,
            "HIGH" => Strata::High,
            "DIALOG" => Strata::Dialog,
            "FULLSCREEN" => Strata::Fullscreen,
            "FULLSCREEN_DIALOG" => Strata::FullscreenDialog,
            "TOOLTIP" => Strata::Tooltip,
            _ => return None,
        })
    }
    pub fn name(self) -> &'static str {
        match self {
            Strata::Background => "BACKGROUND",
            Strata::Low => "LOW",
            Strata::Medium => "MEDIUM",
            Strata::High => "HIGH",
            Strata::Dialog => "DIALOG",
            Strata::Fullscreen => "FULLSCREEN",
            Strata::FullscreenDialog => "FULLSCREEN_DIALOG",
            Strata::Tooltip => "TOOLTIP",
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct TextureState {
    pub path: Option<String>,
    pub atlas: Option<String>,
    pub color: Option<[f32; 4]>,
    pub vertex_color: Option<[f32; 4]>,
    pub rotation: f32,
    pub tex_coord: Option<Vec<f32>>,
    pub gradient: Option<(String, [f32; 4], [f32; 4])>,
    pub blend: Option<String>,
    pub layer: String,
    /// A mask texture is not drawn; it cuts the textures it is added to.
    pub is_mask: bool,
    pub masks: Vec<Id>,
}

#[derive(Clone, Debug)]
pub struct TextState {
    pub text: String,
    pub font: Option<String>,
    pub font_height: Option<f32>,
    pub font_flags: String,
    pub font_object: Option<String>,
    pub justify_h: String,
    pub color: Option<[f32; 4]>,
    pub wrap: bool,
    pub max_lines: u32,
    pub spacing: f32,
}

impl Default for TextState {
    fn default() -> Self {
        TextState { text: String::new(), font: None, font_height: None, font_flags: String::new(), font_object: None, justify_h: "CENTER".into(), color: None, wrap: true, max_lines: 0, spacing: 0.0 }
    }
}

/// One line of a tooltip: its left text, an optional right text, and their colours.
#[derive(Clone, Debug)]
pub struct TipLine {
    pub left: String,
    pub right: Option<String>,
    pub left_color: Option<[f32; 4]>,
    pub right_color: Option<[f32; 4]>,
    pub wrap: bool,
}

pub struct Hook {
    pub function: Function,
}

pub struct Obj {
    pub class: Class,
    pub name: Option<String>,
    pub table: Table,
    pub parent: Option<Id>,
    pub children: Vec<Id>,
    pub regions: Vec<Id>,
    pub groups: Vec<Id>,
    pub template: Option<String>,
    pub shown: bool,
    pub alpha: f32,
    pub scale: f32,
    pub width: Option<f32>,
    pub height: Option<f32>,
    pub points: Vec<Anchor>,
    pub all_points: Option<Option<Id>>,
    // frames
    pub strata: Strata,
    pub level: i32,
    pub order: usize,
    pub mouse_click: bool,
    pub mouse_motion: bool,
    pub mouse_wheel: bool,
    pub insets: [f32; 4],
    pub clips: bool,
    pub enabled: bool,
    pub highlight_locked: bool,
    pub scripts: HashMap<String, Function>,
    pub hooks: HashMap<String, Vec<Function>>,
    pub events: HashSet<String>,
    pub attributes: HashMap<String, mlua::Value>,
    pub clicks: Vec<String>,
    pub scroll_child: Option<Id>,
    pub scroll: (f32, f32),
    pub value: Option<f32>,
    pub min_max: (f32, f32),
    pub bar_color: Option<[f32; 4]>,
    pub bar_texture: Option<String>,
    pub cooldown: Option<(f64, f64)>,
    pub id_number: i64,
    // tooltips
    pub tip: Vec<TipLine>,
    pub tip_owner: Option<Id>,
    pub tip_anchor: String,
    // regions
    pub texture: TextureState,
    pub text: TextState,
    // animation groups and animations
    pub anim: AnimState,
    /// What an animation playing on this object does to it right now.
    pub anim_alpha: Option<f32>,
    pub anim_offset: (f32, f32),
}

#[derive(Clone, Debug, Default)]
pub struct AnimState {
    // groups
    pub owner: Option<Id>,
    pub members: Vec<Id>,
    pub playing: bool,
    pub paused: bool,
    pub elapsed: f64,
    pub to_final_alpha: bool,
    pub looping: String,
    // animations
    pub duration: f64,
    pub start_delay: f64,
    pub end_delay: f64,
    pub order: i32,
    pub smoothing: String,
    pub from_alpha: f32,
    pub to_alpha: f32,
    pub offset: (f32, f32),
    pub scale_from: (f32, f32),
    pub scale_to: (f32, f32),
    pub degrees: f32,
    pub target: Option<Id>,
    pub progress: f32,
    pub finished: bool,
}

pub struct Timer {
    pub handle: usize,
    pub due: f64,
    pub callback: Function,
    pub interval: Option<f64>,
    pub remaining: Option<u32>,
    pub cancelled: bool,
}

/// Rules of the game's mouse handling that are not yet known. Each starts off, as the harness first assumed,
/// and a scenario turns one on to see what it would do. When the client confirms one, it becomes the default.
#[derive(Clone, Copy, Debug)]
pub struct Rules {
    /// A clipping frame that has its own mouse off hides every frame under it from the mouse.
    pub clip_needs_mouse: bool,
    /// A frame inside a scroll frame's scroll child must be inside that scroll child's rectangle to be hit.
    pub scroll_child_limits: bool,
    /// Confirmed in the client, so on unless a scenario turns it off. A clipping frame's whole subtree is ordered as one unit, at the clipping frame's strata and level. Inside it
    /// the frames are ordered by their own levels. Against a frame outside it at the same level, an ancestor of the
    /// unit wins the tie.
    pub flatten_clips: bool,
}

impl Default for Rules {
    fn default() -> Rules {
        // flatten_clips was read in the client (see docs/engine-facts.md, row 19). The others are guesses and off.
        Rules { clip_needs_mouse: false, scroll_child_limits: false, flatten_clips: true }
    }
}

pub struct World {
    pub rules: Rules,
    pub objs: Vec<Obj>,
    pub now: f64,
    pub timers: Vec<Timer>,
    pub next_timer: usize,
    pub globals_named: HashMap<String, Id>,
    pub pointer: (f32, f32),
    pub hovered: Option<Id>,
    pub errors: Vec<String>,
    pub order: usize,
    pub fonts: std::cell::RefCell<FontBook>,
}

impl World {
    pub fn new(addons: std::path::PathBuf) -> World {
        World {
            rules: Rules::default(),
            objs: Vec::new(),
            now: 1000.0,
            timers: Vec::new(),
            next_timer: 1,
            globals_named: HashMap::new(),
            pointer: (-1.0, -1.0),
            hovered: None,
            errors: Vec::new(),
            order: 0,
            fonts: std::cell::RefCell::new(FontBook::new(addons)),
        }
    }

    pub fn add(&mut self, class: Class, table: Table, name: Option<String>, parent: Option<Id>) -> Id {
        let id = self.objs.len();
        self.order += 1;
        // A new frame starts in its parent's strata, one level above it. Engine fact 1.
        let (strata, level) = match parent.and_then(|parent| self.objs.get(parent)) {
            Some(parent) => (parent.strata, parent.level + 1),
            None => (Strata::Medium, 1),
        };
        let mut obj = Obj {
            class,
            name,
            table,
            parent,
            children: Vec::new(),
            regions: Vec::new(),
            groups: Vec::new(),
            template: None,
            shown: true,
            alpha: 1.0,
            scale: 1.0,
            width: None,
            height: None,
            points: Vec::new(),
            all_points: None,
            strata,
            level,
            order: self.order,
            mouse_click: false,
            mouse_motion: false,
            mouse_wheel: false,
            insets: [0.0; 4],
            clips: false,
            enabled: true,
            highlight_locked: false,
            scripts: HashMap::new(),
            hooks: HashMap::new(),
            events: HashSet::new(),
            attributes: HashMap::new(),
            clicks: vec!["LeftButtonUp".into()],
            scroll_child: None,
            scroll: (0.0, 0.0),
            value: None,
            min_max: (0.0, 1.0),
            bar_color: None,
            bar_texture: None,
            cooldown: None,
            id_number: 0,
            tip: Vec::new(),
            tip_owner: None,
            tip_anchor: String::new(),
            texture: TextureState::default(),
            text: TextState::default(),
            anim: AnimState::default(),
            anim_alpha: None,
            anim_offset: (0.0, 0.0),
        };
        // A button takes the mouse until told not to. A plain frame does not.
        if class == Class::Button {
            obj.mouse_click = true;
            obj.mouse_motion = true;
        }
        self.objs.push(obj);
        if let Some(parent) = parent {
            if class.is_frame() {
                self.objs[parent].children.push(id);
            } else if class.is_region() {
                self.objs[parent].regions.push(id);
            }
        }
        id
    }

    pub fn set_parent(&mut self, id: Id, parent: Option<Id>) {
        if let Some(old) = self.objs[id].parent {
            self.objs[old].children.retain(|child| *child != id);
            self.objs[old].regions.retain(|child| *child != id);
        }
        self.objs[id].parent = parent;
        if let Some(parent) = parent {
            if self.objs[id].class.is_frame() {
                self.objs[parent].children.push(id);
                // Taking a new parent takes its strata and a level above it. Engine fact 1.
                let (strata, level) = (self.objs[parent].strata, self.objs[parent].level + 1);
                self.objs[id].strata = strata;
                self.objs[id].level = level;
            } else if self.objs[id].class.is_region() {
                self.objs[parent].regions.push(id);
            }
        }
    }

    /// Shown itself and under parents that are all shown.
    pub fn visible(&self, id: Id) -> bool {
        let mut walker = Some(id);
        while let Some(current) = walker {
            let obj = &self.objs[current];
            if !obj.shown {
                return false;
            }
            walker = obj.parent;
        }
        true
    }

    pub fn effective_scale(&self, id: Id) -> f32 {
        let mut scale = 1.0;
        let mut walker = Some(id);
        while let Some(current) = walker {
            let obj = &self.objs[current];
            if obj.class.is_frame() || obj.class.is_region() {
                scale *= obj.scale;
            }
            walker = obj.parent;
        }
        scale
    }

    pub fn effective_alpha(&self, id: Id) -> f32 {
        let mut alpha = 1.0;
        let mut walker = Some(id);
        while let Some(current) = walker {
            let obj = &self.objs[current];
            alpha *= obj.alpha * obj.anim_alpha.unwrap_or(1.0);
            walker = obj.parent;
        }
        alpha
    }

    fn natural_size(&self, id: Id) -> (f32, f32) {
        let obj = &self.objs[id];
        let mut width = obj.width.unwrap_or(0.0);
        let mut height = obj.height.unwrap_or(0.0);
        if obj.class == Class::FontString {
            if width == 0.0 {
                width = self.string_width(id);
            }
            if height == 0.0 {
                height = self.string_height(id, if obj.width.unwrap_or(0.0) > 0.0 { Some(obj.width.unwrap_or(0.0)) } else { None });
            }
        }
        (width, height)
    }

    pub fn shown_text(text: &str) -> String {
        // Colour codes, textures and escapes draw no text of their own. A texture escape is one glyph pair wide.
        let mut out = String::new();
        let bytes: Vec<char> = text.chars().collect();
        let mut index = 0;
        while index < bytes.len() {
            if bytes[index] == '|' && index + 1 < bytes.len() {
                match bytes[index + 1] {
                    'c' => {
                        index += 10;
                        continue;
                    }
                    'r' => {
                        index += 2;
                        continue;
                    }
                    'T' => {
                        let mut end = index + 2;
                        while end + 1 < bytes.len() && !(bytes[end] == '|' && bytes[end + 1] == 't') {
                            end += 1;
                        }
                        out.push_str("OO");
                        index = end + 2;
                        continue;
                    }
                    _ => {}
                }
            }
            out.push(bytes[index]);
            index += 1;
        }
        out
    }

    /// The file and height a string is drawn in: its own, or its font object's as it is now.
    pub fn font_of(&self, id: Id) -> (String, f32) {
        let obj = &self.objs[id];
        if let Some(path) = &obj.text.font {
            return (path.clone(), obj.text.font_height.unwrap_or(12.0));
        }
        let book = self.fonts.borrow();
        match obj.text.font_object.as_ref().and_then(|name| book.objects.get(name)) {
            Some(def) => (def.path.clone(), def.height),
            None => ("Fonts\\FRIZQT__.TTF".to_string(), 12.0),
        }
    }

    pub fn string_width(&self, id: Id) -> f32 {
        let (path, height) = self.font_of(id);
        let text = Self::shown_text(&self.objs[id].text.text);
        let mut book = self.fonts.borrow_mut();
        text.split('\n').map(|line| book.line_width(&path, height, line)).fold(0.0, f32::max)
    }

    pub fn string_height(&self, id: Id, wrap_width: Option<f32>) -> f32 {
        let obj = &self.objs[id];
        let (path, height) = self.font_of(id);
        let text = Self::shown_text(&obj.text.text);
        let mut lines = match (obj.text.wrap, wrap_width) {
            (true, Some(width)) => self.fonts.borrow_mut().wrapped_lines(&path, height, &text, width),
            _ => text.split('\n').count(),
        }
        .max(1);
        if obj.text.max_lines > 0 {
            lines = lines.min(obj.text.max_lines as usize);
        }
        lines as f32 * height + (lines as f32 - 1.0) * obj.text.spacing
    }

    fn screen() -> Rect {
        Rect { left: 0.0, top: 0.0, width: SCREEN_WIDTH, height: SCREEN_HEIGHT }
    }

    fn relative_rect(&self, id: Id, relative: Option<Id>, depth: usize) -> Rect {
        let target = relative.or(self.objs[id].parent);
        match target {
            Some(target) if target != id => self.rect_at(target, depth + 1),
            _ => Self::screen(),
        }
    }

    /// Where an object sits, in screen units with y growing downward.
    pub fn rect(&self, id: Id) -> Rect {
        self.rect_at(id, 0)
    }

    fn rect_at(&self, id: Id, depth: usize) -> Rect {
        if depth > 64 {
            return Self::screen();
        }
        let obj = &self.objs[id];
        let scale = self.effective_scale(id);
        let (natural_width, natural_height) = self.natural_size(id);
        let (offset_x, offset_y) = obj.anim_offset;
        if let Some(target) = obj.all_points {
            let mut rect = self.relative_rect(id, target, depth);
            rect.left += offset_x * scale;
            rect.top -= offset_y * scale;
            return rect;
        }
        if obj.points.is_empty() {
            // A frame with no anchors fills the screen only when it is the root. Otherwise it has no place.
            return if obj.parent.is_none() && obj.class.is_frame() && obj.width.is_none() {
                Self::screen()
            } else {
                Rect { left: 0.0, top: 0.0, width: natural_width * scale, height: natural_height * scale }
            };
        }
        let (mut left_edge, mut right_edge, mut top_edge, mut bottom_edge) = (None, None, None, None);
        let mut first: Option<(f32, f32, Point)> = None;
        for anchor in &obj.points {
            let box_ = self.relative_rect(id, anchor.relative, depth);
            let x = box_.left + anchor.relative_point.across() * box_.width + anchor.x * scale;
            let y = box_.top + anchor.relative_point.down() * box_.height - anchor.y * scale;
            if anchor.point.has_left() {
                left_edge = left_edge.or(Some(x));
            }
            if anchor.point.has_right() {
                right_edge = right_edge.or(Some(x));
            }
            if anchor.point.has_top() {
                top_edge = top_edge.or(Some(y));
            }
            if anchor.point.has_bottom() {
                bottom_edge = bottom_edge.or(Some(y));
            }
            if first.is_none() {
                first = Some((x, y, anchor.point));
            }
        }
        let mut width = natural_width * scale;
        let mut height = natural_height * scale;
        if let (Some(left), Some(right)) = (left_edge, right_edge) {
            width = right - left;
        }
        if let (Some(top), Some(bottom)) = (top_edge, bottom_edge) {
            height = bottom - top;
        }
        let (first_x, first_y, first_point) = first.unwrap();
        let left = left_edge.or(right_edge.map(|right| right - width)).unwrap_or(first_x - first_point.across() * width);
        let top = top_edge.or(bottom_edge.map(|bottom| bottom - height)).unwrap_or(first_y - first_point.down() * height);
        Rect { left: left + offset_x * scale, top: top - offset_y * scale, width, height }
    }

    /// Whether a point is inside an object's rectangle, as its hit insets leave it. Engine fact 7.
    pub fn holds(&self, id: Id, x: f32, y: f32) -> bool {
        let rect = self.rect(id);
        let inset = self.objs[id].insets;
        let (left, right, top, bottom) = (rect.left + inset[0], rect.right() - inset[1], rect.top + inset[2], rect.bottom() - inset[3]);
        rect.width > 0.0 && rect.height > 0.0 && x >= left && x < right && y >= top && y < bottom
    }

    /// Every frame that takes the mouse at a point, the one that gets it first at the front.
    pub fn hits(&self, x: f32, y: f32, wheel: bool, motion_only: bool) -> Vec<Id> {
        let mut found: Vec<Id> = Vec::new();
        for (id, obj) in self.objs.iter().enumerate() {
            if !obj.class.is_frame() {
                continue;
            }
            let takes = if wheel {
                obj.mouse_wheel
            } else if motion_only {
                obj.mouse_motion
            } else {
                obj.mouse_click
            };
            if !takes || !self.visible(id) || !self.holds(id, x, y) {
                continue;
            }
            // A clipping parent cuts off what is outside it. Engine fact 6.
            let mut cut = false;
            let mut walker = obj.parent;
            while let Some(parent) = walker {
                let ancestor = &self.objs[parent];
                if (ancestor.clips || ancestor.class == Class::ScrollFrame) && !self.holds_plain(parent, x, y) {
                    cut = true;
                }
                walker = ancestor.parent;
            }
            if self.rules.clip_needs_mouse {
                let mut walker = obj.parent;
                while let Some(parent) = walker {
                    let ancestor = &self.objs[parent];
                    if ancestor.clips && !(ancestor.mouse_click || ancestor.mouse_motion) {
                        cut = true;
                    }
                    walker = ancestor.parent;
                }
            }
            if self.rules.scroll_child_limits {
                let mut walker = Some(id);
                while let Some(current) = walker {
                    let Some(parent) = self.objs[current].parent else { break };
                    if self.objs[parent].scroll_child == Some(current) && !self.holds_plain(current, x, y) {
                        cut = true;
                    }
                    walker = Some(parent);
                }
            }
            if !cut {
                found.push(id);
            }
        }
        if self.rules.flatten_clips {
            found.sort_by(|a, b| self.compare_flattened(*a, *b));
            return found;
        }
        found.sort_by(|a, b| {
            let (a, b) = (&self.objs[*a], &self.objs[*b]);
            b.strata.cmp_rank().cmp(&a.strata.cmp_rank()).then(b.level.cmp(&a.level)).then(b.order.cmp(&a.order))
        });
        found
    }

    /// The outermost clipping frame a frame is inside, or itself when it clips, or None.
    fn clip_group(&self, id: Id) -> Option<Id> {
        let mut group = if self.objs[id].clips { Some(id) } else { None };
        let mut walker = self.objs[id].parent;
        while let Some(parent) = walker {
            if self.objs[parent].clips {
                group = Some(parent);
            }
            walker = self.objs[parent].parent;
        }
        group
    }

    fn is_ancestor(&self, ancestor: Id, id: Id) -> bool {
        let mut walker = self.objs[id].parent;
        while let Some(parent) = walker {
            if parent == ancestor {
                return true;
            }
            walker = self.objs[parent].parent;
        }
        false
    }

    /// Orders two frames with each clipping subtree counted as one unit at its clipping frame's level.
    fn compare_flattened(&self, a: Id, b: Id) -> std::cmp::Ordering {
        let (group_a, group_b) = (self.clip_group(a), self.clip_group(b));
        let level = |id: Id, group: Option<Id>| group.map(|group| self.objs[group].level).unwrap_or(self.objs[id].level);
        let (oa, ob) = (&self.objs[a], &self.objs[b]);
        ob.strata
            .cmp_rank()
            .cmp(&oa.strata.cmp_rank())
            .then(level(b, group_b).cmp(&level(a, group_a)))
            .then_with(|| {
                if group_a.is_some() && group_a == group_b {
                    return ob.level.cmp(&oa.level).then(ob.order.cmp(&oa.order));
                }
                if self.is_ancestor(a, b) {
                    return std::cmp::Ordering::Less;
                }
                if self.is_ancestor(b, a) {
                    return std::cmp::Ordering::Greater;
                }
                ob.level.cmp(&oa.level).then(ob.order.cmp(&oa.order))
            })
    }

    fn holds_plain(&self, id: Id, x: f32, y: f32) -> bool {
        let rect = self.rect(id);
        x >= rect.left && x < rect.right() && y >= rect.top && y < rect.bottom()
    }
}

trait Rank {
    fn cmp_rank(self) -> u8;
}

impl Rank for Strata {
    fn cmp_rank(self) -> u8 {
        match self {
            Strata::Background => 1,
            Strata::Low => 2,
            Strata::Medium => 3,
            Strata::High => 4,
            Strata::Dialog => 5,
            Strata::Fullscreen => 6,
            Strata::FullscreenDialog => 7,
            Strata::Tooltip => 8,
        }
    }
}
