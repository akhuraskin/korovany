use bevy::prelude::Resource;
use serde::{Deserialize, Serialize};

// === Factions ===

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Faction {
    Elves,      // Лесные Эльфы
    Palace,     // Охрана Дворца
    DarkLord,   // Тёмный Властелин
}

impl Faction {
    pub fn name(&self) -> &'static str {
        match self {
            Faction::Elves => "Лесные Эльфы",
            Faction::Palace => "Охрана Дворца",
            Faction::DarkLord => "Тёмный Властелин",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Faction::Elves => "Вы — эльф из лесного племени. Ваш путь — набеги на корованы, партизанская война и защита леса.",
            Faction::Palace => "Вы — стражник Имперского Дворца. Служите командиру, получаете жалование и защищаете империю.",
            Faction::DarkLord => "Вы — Тёмный Властелин. Командуете войсками тьмы, строите козни и готовите штурм дворца.",
        }
    }

    pub fn start_location(&self) -> LocationId {
        match self {
            Faction::Elves => LocationId::ForestVillage,
            Faction::Palace => LocationId::PalaceBarracks,
            Faction::DarkLord => LocationId::FortTower,
        }
    }
}

// === Injury System ===

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LimbState {
    Healthy,
    Wounded,
    Severed,
    Prosthesis,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EyeState {
    Healthy,
    Wounded,
    Lost,
    Prosthesis,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Injuries {
    pub left_arm: LimbState,
    pub right_arm: LimbState,
    pub left_leg: LimbState,
    pub right_leg: LimbState,
    pub left_eye: EyeState,
    pub right_eye: EyeState,
    pub bleeding: bool,
    pub bleed_turns_left: i32,
}

impl Default for Injuries {
    fn default() -> Self {
        Self {
            left_arm: LimbState::Healthy,
            right_arm: LimbState::Healthy,
            left_leg: LimbState::Healthy,
            right_leg: LimbState::Healthy,
            left_eye: EyeState::Healthy,
            right_eye: EyeState::Healthy,
            bleeding: false,
            bleed_turns_left: 0,
        }
    }
}

impl Injuries {
    pub fn attack_modifier(&self) -> f64 {
        let mut modifier = 1.0;
        match self.right_arm {
            LimbState::Wounded => modifier *= 0.7,
            LimbState::Severed => modifier *= 0.3,
            LimbState::Prosthesis => modifier *= 0.6,
            LimbState::Healthy => {}
        }
        match self.left_arm {
            LimbState::Wounded => modifier *= 0.85,
            LimbState::Severed => modifier *= 0.7,
            LimbState::Prosthesis => modifier *= 0.8,
            LimbState::Healthy => {}
        }
        // Eye loss reduces accuracy
        match self.right_eye {
            EyeState::Wounded => modifier *= 0.9,
            EyeState::Lost => modifier *= 0.7,
            EyeState::Prosthesis => modifier *= 0.8,
            EyeState::Healthy => {}
        }
        match self.left_eye {
            EyeState::Wounded => modifier *= 0.9,
            EyeState::Lost => modifier *= 0.7,
            EyeState::Prosthesis => modifier *= 0.8,
            EyeState::Healthy => {}
        }
        modifier
    }

    pub fn defense_modifier(&self) -> f64 {
        let mut modifier = 1.0;
        match self.left_arm {
            LimbState::Wounded => modifier *= 0.8,
            LimbState::Severed => modifier *= 0.5,
            LimbState::Prosthesis => modifier *= 0.7,
            LimbState::Healthy => {}
        }
        modifier
    }

    pub fn can_walk(&self) -> bool {
        let legs_ok = self.left_leg != LimbState::Severed || self.right_leg != LimbState::Severed;
        let has_prosthesis = self.left_leg == LimbState::Prosthesis || self.right_leg == LimbState::Prosthesis;
        legs_ok || has_prosthesis
    }

    pub fn can_fight(&self) -> bool {
        self.right_arm != LimbState::Severed || self.left_arm != LimbState::Severed
    }

    pub fn movement_speed(&self) -> f64 {
        let mut speed = 1.0;
        match self.left_leg {
            LimbState::Wounded => speed *= 0.7,
            LimbState::Severed => speed *= 0.3,
            LimbState::Prosthesis => speed *= 0.6,
            LimbState::Healthy => {}
        }
        match self.right_leg {
            LimbState::Wounded => speed *= 0.7,
            LimbState::Severed => speed *= 0.3,
            LimbState::Prosthesis => speed *= 0.6,
            LimbState::Healthy => {}
        }
        speed
    }

    pub fn has_any_injury(&self) -> bool {
        self.left_arm != LimbState::Healthy
            || self.right_arm != LimbState::Healthy
            || self.left_leg != LimbState::Healthy
            || self.right_leg != LimbState::Healthy
            || self.left_eye != EyeState::Healthy
            || self.right_eye != EyeState::Healthy
            || self.bleeding
    }

    pub fn injury_summary(&self) -> Vec<String> {
        let mut summary = Vec::new();
        let limb = |name: &str, state: &LimbState| -> Option<String> {
            match state {
                LimbState::Healthy => None,
                LimbState::Wounded => Some(format!("{}: ранена", name)),
                LimbState::Severed => Some(format!("{}: отрублена!", name)),
                LimbState::Prosthesis => Some(format!("{}: протез", name)),
            }
        };
        let eye = |name: &str, state: &EyeState| -> Option<String> {
            match state {
                EyeState::Healthy => None,
                EyeState::Wounded => Some(format!("{}: ранен", name)),
                EyeState::Lost => Some(format!("{}: потерян!", name)),
                EyeState::Prosthesis => Some(format!("{}: протез", name)),
            }
        };
        if let Some(s) = limb("Левая рука", &self.left_arm) { summary.push(s); }
        if let Some(s) = limb("Правая рука", &self.right_arm) { summary.push(s); }
        if let Some(s) = limb("Левая нога", &self.left_leg) { summary.push(s); }
        if let Some(s) = limb("Правая нога", &self.right_leg) { summary.push(s); }
        if let Some(s) = eye("Левый глаз", &self.left_eye) { summary.push(s); }
        if let Some(s) = eye("Правый глаз", &self.right_eye) { summary.push(s); }
        if self.bleeding {
            summary.push(format!("КРОВОТЕЧЕНИЕ! Осталось ходов: {}", self.bleed_turns_left));
        }
        summary
    }
}

// === Locations ===

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum LocationId {
    // Вольный Город
    TownSquare,
    TownMarket,
    TownTavern,
    TownGates,
    // Имперский Дворец
    PalaceGates,
    PalaceCourtyard,
    PalaceBarracks,
    PalaceThroneRoom,
    PalaceArmory,
    // Эльфийский Лес
    ForestEdge,
    ForestVillage,
    ForestDepths,
    ForestSacredGrove,
    ForestOutpost,
    // Тёмная Крепость
    MountainPass,
    FortGates,
    FortCourtyard,
    FortDungeon,
    FortTower,
    // Roads
    RoadNorthSouth,
    RoadEastWest,
    Crossroads,
}

impl LocationId {
    pub fn name(&self) -> &'static str {
        match self {
            LocationId::TownSquare => "Городская площадь",
            LocationId::TownMarket => "Рынок",
            LocationId::TownTavern => "Таверна",
            LocationId::TownGates => "Городские ворота",
            LocationId::PalaceGates => "Ворота дворца",
            LocationId::PalaceCourtyard => "Дворцовый двор",
            LocationId::PalaceBarracks => "Казармы",
            LocationId::PalaceThroneRoom => "Тронный зал",
            LocationId::PalaceArmory => "Оружейная",
            LocationId::ForestEdge => "Опушка леса",
            LocationId::ForestVillage => "Эльфийская деревня",
            LocationId::ForestDepths => "Чаща леса",
            LocationId::ForestSacredGrove => "Священная роща",
            LocationId::ForestOutpost => "Лесной форпост",
            LocationId::MountainPass => "Горный перевал",
            LocationId::FortGates => "Ворота крепости",
            LocationId::FortCourtyard => "Двор крепости",
            LocationId::FortDungeon => "Подземелье",
            LocationId::FortTower => "Башня Властелина",
            LocationId::RoadNorthSouth => "Дорога Север-Юг",
            LocationId::RoadEastWest => "Дорога Запад-Восток",
            LocationId::Crossroads => "Перекрёсток",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            LocationId::TownSquare => "Шумная площадь вольного города. Торговцы кричат, стражники патрулируют.",
            LocationId::TownMarket => "Крытый рынок с лавками оружейников, зельеваров и скупщиков краденого.",
            LocationId::TownTavern => "Тёмная таверна «Слепой Тролль». Здесь лечат раны и продают слухи.",
            LocationId::TownGates => "Массивные ворота города. Стражники проверяют путников.",
            LocationId::PalaceGates => "Золочёные ворота Имперского Дворца. Стража в блестящих доспехах.",
            LocationId::PalaceCourtyard => "Мощёный двор дворца. Фонтан в центре, казармы слева.",
            LocationId::PalaceBarracks => "Казармы дворцовой стражи. Оружейные стойки и койки.",
            LocationId::PalaceThroneRoom => "Тронный зал Императора. Золото, мрамор, величие.",
            LocationId::PalaceArmory => "Дворцовая оружейная. Лучшее оружие и доспехи империи.",
            LocationId::ForestEdge => "Границы древнего леса. Деревья смыкаются над головой.",
            LocationId::ForestVillage => "Эльфийская деревня на деревьях. Мосты из лиан, домики в кронах.",
            LocationId::ForestDepths => "Тёмная чаща. Здесь водятся опасные звери и заблудшие путники.",
            LocationId::ForestSacredGrove => "Священная роща эльфов. Древний дуб светится магией. Здесь лечат раны.",
            LocationId::ForestOutpost => "Сторожевой пост эльфов на опушке. Отсюда следят за дорогами.",
            LocationId::MountainPass => "Узкий горный перевал. Ветер воет, камни осыпаются.",
            LocationId::FortGates => "Чёрные ворота крепости. Шипы, черепа, устрашение.",
            LocationId::FortCourtyard => "Мрачный двор крепости. Тренировочные манекены и клетки с пленниками.",
            LocationId::FortDungeon => "Подземелье крепости. Тёмные коридоры, камеры пыток, склады.",
            LocationId::FortTower => "Башня Тёмного Властелина. Вид на все земли. Здесь куётся зло.",
            LocationId::RoadNorthSouth => "Пыльная дорога с севера на юг. Здесь ходят корованы...",
            LocationId::RoadEastWest => "Торговый тракт с запада на восток. Следы повозок в грязи.",
            LocationId::Crossroads => "Перекрёсток трёх дорог. Каменный указатель порос мхом.",
        }
    }

    pub fn is_road(&self) -> bool {
        matches!(self, LocationId::RoadNorthSouth | LocationId::RoadEastWest | LocationId::Crossroads)
    }

    pub fn is_forest(&self) -> bool {
        matches!(self,
            LocationId::ForestEdge
            | LocationId::ForestVillage
            | LocationId::ForestDepths
            | LocationId::ForestSacredGrove
            | LocationId::ForestOutpost
        )
    }

    pub fn has_shop(&self) -> bool {
        matches!(self,
            LocationId::TownMarket
            | LocationId::PalaceArmory
            | LocationId::ForestVillage
            | LocationId::FortDungeon
        )
    }

    pub fn has_healer(&self) -> bool {
        matches!(self,
            LocationId::TownTavern
            | LocationId::PalaceBarracks
            | LocationId::ForestSacredGrove
            | LocationId::FortTower
        )
    }
}

// === Items ===

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ItemType {
    Weapon,
    Armor,
    HealingPotion,
    Bandage,
    ProstheticArm,
    ProstheticLeg,
    ProstheticEye,
    Food,
    Loot,
    Wheelchair,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Item {
    pub name: String,
    pub item_type: ItemType,
    pub power: i32,      // weapon damage or armor defense
    pub price: i32,
    pub heal_amount: i32, // for healing items
}

impl Item {
    pub fn new_weapon(name: &str, power: i32, price: i32) -> Self {
        Self {
            name: name.to_string(),
            item_type: ItemType::Weapon,
            power,
            price,
            heal_amount: 0,
        }
    }

    pub fn new_armor(name: &str, power: i32, price: i32) -> Self {
        Self {
            name: name.to_string(),
            item_type: ItemType::Armor,
            power,
            price,
            heal_amount: 0,
        }
    }

    pub fn new_consumable(name: &str, item_type: ItemType, heal: i32, price: i32) -> Self {
        Self {
            name: name.to_string(),
            item_type,
            power: 0,
            price,
            heal_amount: heal,
        }
    }

    pub fn new_prosthetic(name: &str, item_type: ItemType, price: i32) -> Self {
        Self {
            name: name.to_string(),
            item_type,
            power: 0,
            price,
            heal_amount: 0,
        }
    }
}

// === NPCs ===

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NpcType {
    Bandit,
    ImperialSoldier,
    ElfWarrior,
    DarkSoldier,
    Beast,
    CaravanGuard,
    Commander,
    Merchant,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Npc {
    pub name: String,
    pub npc_type: NpcType,
    pub health: i32,
    pub max_health: i32,
    pub attack: i32,
    pub defense: i32,
    pub gold: i32,
    pub loot: Vec<Item>,
}

impl Npc {
    pub fn new(name: &str, npc_type: NpcType, health: i32, attack: i32, defense: i32) -> Self {
        Self {
            name: name.to_string(),
            npc_type,
            health,
            max_health: health,
            attack,
            defense,
            gold: 0,
            loot: Vec::new(),
        }
    }

    pub fn new_hostile(name: &str, npc_type: NpcType, health: i32, attack: i32, defense: i32, gold: i32) -> Self {
        let mut npc = Self::new(name, npc_type, health, attack, defense);
        npc.gold = gold;
        npc
    }

    pub fn is_alive(&self) -> bool {
        self.health > 0
    }

    pub fn is_hostile(&self) -> bool {
        matches!(self.npc_type, NpcType::Bandit | NpcType::Beast)
    }
}

// === Caravan ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Caravan {
    pub guards: Vec<Npc>,
    pub goods: Vec<Item>,
    pub gold: i32,
    pub location: LocationId,
}

// === Location ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Location {
    pub id: LocationId,
    pub connections: Vec<LocationId>,
    pub npcs: Vec<Npc>,
    pub items_on_ground: Vec<Item>,
}

// === Commander Order (Palace Guard) ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CommanderOrder {
    Patrol(LocationId),
    DefendLocation(LocationId),
    EscortCaravan,
    HuntBandits(LocationId),
    None,
}

