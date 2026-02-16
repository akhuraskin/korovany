use rand::Rng;
use crate::types::*;

pub fn generate_commander_order(_player: &Player) -> CommanderOrder {
    let mut rng = rand::thread_rng();
    match rng.gen_range(0..4) {
        0 => {
            let patrol_locations = [
                LocationId::PalaceGates,
                LocationId::PalaceCourtyard,
                LocationId::RoadEastWest,
                LocationId::TownGates,
            ];
            CommanderOrder::Patrol(patrol_locations[rng.gen_range(0..patrol_locations.len())])
        }
        1 => {
            let defend_locations = [
                LocationId::PalaceGates,
                LocationId::PalaceThroneRoom,
                LocationId::PalaceCourtyard,
            ];
            CommanderOrder::DefendLocation(defend_locations[rng.gen_range(0..defend_locations.len())])
        }
        2 => CommanderOrder::EscortCaravan,
        3 => {
            let hunt_locations = [
                LocationId::RoadNorthSouth,
                LocationId::RoadEastWest,
                LocationId::Crossroads,
                LocationId::ForestEdge,
            ];
            CommanderOrder::HuntBandits(hunt_locations[rng.gen_range(0..hunt_locations.len())])
        }
        _ => CommanderOrder::None,
    }
}

pub fn check_order_compliance(player: &Player) -> bool {
    match &player.current_order {
        CommanderOrder::Patrol(loc) | CommanderOrder::DefendLocation(loc) | CommanderOrder::HuntBandits(loc) => {
            player.location == *loc
        }
        CommanderOrder::EscortCaravan => {
            player.location.is_road()
        }
        CommanderOrder::None => true,
    }
}

pub fn process_faction_turn(state: &mut GameState) -> Vec<String> {
    let mut messages = Vec::new();

    match state.player.faction {
        Faction::Palace => {
            // Salary
            if let Some(msg) = state.player.pay_salary() {
                messages.push(msg);
            }

            // New orders every 5 turns
            if state.player.turn_count % 5 == 0 && state.player.turn_count > 0 {
                let order = generate_commander_order(&state.player);
                messages.push(format!("Новый приказ командира: {}", order.description()));
                state.player.current_order = order;
            }

            // Check disobedience
            if state.player.turn_count % 5 == 4 {
                if !check_order_compliance(&state.player) {
                    state.player.disobedience_count += 1;
                    if state.player.disobedience_count >= 3 {
                        messages.push("Вы уволены из стражи за неподчинение! Штраф: 50 золота.".to_string());
                        state.player.gold = (state.player.gold - 50).max(0);
                        state.player.current_order = CommanderOrder::None;
                    } else {
                        messages.push(format!(
                            "Командир недоволен! Неподчинение: {}/3. Штраф: 10 золота.",
                            state.player.disobedience_count
                        ));
                        state.player.gold = (state.player.gold - 10).max(0);
                    }
                }
            }
        }
        Faction::Elves => {
            // Elf missions — hint about caravans
            if state.player.turn_count % 7 == 0 && state.player.turn_count > 0 {
                if !state.caravans.is_empty() {
                    let caravan = &state.caravans[0];
                    messages.push(format!(
                        "Разведчики докладывают: корован замечен на «{}»!",
                        caravan.location.name()
                    ));
                } else {
                    messages.push("Разведчики: дороги пусты, корованов нет.".to_string());
                }
            }

            // Occasional elf mission
            if state.player.turn_count % 15 == 0 && state.player.turn_count > 0 {
                let mut rng = rand::thread_rng();
                match rng.gen_range(0..3) {
                    0 => messages.push("Совет старейшин: Атакуйте Имперский Дворец! Слава эльфам!".to_string()),
                    1 => messages.push("Совет старейшин: Разведайте Тёмную Крепость!".to_string()),
                    _ => messages.push("Совет старейшин: Ограбьте корован для нужд деревни!".to_string()),
                }
            }
        }
        Faction::DarkLord => {
            // Troop recruitment
            if state.player.turn_count % 10 == 0 && state.player.turn_count > 0 {
                if state.player.location == LocationId::FortTower || state.player.location == LocationId::FortCourtyard {
                    let troop = Npc::new("Тёмный воин", NpcType::DarkSoldier, 50, 8, 5);
                    state.player.troops.push(troop);
                    messages.push(format!(
                        "Новый воин присоединился к вашей армии! Всего войск: {}",
                        state.player.troops.len()
                    ));
                }
            }

            // Dark Lord missions
            if state.player.turn_count % 12 == 0 && state.player.turn_count > 0 {
                let mut rng = rand::thread_rng();
                match rng.gen_range(0..3) {
                    0 => messages.push("Ваши шпионы доносят: дворец слабо охраняется! Время штурма!".to_string()),
                    1 => messages.push("Эльфийские партизаны тревожат ваши границы. Уничтожьте их!".to_string()),
                    _ => messages.push("Казна пустеет. Ограбьте корованы для финансирования армии!".to_string()),
                }
            }
        }
    }

    messages
}
