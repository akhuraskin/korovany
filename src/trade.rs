use crate::types::*;

pub fn buy_item(player: &mut Player, shop_items: &[Item], index: usize) -> String {
    if index >= shop_items.len() {
        return "Неверный выбор.".to_string();
    }

    let item = &shop_items[index];
    if player.gold < item.price {
        return format!("Не хватает золота! Нужно: {}, у вас: {}", item.price, player.gold);
    }

    player.gold -= item.price;
    let name = item.name.clone();
    player.inventory.push(item.clone());
    format!("Куплено: {} за {} золота", name, item.price)
}

pub fn sell_item(player: &mut Player, index: usize) -> String {
    if index >= player.inventory.len() {
        return "Неверный выбор.".to_string();
    }

    let item = &player.inventory[index];
    let sell_price = item.price / 2;
    let name = item.name.clone();
    player.gold += sell_price;
    player.inventory.remove(index);
    format!("Продано: {} за {} золота", name, sell_price)
}

pub fn heal_at_healer(player: &mut Player) -> String {
    let price = healer_price();
    if player.gold < price {
        return format!("Не хватает золота! Нужно: {}, у вас: {}", price, player.gold);
    }

    if player.health >= player.max_health && !player.injuries.bleeding {
        let has_wounds = player.injuries.left_arm == LimbState::Wounded
            || player.injuries.right_arm == LimbState::Wounded
            || player.injuries.left_leg == LimbState::Wounded
            || player.injuries.right_leg == LimbState::Wounded
            || player.injuries.left_eye == EyeState::Wounded
            || player.injuries.right_eye == EyeState::Wounded;

        if !has_wounds {
            return "Вы полностью здоровы!".to_string();
        }
    }

    player.gold -= price;

    // Heal HP to full
    player.health = player.max_health;

    // Stop bleeding
    player.injuries.bleeding = false;
    player.injuries.bleed_turns_left = 0;

    // Heal wounded limbs (not severed — those need prosthetics)
    if player.injuries.left_arm == LimbState::Wounded {
        player.injuries.left_arm = LimbState::Healthy;
    }
    if player.injuries.right_arm == LimbState::Wounded {
        player.injuries.right_arm = LimbState::Healthy;
    }
    if player.injuries.left_leg == LimbState::Wounded {
        player.injuries.left_leg = LimbState::Healthy;
    }
    if player.injuries.right_leg == LimbState::Wounded {
        player.injuries.right_leg = LimbState::Healthy;
    }
    if player.injuries.left_eye == EyeState::Wounded {
        player.injuries.left_eye = EyeState::Healthy;
    }
    if player.injuries.right_eye == EyeState::Wounded {
        player.injuries.right_eye = EyeState::Healthy;
    }

    format!("Лекарь вылечил вас за {} золота. Здоровье восстановлено, раны залечены.", price)
}

pub fn raid_caravan(state: &mut GameState, caravan_index: usize) -> (Vec<String>, Option<usize>) {
    let mut messages = Vec::new();

    if caravan_index >= state.caravans.len() {
        messages.push("Нет такого корована.".to_string());
        return (messages, None);
    }

    let caravan = &state.caravans[caravan_index];
    if caravan.location != state.player.location {
        messages.push("Этот корован не здесь.".to_string());
        return (messages, None);
    }

    // Check if guards are alive
    let has_guards = caravan.guards.iter().any(|g| g.is_alive());

    if has_guards {
        // Return the index of the first alive guard for combat
        let guard_idx = caravan.guards.iter().position(|g| g.is_alive()).unwrap();
        messages.push(format!(
            "Охранники корована вступают в бой! ({} живых)",
            caravan.guards.iter().filter(|g| g.is_alive()).count()
        ));
        return (messages, Some(guard_idx));
    }

    // All guards dead — loot the caravan
    let gold = caravan.gold;
    let goods = caravan.goods.clone();

    state.player.gold += gold;
    messages.push(format!("Вы ограбили корован! +{} золота", gold));

    for item in &goods {
        messages.push(format!("Добыча: {}", item.name));
        state.player.inventory.push(item.clone());
    }

    state.caravans.remove(caravan_index);
    messages.push("Корован разграблен полностью!".to_string());

    (messages, None)
}
