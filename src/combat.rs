use rand::Rng;
use crate::types::*;

#[derive(Debug)]
pub enum CombatAction {
    Attack,
    UseItem(usize),
    Flee,
}

#[derive(Debug)]
pub enum CombatResult {
    Continue(Vec<String>),
    Victory(Vec<String>, Vec<Item>, i32), // messages, loot, gold
    Defeat(Vec<String>),
    Fled(Vec<String>),
}

pub fn player_attack(player: &mut Player, enemy: &mut Npc) -> Vec<String> {
    let mut messages = Vec::new();
    let mut rng = rand::thread_rng();

    let attack_power = player.effective_attack();
    let defense = enemy.defense as f64;
    let mut damage = (attack_power - defense * 0.5).max(1.0) as i32;

    // Elf forest bonus
    if player.faction == Faction::Elves && player.location.is_forest() {
        damage = (damage as f64 * 1.3) as i32;
        messages.push("Бонус леса! (+30% урон)".to_string());
    }

    // Random variance
    damage = (damage as f64 * (0.8 + rng.gen::<f64>() * 0.4)) as i32;
    damage = damage.max(1);

    enemy.health -= damage;
    messages.push(format!("Вы наносите {} урона {}!", damage, enemy.name));

    // Critical hit chance (15%)
    if rng.gen_range(0..100) < 15 {
        let extra = damage / 2;
        enemy.health -= extra;
        messages.push(format!("КРИТИЧЕСКИЙ УДАР! Ещё {} урона!", extra));
    }

    if enemy.health <= 0 {
        enemy.health = 0;
        messages.push(format!("{} повержен!", enemy.name));
    }

    messages
}

pub fn enemy_attack(enemy: &Npc, player: &mut Player) -> Vec<String> {
    let mut messages = Vec::new();
    let mut rng = rand::thread_rng();

    let attack_power = enemy.attack as f64;
    let defense = player.effective_defense();
    let mut damage = (attack_power - defense * 0.3).max(1.0) as i32;

    // Random variance
    damage = (damage as f64 * (0.8 + rng.gen::<f64>() * 0.4)) as i32;
    damage = damage.max(1);

    player.take_damage(damage);
    messages.push(format!("{} наносит вам {} урона!", enemy.name, damage));

    // Critical hit with dismemberment (10%)
    if rng.gen_range(0..100) < 10 {
        let extra = damage / 2;
        player.take_damage(extra);
        messages.push(format!("КРИТИЧЕСКИЙ УДАР! Ещё {} урона!", extra));

        // Dismemberment roll (50% on crit)
        if rng.gen_range(0..100) < 50 {
            let dismember_msg = apply_dismemberment(player, &mut rng);
            messages.push(dismember_msg);
        }
    }

    if !player.is_alive() {
        messages.push("Вы погибли в бою!".to_string());
    }

    messages
}

