//! Instances, their entrances and their bosses, read from the game's own tables.
//!
//! An instance's entrance is the point where a ghost returns to (the map table's corpse point), in world yards on a
//! continent. The table that places each map region on the world gives its bounds in the same yards, so the point
//! becomes a place on the continent's map and on every zone map whose frame holds it (zone frames are rectangles and
//! overlap, so more than one can, and the smallest is not always the zone the entrance is in). The conversion is
//! `docs/game-data-facts.md` row 27. The bosses
//! are in the order the encounter table's order key gives. Each table is pinned by file id and layout hash.

use std::collections::HashMap;

use serde_json::{Value, json};

use crate::casc::{Casc, Error};
use crate::maps::open;

const MAPS: (u32, u32) = (1349477, 0xd43afac3); // name, corpse point (two floats), instance type, corpse continent
const PLACEMENTS: (u32, u32) = (1957219, 0xc9cc8dfb); // parent = region id; bounds (six floats), map id, area id
const REGIONS: (u32, u32) = (1957206, 0xdb51d55f); // name; the row's parent is the parent region
const ENCOUNTERS: (u32, u32) = (1347279, 0x35863dc4); // name, id, map id, difficulty, order key

const INSTANCE_TYPE: usize = 8;
const CORPSE_POINT: usize = 6;
const CORPSE_CONTINENT: usize = 17;

/// Where a region lies in world yards: the smallest and the largest of each axis.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Bounds {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
}

impl Bounds {
    fn from_words(words: &[u64]) -> Option<Bounds> {
        let float = |i: usize| words.get(i).map(|w| f32::from_bits(*w as u32));
        Some(Bounds { min_x: float(0)?, min_y: float(1)?, max_x: float(3)?, max_y: float(4)? })
    }

    fn contains(&self, x: f32, y: f32) -> bool {
        (self.min_x..=self.max_x).contains(&x) && (self.min_y..=self.max_y).contains(&y)
    }

    fn area(&self) -> f32 {
        (self.max_x - self.min_x) * (self.max_y - self.min_y)
    }

    /// The point as a place on this region's map, each from 0 to 1: across is decreasing world y, down is decreasing
    /// world x.
    fn place_of(&self, x: f32, y: f32) -> (f64, f64) {
        (((self.max_y - y) / (self.max_y - self.min_y)) as f64, ((self.max_x - x) / (self.max_x - self.min_x)) as f64)
    }
}

/// The regions whose frame holds the point, smallest first.
fn holding(point: (f32, f32), regions: &[(u32, Bounds)]) -> Vec<(u32, Bounds)> {
    let mut held: Vec<(u32, Bounds)> = regions.iter().filter(|(_, bounds)| bounds.contains(point.0, point.1)).copied().collect();
    held.sort_by(|a, b| a.1.area().total_cmp(&b.1.area()).then(a.0.cmp(&b.0)));
    held
}

/// One boss encounter. The derived order is the one a list wants: by map, then difficulty, then the order key.
#[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
struct Boss {
    map: u32,
    difficulty: u32,
    order: i64,
    id: u32,
    name: String,
}

impl Boss {
    /// The table holds a row, "No Longer in Use", that belongs to no map: it is not a boss of anything.
    fn belongs_to_a_map(&self) -> bool {
        self.map != 0
    }
}

fn in_order(mut bosses: Vec<Boss>) -> Vec<Boss> {
    bosses.sort();
    bosses
}

fn four_digits(value: f64) -> f64 {
    (value * 10_000.0).round() / 10_000.0
}