impl CommanderOrder {
    pub fn description(&self) -> String {
        match self {
            CommanderOrder::Patrol(loc) => format!("Патрулировать: {}", loc.name()),
            CommanderOrder::DefendLocation(loc) => format!("Защищать: {}", loc.name()),
            CommanderOrder::EscortCaravan => "Сопровождать корован".to_string(),
            CommanderOrder::HuntBandits(loc) => format!("Уничтожить бандитов: {}", loc.name()),
            CommanderOrder::None => "Нет приказов. Свободное время.".to_string(),
        }
    }
}

// === Game State ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Player {
    pub name: String,
    pub faction: Faction,
    pub health: i32,
    pub max_health: i32,
    pub attack: i32,
    pub defense: i32,
    pub gold: i32,
    pub experience: i32,
    pub level: i32,
    pub injuries: Injuries,
    pub inventory: Vec<Item>,
    pub weapon: Option<Item>,
    pub armor: Option<Item>,
    pub location: LocationId,
    pub troops: Vec<Npc>,
    pub has_wheelchair: bool,
    pub turn_count: u32,
    pub salary_turns: u32, // turns until next salary (Palace Guard)
    pub current_order: CommanderOrder,
    pub disobedience_count: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Resource)]
pub struct GameState {
    pub player: Player,
    pub locations: Vec<Location>,
    pub caravans: Vec<Caravan>,
    pub messages: Vec<String>,
    pub game_over: bool,
    pub victory: bool,
}

