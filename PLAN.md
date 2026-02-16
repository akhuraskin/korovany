# Корованы — Implementation Plan

## Overview
A terminal-based RPG game in Rust implementing the legendary "Korovany" specification.
Three playable factions, 4 world zones, caravan raiding, dismemberment system, trading, and save/load.
Cross-platform (Linux, macOS, Windows).

## Tech Stack
- **Language:** Rust
- **Terminal UI:** crossterm (cross-platform terminal manipulation)
- **Serialization:** serde + serde_json (save/load)
- **Random:** rand (combat, events)
- **File paths:** dirs (cross-platform save file location)

## Architecture

### Source Files
```
src/
├── main.rs        # Entry point, title screen, main menu
├── types.rs       # All enums, structs, item definitions
├── player.rs      # Player state, inventory, injury management
├── world.rs       # World state, zone/location management, NPC spawning
├── combat.rs      # Turn-based combat with dismemberment
├── trade.rs       # Shop system, caravan generation & raiding
├── events.rs      # Random events, faction missions, commander orders
├── save.rs        # Save/load to JSON files
├── ui.rs          # Terminal rendering, input handling, colors
└── game.rs        # Main game loop, action dispatch
```

### Core Data Model

#### Player
- name, faction, health/max_health, attack, defense
- gold, experience, level
- injuries (Injuries struct)
- inventory (Vec<Item>), equipment (weapon + armor)
- current location (LocationId)
- troops (Vec<Npc>) — for Dark Lord faction
- has_wheelchair: bool
- turn_count: u32

#### Injuries System
- left_arm, right_arm: LimbState (Healthy | Wounded | Severed | Prosthesis)
- left_leg, right_leg: LimbState
- left_eye, right_eye: EyeState (Healthy | Wounded | Lost | Prosthesis)
- bleeding: bool, bleed_turns_left: i32
- Modifiers: attack_modifier(), defense_modifier(), movement_speed()
- Severed arm → can't fight (if both), reduced attack
- Severed leg → crawl, wheelchair, or prosthesis; can't walk if both severed without aid
- Lost eye → reduced vision (half screen flavor text), reduced accuracy
- Bleeding → N turns to get healed or die

#### Factions
- **Elves (Лесные Эльфы):** Start in forest village, raid caravans, attack palace & dark lord
- **Palace Guard (Охрана Дворца):** Start in barracks, follow commander orders, defend palace
- **Dark Lord (Тёмный Властелин):** Start in fort tower, command troops, attack palace

#### 4 Zones (each with ~4-5 locations)
1. **Вольный Город** (Neutral Town): TownSquare, TownMarket, TownTavern, TownGates
2. **Имперский Дворец** (Imperial Palace): PalaceGates, PalaceCourtyard, PalaceBarracks, PalaceThroneRoom, PalaceArmory
3. **Эльфийский Лес** (Elf Forest): ForestEdge, ForestVillage, ForestDepths, ForestSacredGrove, ForestOutpost
4. **Тёмная Крепость** (Dark Fortress): MountainPass, FortGates, FortCourtyard, FortDungeon, FortTower
5. **Wilderness roads** (between zones): RoadNorthSouth, RoadEastWest, Crossroads

#### Items & Trading (Daggerfall-style)
- Weapons (various tiers per faction)
- Armor (various tiers per faction)
- Healing Potions, Bandages
- Prosthetics (arm, leg, eye)
- Food, Loot, Wheelchair
- Shops at: TownMarket, PalaceArmory, ForestVillage, FortDungeon
- Healers at: TownTavern, PalaceBarracks, ForestSacredGrove, FortTower

#### Caravans
- Randomly generated caravans traveling between zones
- Have guards (NPCs), goods (Items), and gold
- Player can intercept on road locations and choose to attack
- Combat against guards; success = loot all goods and gold

#### Combat System
- Turn-based: player action → enemy action → repeat
- Actions: Attack, Use Item, Flee
- Damage = attack * weapon_power * injury_modifier - defense * armor
- Critical hits (random chance) can cause dismemberment:
  - Sever arm, sever leg, gouge eye
  - Causes bleeding (need bandage/healer within N turns)
