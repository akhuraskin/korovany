use bevy::prelude::*;

#[derive(Debug, Clone, Copy, Default, Eq, PartialEq, Hash, States)]
pub enum AppState {
    #[default]
    MainMenu,
    FactionSelect,
    NameInput,
    InGame,
    Paused,
    ShopOpen,
    InventoryOpen,
    HealerOpen,
    SaveLoadMenu,
    GameOver,
}
