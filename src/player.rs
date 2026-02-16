use crate::types::*;

impl Player {
    pub fn new(name: String, faction: Faction) -> Self {
        let (health, attack, defense, gold) = match faction {
            Faction::Elves => (90, 12, 6, 30),
            Faction::Palace => (100, 10, 10, 50),
            Faction::DarkLord => (110, 14, 8, 40),
        };

        let mut player = Self {
            name,
            faction,
            health,
            max_health: health,
            attack,
            defense,
            gold,
            experience: 0,
            level: 1,
            injuries: Injuries::default(),
            inventory: Vec::new(),
            weapon: None,
            armor: None,
            location: faction.start_location(),
            troops: Vec::new(),
            has_wheelchair: false,
            turn_count: 0,
            salary_turns: 0,
            current_order: CommanderOrder::None,
            disobedience_count: 0,
        };

        // Starting equipment
        match faction {
            Faction::Elves => {
                player.weapon = Some(Item::new_weapon("Эльфийский кинжал", 7, 45));
                player.armor = Some(Item::new_armor("Кожаная куртка", 4, 30));
                player.inventory.push(Item::new_consumable("Травяной бинт", ItemType::Bandage, 0, 8));
                player.inventory.push(Item::new_consumable("Ягоды", ItemType::Food, 8, 4));
            }
            Faction::Palace => {
                player.weapon = Some(Item::new_weapon("Казённый меч", 9, 60));
                player.armor = Some(Item::new_armor("Стражничья кольчуга", 7, 70));
                player.inventory.push(Item::new_consumable("Бинты", ItemType::Bandage, 0, 10));
                player.salary_turns = 10;
            }
            Faction::DarkLord => {
                player.weapon = Some(Item::new_weapon("Тёмный клинок", 11, 90));
                player.armor = Some(Item::new_armor("Доспех тьмы", 9, 100));
                // Start with some troops
                player.troops.push(Npc::new("Тёмный воин", NpcType::DarkSoldier, 50, 8, 5));
                player.troops.push(Npc::new("Тёмный воин", NpcType::DarkSoldier, 50, 8, 5));
                player.troops.push(Npc::new("Тёмный воин", NpcType::DarkSoldier, 50, 8, 5));
            }
        }

        player
    }

    pub fn is_alive(&self) -> bool {
        self.health > 0
    }

    pub fn effective_attack(&self) -> f64 {
        let base = self.attack as f64;
        let weapon_power = self.weapon.as_ref().map_or(1.0, |w| w.power as f64 / 5.0);
        base * weapon_power * self.injuries.attack_modifier()
    }

    pub fn effective_defense(&self) -> f64 {
        let base = self.defense as f64;
        let armor_power = self.armor.as_ref().map_or(0.0, |a| a.power as f64);
        (base + armor_power) * self.injuries.defense_modifier()
    }

    pub fn heal(&mut self, amount: i32) {
        self.health = (self.health + amount).min(self.max_health);
    }

    pub fn take_damage(&mut self, damage: i32) {
        self.health = (self.health - damage).max(0);
    }

    pub fn add_experience(&mut self, exp: i32) -> bool {
        self.experience += exp;
        let needed = self.level * 100;
        if self.experience >= needed {
            self.experience -= needed;
            self.level += 1;
            self.max_health += 10;
            self.health = self.max_health;
            self.attack += 2;
            self.defense += 1;
            true
        } else {
            false
        }
    }

    pub fn can_move(&self) -> bool {
        self.injuries.can_walk() || self.has_wheelchair
    }