/// The instances (type 1 a dungeon, 2 a raid) and their bosses, as JSON.
pub fn read(casc: &Casc) -> Result<Value, Error> {
    let maps = open(casc, MAPS, "the maps")?;
    let placements = open(casc, PLACEMENTS, "the region placements")?;
    let regions = open(casc, REGIONS, "the map regions")?;
    let encounters = open(casc, ENCOUNTERS, "the boss encounters")?;

    // Per continent (a map id): its own region, and every other region placed on it.
    let mut on_map: HashMap<u32, Vec<(u32, Bounds)>> = HashMap::new();
    for row in placements.rows() {
        let (Some(region), Some(bounds)) = (row.parent(), Bounds::from_words(&row.numbers(2))) else { continue };
        on_map.entry(row.number(6) as u32).or_default().push((region, bounds));
    }
    let names: HashMap<u32, String> = regions.rows().map(|row| (row.id, row.string(0).unwrap_or_default())).collect();

    let mut instances = Vec::new();
    for row in maps.rows() {
        let kind = match row.number(INSTANCE_TYPE) {
            1 => "dungeon",
            2 => "raid",
            _ => continue,
        };
        let words = row.numbers(CORPSE_POINT);
        let (x, y) = (f32::from_bits(words.first().copied().unwrap_or(0) as u32), f32::from_bits(words.get(1).copied().unwrap_or(0) as u32));
        let continent = row.number(CORPSE_CONTINENT) as u32;
        let mut instance = json!({ "mapId": row.id, "name": row.string(1).unwrap_or_default(), "type": kind, "entrance": null });

        if (x != 0.0 || y != 0.0) && let Some(regions_here) = on_map.get(&continent) {
            // The continent's own region is the largest one on it.
            let largest = regions_here.iter().max_by(|a, b| a.1.area().total_cmp(&b.1.area()));
            if let Some((continent_region, continent_bounds)) = largest {
                let (across, down) = continent_bounds.place_of(x, y);
                let zones: Vec<Value> = holding((x, y), regions_here)
                    .into_iter()
                    // Whole-world and whole-continent regions are not zones: a zone covers far less than a quarter of one.
                    .filter(|(id, bounds)| id != continent_region && bounds.area() < continent_bounds.area() / 4.0)
                    .map(|(id, bounds)| {
                        let (zone_across, zone_down) = bounds.place_of(x, y);
                        json!({ "uiMapId": id, "name": names.get(&id), "x": four_digits(zone_across), "y": four_digits(zone_down) })
                    })
                    .collect();
                instance["entrance"] = json!({
                    "continentMapId": continent, "worldX": x, "worldY": y,
                    "continent": { "uiMapId": continent_region, "x": four_digits(across), "y": four_digits(down) },
                    "zones": zones,
                });
            }
        }

        instances.push(instance);
    }

    // The order key is a signed column: Blackfathom Deeps' bosses run from -6000 up, read as unsigned they would come last.
    // A dungeon has one set of encounters for each difficulty id (Blackfathom Deeps has four), each in its own order.
    let bosses = in_order(encounters.rows().map(|row| Boss { map: row.number(2) as u32, difficulty: row.number(3) as u32, order: row.number(4) as i64, id: row.id, name: row.string(0).unwrap_or_default() }).filter(Boss::belongs_to_a_map).collect());
    let encounters: Vec<Value> = bosses.into_iter().map(|boss| json!({ "id": boss.id, "name": boss.name, "mapId": boss.map, "difficultyId": boss.difficulty, "order": boss.order })).collect();

    Ok(json!({ "build": casc.build, "instances": instances, "encounters": encounters }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bounds(min_x: f32, min_y: f32, max_x: f32, max_y: f32) -> Bounds {
        Bounds { min_x, min_y, max_x, max_y }
    }

    #[test]
    fn a_point_is_placed_across_by_decreasing_y_and_down_by_decreasing_x() {
        // Kalimdor and Winterspring as the tables give them (docs/game-data-facts.md, row 27).
        let kalimdor = bounds(-11733.3, -19733.2, 12799.9, 17066.6);
        let winterspring = bounds(3800.0, -7416.7, 8533.3, -316.7);
        let (across, down) = kalimdor.place_of(winterspring.max_x, winterspring.max_y);

        assert!((across - 0.472_374).abs() < 0.000_3, "the left edge of Winterspring on Kalimdor: {across}");
        assert!((down - 0.173_910).abs() < 0.000_3, "the top edge of Winterspring on Kalimdor: {down}");
    }

    #[test]
    fn every_region_that_holds_a_point_is_listed_smallest_first() {
        let regions = [(1414, bounds(-100.0, -100.0, 100.0, 100.0)), (1452, bounds(0.0, 0.0, 10.0, 10.0)), (1411, bounds(50.0, 50.0, 60.0, 60.0))];
        let ids = |point| holding(point, &regions).into_iter().map(|(id, _)| id).collect::<Vec<u32>>();
        assert_eq!(ids((5.0, 5.0)), vec![1452, 1414]);
        assert_eq!(ids((-50.0, 20.0)), vec![1414]);
        assert!(ids((500.0, 0.0)).is_empty());
    }

    #[test]
    fn bosses_are_grouped_by_map_then_difficulty_and_a_negative_order_key_comes_first() {
        let boss = |difficulty: u32, order: i64, name: &str| Boss { map: 48, difficulty, order, id: 0, name: name.to_string() };
        let names: Vec<String> = in_order(vec![boss(201, 0, "Ghamoo-ra"), boss(0, 0, "Aku'mai"), boss(0, -6000, "Ghamoo-ra"), boss(0, -5000, "Lady Sarevess")]).into_iter().map(|b| format!("{} {}", b.difficulty, b.name)).collect();
        assert_eq!(names, ["0 Ghamoo-ra", "0 Lady Sarevess", "0 Aku'mai", "201 Ghamoo-ra"]);
    }

    #[test]
    fn a_row_with_no_map_is_not_a_boss() {
        let row = |map: u32| Boss { map, difficulty: 0, order: 0, id: 3061, name: "No Longer in Use".to_string() };
        assert!(!row(0).belongs_to_a_map());
        assert!(row(409).belongs_to_a_map());
    }

    #[test]
    fn bounds_come_from_the_first_and_fourth_floats_of_each_axis() {
        let words: Vec<u64> = [1.0f32, 2.0, -1e6, 3.0, 4.0, 1e6].iter().map(|f| f.to_bits() as u64).collect();
        assert_eq!(Bounds::from_words(&words), Some(bounds(1.0, 2.0, 3.0, 4.0)));
        assert_eq!(Bounds::from_words(&words[..3]), None);
    }
}
