# Requirements Coverage Matrix

Source request: [`README.md`](/home/ask/devel/korovany/README.md)

## Covered

- 3D action game loop (movement/combat/UI/save-load): `src/main.rs`, `src/combat3d.rs`, `src/ui_menus.rs`
- Playable factions (elves / palace guard / dark lord): `src/types.rs`, `src/player.rs`
- 4-zone map with forest/palace/fortress/town and roads: `src/world.rs`, `src/world3d.rs`
- Caravan system and raiding in 3D interaction:
  - spawn/move: `src/world.rs`, `src/main.rs`
  - engage guards + loot: `src/combat3d.rs`, `src/trade.rs`
- Buying/trading/healing/inventory: `src/ui_menus.rs`, `src/trade.rs`
- Injury system:
  - dismemberment/bleeding/death: `src/combat.rs`, `src/combat3d.rs`, `src/player.rs`
  - prosthetics + wheelchair use: `src/player.rs`, `src/types.rs`
  - eye loss half-screen visibility penalty: `src/hud.rs`
- Jumping: `src/controller.rs`
- Enemy/NPC 3D representations and loot drop entities: `src/character.rs`, `src/combat3d.rs`
- Save/load: `src/save.rs`, `src/ui_menus.rs`

## Extended to close request gaps

- Tree LOD behavior (far proxy -> near 3D tree): `src/world3d.rs`
- Actionable faction command input (`M`): `src/main.rs`, `src/events.rs`