pub fn apply_dismemberment(player: &mut Player, rng: &mut impl Rng) -> String {
    let targets = [
        DismemberTarget::LeftArm,
        DismemberTarget::RightArm,
        DismemberTarget::LeftLeg,
        DismemberTarget::RightLeg,
        DismemberTarget::LeftEye,
        DismemberTarget::RightEye,
    ];

    let target = targets[rng.gen_range(0..targets.len())];

    match target {
        DismemberTarget::LeftArm => {
            match player.injuries.left_arm {
                LimbState::Healthy => {
                    player.injuries.left_arm = LimbState::Wounded;
                    "Вражеский удар ранил вашу левую руку!".to_string()
                }
                LimbState::Wounded => {
                    player.injuries.left_arm = LimbState::Severed;
                    player.injuries.bleeding = true;
                    player.injuries.bleed_turns_left = 5;
                    "Вражеский удар ОТРУБИЛ вашу левую руку! Вы истекаете кровью!".to_string()
                }
                _ => "Удар попал по уже раненой руке.".to_string(),
            }
        }
        DismemberTarget::RightArm => {
            match player.injuries.right_arm {
                LimbState::Healthy => {
                    player.injuries.right_arm = LimbState::Wounded;
                    "Вражеский удар ранил вашу правую руку!".to_string()
                }
                LimbState::Wounded => {
                    player.injuries.right_arm = LimbState::Severed;
                    player.injuries.bleeding = true;
                    player.injuries.bleed_turns_left = 5;
                    "Вражеский удар ОТРУБИЛ вашу правую руку! Вы истекаете кровью!".to_string()
                }
                _ => "Удар попал по уже раненой руке.".to_string(),
            }
        }
        DismemberTarget::LeftLeg => {
            match player.injuries.left_leg {
                LimbState::Healthy => {
                    player.injuries.left_leg = LimbState::Wounded;
                    "Вражеский удар ранил вашу левую ногу!".to_string()
                }
                LimbState::Wounded => {
                    player.injuries.left_leg = LimbState::Severed;
                    player.injuries.bleeding = true;
                    player.injuries.bleed_turns_left = 5;
                    "Вражеский удар ОТРУБИЛ вашу левую ногу! Вы истекаете кровью!".to_string()
                }
                _ => "Удар попал по уже раненой ноге.".to_string(),
            }
        }
        DismemberTarget::RightLeg => {
            match player.injuries.right_leg {
                LimbState::Healthy => {
                    player.injuries.right_leg = LimbState::Wounded;
                    "Вражеский удар ранил вашу правую ногу!".to_string()
                }
                LimbState::Wounded => {
                    player.injuries.right_leg = LimbState::Severed;
                    player.injuries.bleeding = true;
                    player.injuries.bleed_turns_left = 5;
                    "Вражеский удар ОТРУБИЛ вашу правую ногу! Вы истекаете кровью!".to_string()
                }
                _ => "Удар попал по уже раненой ноге.".to_string(),
            }
        }
        DismemberTarget::LeftEye => {
            match player.injuries.left_eye {
                EyeState::Healthy => {
                    player.injuries.left_eye = EyeState::Wounded;
                    "Вражеский удар ранил ваш левый глаз!".to_string()
                }
                EyeState::Wounded => {
                    player.injuries.left_eye = EyeState::Lost;
                    player.injuries.bleeding = true;
                    player.injuries.bleed_turns_left = 4;
                    "Вражеский удар ВЫБИЛ ваш левый глаз! Вы истекаете кровью!".to_string()
                }
                _ => "Удар попал по уже раненому глазу.".to_string(),
            }
        }
        DismemberTarget::RightEye => {
            match player.injuries.right_eye {
                EyeState::Healthy => {
                    player.injuries.right_eye = EyeState::Wounded;
                    "Вражеский удар ранил ваш правый глаз!".to_string()
                }
                EyeState::Wounded => {
                    player.injuries.right_eye = EyeState::Lost;
                    player.injuries.bleeding = true;
                    player.injuries.bleed_turns_left = 4;
                    "Вражеский удар ВЫБИЛ ваш правый глаз! Вы истекаете кровью!".to_string()
                }
                _ => "Удар попал по уже раненому глазу.".to_string(),
            }
        }
    }
}

pub fn combat_round(player: &mut Player, enemy: &mut Npc, action: CombatAction) -> CombatResult {
    let mut all_messages = Vec::new();

    match action {
        CombatAction::Attack => {
            if !player.injuries.can_fight() {
                all_messages.push("Вы не можете сражаться — обе руки потеряны!".to_string());
                return CombatResult::Continue(all_messages);
            }

            let msgs = player_attack(player, enemy);
            all_messages.extend(msgs);

            if !enemy.is_alive() {
                let exp = 20 + enemy.max_health / 2;
                let loot = enemy.loot.clone();
                let gold = enemy.gold;
                if player.add_experience(exp) {
                    all_messages.push(format!("Уровень повышен! Теперь уровень {}!", player.level));
                }
                all_messages.push(format!("+{} опыта", exp));
                if gold > 0 {
                    player.gold += gold;
                    all_messages.push(format!("+{} золота", gold));
                }
                for item in &loot {
                    all_messages.push(format!("Добыча: {}", item.name));
                    player.inventory.push(item.clone());
                }
                return CombatResult::Victory(all_messages, loot, gold);
            }

            // Enemy attacks back
            let msgs = enemy_attack(enemy, player);
            all_messages.extend(msgs);

            if !player.is_alive() {
                return CombatResult::Defeat(all_messages);
            }
        }
        CombatAction::UseItem(idx) => {
            if let Some(msg) = player.use_item(idx) {
                all_messages.push(msg);
            } else {
                all_messages.push("Не удалось использовать предмет.".to_string());
            }

            // Enemy still attacks
            let msgs = enemy_attack(enemy, player);
            all_messages.extend(msgs);

            if !player.is_alive() {
                return CombatResult::Defeat(all_messages);
            }
        }
        CombatAction::Flee => {
            let mut rng = rand::thread_rng();
            let flee_chance = (50.0 * player.injuries.movement_speed()) as i32;
            if rng.gen_range(0..100) < flee_chance {
                all_messages.push("Вы успешно сбежали!".to_string());
                return CombatResult::Fled(all_messages);
            } else {
                all_messages.push("Не удалось сбежать!".to_string());
                // Enemy attacks
                let msgs = enemy_attack(enemy, player);
                all_messages.extend(msgs);
                if !player.is_alive() {
                    return CombatResult::Defeat(all_messages);
                }
            }
        }
    }

    CombatResult::Continue(all_messages)
}