    pub fn movement_description(&self) -> &'static str {
        if self.injuries.can_walk() {
            if self.injuries.left_leg == LimbState::Severed || self.injuries.right_leg == LimbState::Severed {
                "Ковыляете на одной ноге"
            } else {
                "Идёте"
            }
        } else if self.has_wheelchair {
            "Едете на коляске"
        } else {
            "Ползёте"
        }
    }

    pub fn equip_weapon(&mut self, index: usize) -> Option<String> {
        if index >= self.inventory.len() {
            return None;
        }
        if self.inventory[index].item_type != ItemType::Weapon {
            return None;
        }
        let new_weapon = self.inventory.remove(index);
        let msg = format!("Вы экипировали: {}", new_weapon.name);
        if let Some(old) = self.weapon.take() {
            self.inventory.push(old);
        }
        self.weapon = Some(new_weapon);
        Some(msg)
    }

    pub fn equip_armor(&mut self, index: usize) -> Option<String> {
        if index >= self.inventory.len() {
            return None;
        }
        if self.inventory[index].item_type != ItemType::Armor {
            return None;
        }
        let new_armor = self.inventory.remove(index);
        let msg = format!("Вы надели: {}", new_armor.name);
        if let Some(old) = self.armor.take() {
            self.inventory.push(old);
        }
        self.armor = Some(new_armor);
        Some(msg)
    }

    pub fn use_item(&mut self, index: usize) -> Option<String> {
        if index >= self.inventory.len() {
            return None;
        }
        let item = &self.inventory[index];
        match item.item_type {
            ItemType::HealingPotion | ItemType::Food => {
                let heal = item.heal_amount;
                let name = item.name.clone();
                self.inventory.remove(index);
                self.heal(heal);
                Some(format!("Вы использовали {}. Здоровье +{}", name, heal))
            }
            ItemType::Bandage => {
                let name = item.name.clone();
                self.inventory.remove(index);
                self.injuries.bleeding = false;
                self.injuries.bleed_turns_left = 0;
                Some(format!("Вы перевязались: {}. Кровотечение остановлено.", name))
            }
            ItemType::ProstheticArm => {
                if self.injuries.left_arm == LimbState::Severed {
                    self.injuries.left_arm = LimbState::Prosthesis;
                    let name = item.name.clone();
                    self.inventory.remove(index);
                    Some(format!("Вы установили {} на левую руку.", name))
                } else if self.injuries.right_arm == LimbState::Severed {
                    self.injuries.right_arm = LimbState::Prosthesis;
                    let name = item.name.clone();
                    self.inventory.remove(index);
                    Some(format!("Вы установили {} на правую руку.", name))
                } else {
                    Some("Нет отрубленных рук для установки протеза.".to_string())
                }
            }
            ItemType::ProstheticLeg => {
                if self.injuries.left_leg == LimbState::Severed {
                    self.injuries.left_leg = LimbState::Prosthesis;
                    let name = item.name.clone();
                    self.inventory.remove(index);
                    Some(format!("Вы установили {} на левую ногу.", name))
                } else if self.injuries.right_leg == LimbState::Severed {
                    self.injuries.right_leg = LimbState::Prosthesis;
                    let name = item.name.clone();
                    self.inventory.remove(index);
                    Some(format!("Вы установили {} на правую ногу.", name))
                } else {
                    Some("Нет отрубленных ног для установки протеза.".to_string())
                }
            }
            ItemType::ProstheticEye => {
                if self.injuries.left_eye == EyeState::Lost {
                    self.injuries.left_eye = EyeState::Prosthesis;
                    let name = item.name.clone();
                    self.inventory.remove(index);
                    Some(format!("Вы вставили {} вместо левого глаза.", name))
                } else if self.injuries.right_eye == EyeState::Lost {
                    self.injuries.right_eye = EyeState::Prosthesis;
                    let name = item.name.clone();
                    self.inventory.remove(index);
                    Some(format!("Вы вставили {} вместо правого глаза.", name))
                } else {
                    Some("Нет потерянных глаз для установки протеза.".to_string())
                }
            }
            ItemType::Wheelchair => {
                self.has_wheelchair = true;
                let name = item.name.clone();
                self.inventory.remove(index);
                Some(format!("Вы теперь используете: {}", name))
            }
            ItemType::Weapon => self.equip_weapon(index),
            ItemType::Armor => self.equip_armor(index),
            ItemType::Loot => Some("Это нельзя использовать. Продайте в магазине.".to_string()),
        }
    }

    pub fn tick_bleeding(&mut self) -> Option<String> {
        if !self.injuries.bleeding {
            return None;
        }
        self.injuries.bleed_turns_left -= 1;
        self.take_damage(5);
        if self.injuries.bleed_turns_left <= 0 {
            self.take_damage(self.health); // fatal
            Some("Вы истекли кровью и погибли!".to_string())
        } else {
            Some(format!(
                "Вы истекаете кровью! (-5 HP) Осталось ходов: {}",
                self.injuries.bleed_turns_left
            ))
        }
    }

    pub fn pay_salary(&mut self) -> Option<String> {
        if self.faction != Faction::Palace {
            return None;
        }
        self.salary_turns = self.salary_turns.saturating_sub(1);
        if self.salary_turns == 0 {
            let salary = 20 + self.level as i32 * 5;
            self.gold += salary;
            self.salary_turns = 10;
            Some(format!("Получено жалование: {} золота", salary))
        } else {
            None
        }
    }
}
