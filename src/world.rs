use rand::Rng;
use crate::types::*;

impl GameState {
    pub fn find_location(&self, id: LocationId) -> Option<&Location> {
        self.locations.iter().find(|l| l.id == id)
    }

    pub fn find_location_mut(&mut self, id: LocationId) -> Option<&mut Location> {
        self.locations.iter_mut().find(|l| l.id == id)
    }

    pub fn spawn_caravan(&mut self) {
        let mut rng = rand::thread_rng();
        let road_locations = [LocationId::RoadNorthSouth, LocationId::RoadEastWest, LocationId::Crossroads];
        let location = road_locations[rng.gen_range(0..road_locations.len())];

        // Don't stack too many caravans
        if self.caravans.len() >= 3 {
            return;
        }

        let guard_count = rng.gen_range(1..=3);
        let mut guards = Vec::new();
        for i in 0..guard_count {
            let mut guard = Npc::new(
                &format!("Охранник корована #{}", i + 1),
                NpcType::CaravanGuard,
                40 + rng.gen_range(0..20),
                7 + rng.gen_range(0..4),
                4 + rng.gen_range(0..3),
            );
            guard.gold = rng.gen_range(5..15);
            guards.push(guard);
        }

        let goods_count = rng.gen_range(2..=5);
        let mut goods = Vec::new();
        let possible_goods = vec![
            Item::new_weapon("Торговый меч", 6, 35),
            Item::new_armor("Дорожная кольчуга", 5, 45),
            Item::new_consumable("Зелье лечения", ItemType::HealingPotion, 30, 20),
            Item::new_consumable("Хлеб", ItemType::Food, 5, 3),
            Item { name: "Шёлк".to_string(), item_type: ItemType::Loot, power: 0, price: 40, heal_amount: 0 },
            Item { name: "Специи".to_string(), item_type: ItemType::Loot, power: 0, price: 30, heal_amount: 0 },
            Item { name: "Золотой кубок".to_string(), item_type: ItemType::Loot, power: 0, price: 50, heal_amount: 0 },
        ];
        for _ in 0..goods_count {
            let idx = rng.gen_range(0..possible_goods.len());
            goods.push(possible_goods[idx].clone());
        }

        let gold = rng.gen_range(20..80);

        self.caravans.push(Caravan {
            guards,
            goods,
            gold,
            location,
        });
    }

    pub fn maybe_spawn_random_encounter(&mut self) {
        let mut rng = rand::thread_rng();
        if rng.gen_range(0..100) > 20 {
            return; // 20% chance per turn
        }

        let loc_id = self.player.location;
        if let Some(loc) = self.find_location_mut(loc_id) {
            // Don't spawn if there are already hostiles
            if loc.npcs.iter().any(|n| n.is_hostile() && n.is_alive()) {
                return;
            }

            let npc = match loc_id {
                id if id.is_forest() => {
                    let mut n = Npc::new("Дикий зверь", NpcType::Beast, 30 + rng.gen_range(0..20), 6 + rng.gen_range(0..3), 2);
                    n.gold = rng.gen_range(0..5);
                    n
                }
                id if id.is_road() => {
                    let mut n = Npc::new("Бандит", NpcType::Bandit, 35 + rng.gen_range(0..15), 7 + rng.gen_range(0..3), 3 + rng.gen_range(0..2));
                    n.gold = rng.gen_range(5..20);
                    n.loot.push(Item::new_consumable("Бинты", ItemType::Bandage, 0, 10));
                    n
                }
                _ => return,
            };

            loc.npcs.push(npc);
        }
    }

    pub fn move_caravans(&mut self) {
        let mut rng = rand::thread_rng();
        let road_locations = [LocationId::RoadNorthSouth, LocationId::RoadEastWest, LocationId::Crossroads];

        for caravan in &mut self.caravans {
            if rng.gen_range(0..100) < 40 {
                // 40% chance to move
                let new_loc = road_locations[rng.gen_range(0..road_locations.len())];
                caravan.location = new_loc;
            }
        }

        // Remove caravans that have been around too long (random despawn)
        if rng.gen_range(0..100) < 10 && !self.caravans.is_empty() {
            self.caravans.remove(0);
        }
    }
}

