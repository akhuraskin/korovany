use std::fs;
use std::path::PathBuf;
use crate::types::GameState;

fn save_dir() -> PathBuf {
    let base = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
    let dir = base.join("korovany").join("saves");
    fs::create_dir_all(&dir).ok();
    dir
}

pub fn save_game(state: &GameState, slot: usize) -> Result<String, String> {
    let path = save_dir().join(format!("save_{}.json", slot));
    let json = serde_json::to_string_pretty(state).map_err(|e| format!("Ошибка сериализации: {}", e))?;
    fs::write(&path, json).map_err(|e| format!("Ошибка записи: {}", e))?;
    Ok(format!("Игра сохранена в слот {}", slot))
}

pub fn load_game(slot: usize) -> Result<GameState, String> {
    let path = save_dir().join(format!("save_{}.json", slot));
    if !path.exists() {
        return Err(format!("Слот {} пуст", slot));
    }
    let json = fs::read_to_string(&path).map_err(|e| format!("Ошибка чтения: {}", e))?;
    let state: GameState = serde_json::from_str(&json).map_err(|e| format!("Ошибка загрузки: {}", e))?;
    Ok(state)
}

pub fn list_saves() -> Vec<(usize, bool)> {
    let dir = save_dir();
    (1..=5)
        .map(|slot| {
            let path = dir.join(format!("save_{}.json", slot));
            (slot, path.exists())
        })
        .collect()
}