- Enemy NPCs can also be killed (3D corpse → loot)
- Forest gives elves combat bonus (ambush)

#### Faction-Specific Mechanics
- **Elves:** Forest ambush bonus (+30% attack in forest), can raid caravans freely, missions to attack palace/dark lord
- **Palace Guard:** Receive commander orders each few turns, get paid salary, must follow orders (disobedience = penalties), defend against raids
- **Dark Lord:** Command troops (send on missions), self-directed, deal with elf guerrillas, can launch palace assault

#### Save/Load
- Serialize full GameState to JSON
- Save to platform-appropriate directory (dirs crate)
- Multiple save slots
- Auto-save option

## Game Flow

### Title Screen
```
╔══════════════════════════════════════════════╗
║            К О Р О В А Н Ы                  ║
║                                              ║
║        «Я джва года хочу такую игру»         ║
║                                              ║
║   [1] Новая Игра                             ║
║   [2] Загрузить Игру                         ║
║   [3] Выход                                  ║
╚══════════════════════════════════════════════╝
```

### New Game
1. Select faction (1-3)
2. Enter character name
3. Brief faction intro text
4. Start at faction home location

### Main Game Loop (each turn)
1. Display current location (name, description, ASCII art flavor)
2. Display player status bar (health, injuries, gold)
3. Show available actions based on context:
   - [1] Осмотреться (Look around — see NPCs, items, details)
   - [2] Перейти (Move — show connected locations)
   - [3] Магазин (Shop — if location has shop)
   - [4] Лекарь (Healer — if location has healer)
   - [5] Инвентарь (Inventory — use/equip items)
   - [6] Атаковать (Attack — if enemies present)
   - [7] Грабить Корован (Raid caravan — if on road and caravan present)
   - [8] Миссия Фракции (Faction mission — faction-specific actions)
   - [9] Сохранить (Save game)
   - [0] Выход (Quit)
4. Process chosen action
5. Process world events (bleeding tick, random encounters, caravan spawns)
6. Check death conditions
7. Loop

### Combat Screen
```
═══ БОЙ ══════════════════════════════
Враг: Имперский Солдат
Здоровье врага: ████████░░ 80/100

Ваше здоровье:  ██████░░░░ 60/100

[1] Атаковать
[2] Использовать предмет
[3] Бежать
═══════════════════════════════════════
```

### Injury Events
- On critical hit received: "Вражеский удар отрубил вам левую руку! Вы истекаете кровью!"
- Bleeding warning each turn: "Вы истекаете кровью! Осталось ходов: 3"
- Eye loss: subsequent screens show "███████" covering half the display
- Leg loss: movement options change to "Ползти" / "Ехать на коляске"

## Implementation Order

### Phase 1: Foundation
1. ✅ Cargo.toml with dependencies
2. types.rs — all enums, structs, item/shop definitions
3. player.rs — Player struct, new(), injury methods, inventory
4. world.rs — World struct, location graph, NPC spawning

### Phase 2: Core Systems
5. combat.rs — turn-based combat, dismemberment rolls, loot
6. trade.rs — buy/sell at shops, caravan generation, caravan raiding
7. events.rs — random encounters, commander orders, faction missions
8. save.rs — serialize/deserialize GameState

### Phase 3: UI & Game Loop
9. ui.rs — terminal rendering with crossterm (colors, clearing, input)
10. game.rs — main game loop, action routing, state management
11. main.rs — entry point, title screen, new/load game

### Phase 4: Polish
12. Build and test on the platform
13. Fix any compilation errors or bugs
14. Balance combat numbers, shop prices, etc.
15. Commit and push

## Key Design Decisions
- **Terminal-based** rather than graphical 3D (practical for implementation scope)
- **Russian language UI** to honor the original specification
- **Turn-based** combat (text RPG style)
- **All game text in Russian** with ASCII art embellishments
- **Cross-platform** via crossterm + dirs crates (no OS-specific code)
- **Single binary** — no external assets needed