pub fn build_world() -> Vec<Location> {
    vec![
        // === Вольный Город ===
        Location {
            id: LocationId::TownSquare,
            connections: vec![LocationId::TownMarket, LocationId::TownTavern, LocationId::TownGates],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::TownMarket,
            connections: vec![LocationId::TownSquare],
            npcs: vec![Npc::new("Торговец Иван", NpcType::Merchant, 50, 3, 2)],
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::TownTavern,
            connections: vec![LocationId::TownSquare],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::TownGates,
            connections: vec![LocationId::TownSquare, LocationId::Crossroads, LocationId::RoadNorthSouth],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        // === Имперский Дворец ===
        Location {
            id: LocationId::PalaceGates,
            connections: vec![LocationId::PalaceCourtyard, LocationId::RoadEastWest],
            npcs: vec![
                Npc::new("Имперский стражник", NpcType::ImperialSoldier, 60, 10, 8),
            ],
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::PalaceCourtyard,
            connections: vec![LocationId::PalaceGates, LocationId::PalaceBarracks, LocationId::PalaceThroneRoom, LocationId::PalaceArmory],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::PalaceBarracks,
            connections: vec![LocationId::PalaceCourtyard],
            npcs: vec![
                Npc::new("Командир стражи", NpcType::Commander, 80, 12, 10),
            ],
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::PalaceThroneRoom,
            connections: vec![LocationId::PalaceCourtyard],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::PalaceArmory,
            connections: vec![LocationId::PalaceCourtyard],
            npcs: vec![Npc::new("Оружейник", NpcType::Merchant, 50, 3, 2)],
            items_on_ground: Vec::new(),
        },
        // === Эльфийский Лес ===
        Location {
            id: LocationId::ForestEdge,
            connections: vec![LocationId::ForestVillage, LocationId::ForestOutpost, LocationId::Crossroads],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::ForestVillage,
            connections: vec![LocationId::ForestEdge, LocationId::ForestDepths, LocationId::ForestSacredGrove],
            npcs: vec![Npc::new("Эльф-торговец", NpcType::Merchant, 40, 5, 3)],
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::ForestDepths,
            connections: vec![LocationId::ForestVillage, LocationId::ForestSacredGrove],
            npcs: vec![
                Npc::new_hostile("Дикий волк", NpcType::Beast, 25, 6, 1, 3),
                Npc::new_hostile("Медведь", NpcType::Beast, 50, 10, 5, 5),
            ],
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::ForestSacredGrove,
            connections: vec![LocationId::ForestVillage, LocationId::ForestDepths],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::ForestOutpost,
            connections: vec![LocationId::ForestEdge, LocationId::RoadEastWest],
            npcs: vec![
                Npc::new("Эльф-дозорный", NpcType::ElfWarrior, 45, 9, 5),
            ],
            items_on_ground: Vec::new(),
        },
        // === Тёмная Крепость ===
        Location {
            id: LocationId::MountainPass,
            connections: vec![LocationId::FortGates, LocationId::RoadNorthSouth],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::FortGates,
            connections: vec![LocationId::MountainPass, LocationId::FortCourtyard],
            npcs: vec![
                Npc::new("Тёмный страж", NpcType::DarkSoldier, 55, 9, 6),
            ],
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::FortCourtyard,
            connections: vec![LocationId::FortGates, LocationId::FortDungeon, LocationId::FortTower],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::FortDungeon,
            connections: vec![LocationId::FortCourtyard],
            npcs: vec![Npc::new("Тёмный торговец", NpcType::Merchant, 50, 3, 2)],
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::FortTower,
            connections: vec![LocationId::FortCourtyard],
            npcs: Vec::new(),
            items_on_ground: Vec::new(),
        },
        // === Дороги ===
        Location {
            id: LocationId::RoadNorthSouth,
            connections: vec![LocationId::TownGates, LocationId::MountainPass, LocationId::Crossroads],
            npcs: vec![
                Npc::new_hostile("Бандит-головорез", NpcType::Bandit, 35, 7, 3, 12),
                Npc::new_hostile("Бандит-грабитель", NpcType::Bandit, 30, 6, 2, 8),
            ],
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::RoadEastWest,
            connections: vec![LocationId::PalaceGates, LocationId::ForestOutpost, LocationId::Crossroads],
            npcs: vec![
                Npc::new_hostile("Бандит-разбойник", NpcType::Bandit, 40, 8, 4, 15),
            ],
            items_on_ground: Vec::new(),
        },
        Location {
            id: LocationId::Crossroads,
            connections: vec![LocationId::TownGates, LocationId::ForestEdge, LocationId::RoadNorthSouth, LocationId::RoadEastWest],
            npcs: vec![
                Npc::new_hostile("Бандит", NpcType::Bandit, 30, 6, 3, 10),
            ],
            items_on_ground: Vec::new(),
        },
    ]
}