// === Dismemberment target ===

#[derive(Debug, Clone, Copy)]
pub enum DismemberTarget {
    LeftArm,
    RightArm,
    LeftLeg,
    RightLeg,
    LeftEye,
    RightEye,
}

impl DismemberTarget {
    pub fn name(&self) -> &'static str {
        match self {
            DismemberTarget::LeftArm => "левую руку",
            DismemberTarget::RightArm => "правую руку",
            DismemberTarget::LeftLeg => "левую ногу",
            DismemberTarget::RightLeg => "правую ногу",
            DismemberTarget::LeftEye => "левый глаз",
            DismemberTarget::RightEye => "правый глаз",
        }
    }
}

// === Shop inventory definitions ===

pub fn shop_items_for(location: LocationId) -> Vec<Item> {
    match location {
        LocationId::TownMarket => vec![
            Item::new_weapon("Железный меч", 8, 50),
            Item::new_weapon("Топор", 10, 65),
            Item::new_armor("Кожаная броня", 5, 40),
            Item::new_armor("Кольчуга", 8, 80),
            Item::new_consumable("Зелье лечения", ItemType::HealingPotion, 30, 20),
            Item::new_consumable("Бинты", ItemType::Bandage, 0, 10),
            Item::new_consumable("Хлеб", ItemType::Food, 5, 3),
            Item::new_prosthetic("Протез руки", ItemType::ProstheticArm, 100),
            Item::new_prosthetic("Протез ноги", ItemType::ProstheticLeg, 100),
            Item::new_prosthetic("Стеклянный глаз", ItemType::ProstheticEye, 80),
            Item { name: "Коляска".to_string(), item_type: ItemType::Wheelchair, power: 0, price: 60, heal_amount: 0 },
        ],
        LocationId::PalaceArmory => vec![
            Item::new_weapon("Имперский меч", 12, 100),
            Item::new_weapon("Алебарда", 14, 130),
            Item::new_armor("Имперская кираса", 10, 120),
            Item::new_armor("Полные латы", 14, 200),
            Item::new_consumable("Зелье лечения", ItemType::HealingPotion, 30, 20),
            Item::new_consumable("Бинты", ItemType::Bandage, 0, 10),
        ],
        LocationId::ForestVillage => vec![
            Item::new_weapon("Эльфийский лук", 11, 90),
            Item::new_weapon("Эльфийский кинжал", 7, 45),
            Item::new_armor("Эльфийская кожа", 7, 70),
            Item::new_consumable("Лесное зелье", ItemType::HealingPotion, 40, 25),
            Item::new_consumable("Травяной бинт", ItemType::Bandage, 0, 8),
            Item::new_consumable("Ягоды", ItemType::Food, 8, 4),
            Item::new_prosthetic("Древесный протез руки", ItemType::ProstheticArm, 80),
            Item::new_prosthetic("Древесный протез ноги", ItemType::ProstheticLeg, 80),
        ],
        LocationId::FortDungeon => vec![
            Item::new_weapon("Тёмный клинок", 13, 110),
            Item::new_weapon("Моргенштерн", 15, 150),
            Item::new_armor("Доспех тьмы", 12, 140),
            Item::new_consumable("Тёмное зелье", ItemType::HealingPotion, 35, 22),
            Item::new_consumable("Бинты", ItemType::Bandage, 0, 10),
            Item::new_prosthetic("Железная клешня", ItemType::ProstheticArm, 90),
            Item::new_prosthetic("Железная нога", ItemType::ProstheticLeg, 90),
            Item::new_prosthetic("Рубиновый глаз", ItemType::ProstheticEye, 100),
        ],
        _ => Vec::new(),
    }
}

pub fn healer_price() -> i32 {
    25
}
