use bevy::prelude::*;
use crate::app_state::AppState;
use crate::materials;
use crate::types::*;
use crate::save;
use crate::trade;
use crate::world::build_world;

pub struct UiMenusPlugin;

impl Plugin for UiMenusPlugin {
    fn build(&self, app: &mut App) {
        app.insert_resource(SelectedFaction(None))
            .insert_resource(PlayerNameInput("Герой".into()))
            .insert_resource(ShopState::default())
            .add_systems(OnEnter(AppState::MainMenu), spawn_main_menu)
            .add_systems(OnExit(AppState::MainMenu), despawn_menu)
            .add_systems(Update, main_menu_buttons.run_if(in_state(AppState::MainMenu)))
            .add_systems(OnEnter(AppState::FactionSelect), spawn_faction_menu)
            .add_systems(OnExit(AppState::FactionSelect), despawn_menu)
            .add_systems(Update, faction_menu_buttons.run_if(in_state(AppState::FactionSelect)))
            .add_systems(OnEnter(AppState::NameInput), spawn_name_input)
            .add_systems(OnExit(AppState::NameInput), despawn_menu)
            .add_systems(Update, name_input_system.run_if(in_state(AppState::NameInput)))
            .add_systems(OnEnter(AppState::Paused), spawn_pause_menu)
            .add_systems(OnExit(AppState::Paused), despawn_menu)
            .add_systems(Update, pause_menu_buttons.run_if(in_state(AppState::Paused)))
            .add_systems(Update, pause_key.run_if(in_state(AppState::InGame)))
            .add_systems(OnEnter(AppState::ShopOpen), spawn_shop_menu)
            .add_systems(OnExit(AppState::ShopOpen), despawn_menu)
            .add_systems(Update, shop_menu_buttons.run_if(in_state(AppState::ShopOpen)))
            .add_systems(Update, shop_open_key.run_if(in_state(AppState::InGame)))
            .add_systems(OnEnter(AppState::InventoryOpen), spawn_inventory_menu)
            .add_systems(OnExit(AppState::InventoryOpen), despawn_menu)
            .add_systems(Update, inventory_buttons.run_if(in_state(AppState::InventoryOpen)))
            .add_systems(Update, inventory_key.run_if(in_state(AppState::InGame)))
            .add_systems(OnEnter(AppState::HealerOpen), spawn_healer_menu)
            .add_systems(OnExit(AppState::HealerOpen), despawn_menu)
            .add_systems(Update, healer_buttons.run_if(in_state(AppState::HealerOpen)))
            .add_systems(Update, healer_key.run_if(in_state(AppState::InGame)))
            .add_systems(OnEnter(AppState::SaveLoadMenu), spawn_save_load_menu)
            .add_systems(OnExit(AppState::SaveLoadMenu), despawn_menu)
            .add_systems(Update, save_load_buttons.run_if(in_state(AppState::SaveLoadMenu)))
            .add_systems(OnEnter(AppState::GameOver), spawn_game_over)
            .add_systems(OnExit(AppState::GameOver), despawn_menu)
            .add_systems(Update, game_over_buttons.run_if(in_state(AppState::GameOver)))
            .add_systems(Update, check_game_over.run_if(in_state(AppState::InGame)));
    }
}

#[derive(Component)]
struct MenuRoot;

#[derive(Resource)]
struct SelectedFaction(Option<Faction>);

#[derive(Resource)]
struct PlayerNameInput(String);

#[derive(Resource, Default)]
struct ShopState {
    message: String,
}

// Button identifiers
#[derive(Component)]
enum MenuButton {
    NewGame,
    LoadGame,
    ExitGame,
    SelectElves,
    SelectPalace,
    SelectDarkLord,
    ConfirmName,
    Resume,
    SaveGame,
    LoadSave,
    QuitToMenu,
    BuyItem(usize),
    SellItem(usize),
    CloseMenu,
    UseItem(usize),
    HealPlayer,
    SaveSlot(usize),
    LoadSlot(usize),
    BackToMainMenu,
}

fn menu_button(label: &str, action: MenuButton) -> impl Bundle {
    (
        Button,
        Node {
            width: Val::Px(300.0),
            height: Val::Px(45.0),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            margin: UiRect::all(Val::Px(4.0)),
            border_radius: BorderRadius::all(Val::Px(6.0)),
            ..default()
        },
        BackgroundColor(materials::UI_BUTTON),
        action,
        children![(
            Text::new(label),
            TextFont { font_size: 18.0, ..default() },
            TextColor(materials::UI_TEXT),
        )],
    )
}

fn menu_container() -> impl Bundle {
    (
        Node {
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            position_type: PositionType::Absolute,
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            flex_direction: FlexDirection::Column,
            ..default()
        },
        BackgroundColor(Color::srgba(0.05, 0.05, 0.1, 0.9)),
        MenuRoot,
    )
}

fn despawn_menu(mut commands: Commands, query: Query<Entity, With<MenuRoot>>) {
    for entity in &query {
        commands.entity(entity).despawn();
    }
}

// === Main Menu ===

fn spawn_main_menu(mut commands: Commands) {
    commands.spawn(menu_container()).with_children(|parent| {
        parent.spawn((
            Text::new("КОРОВАНЫ"),
            TextFont { font_size: 56.0, ..default() },
            TextColor(materials::UI_TITLE),
        ));
        parent.spawn((
            Text::new("3D Экшн-RPG"),
            TextFont { font_size: 20.0, ..default() },
            TextColor(materials::UI_TEXT),
            Node { margin: UiRect::bottom(Val::Px(30.0)), ..default() },
        ));
        parent.spawn(menu_button("Новая игра", MenuButton::NewGame));
        parent.spawn(menu_button("Загрузить", MenuButton::LoadGame));
        parent.spawn(menu_button("Выход", MenuButton::ExitGame));
    });
}

fn main_menu_buttons(
    mut next_state: ResMut<NextState<AppState>>,
    query: Query<(&Interaction, &MenuButton), Changed<Interaction>>,
    mut exit: MessageWriter<AppExit>,
    mut bg_query: Query<(&Interaction, &mut BackgroundColor), (Changed<Interaction>, With<Button>)>,
) {
    for (interaction, mut bg) in &mut bg_query {
        *bg = match *interaction {
            Interaction::Pressed => materials::UI_BUTTON_PRESS.into(),
            Interaction::Hovered => materials::UI_BUTTON_HOVER.into(),
            Interaction::None => materials::UI_BUTTON.into(),
        };
    }

    for (interaction, button) in &query {
        if *interaction != Interaction::Pressed { continue; }
        match button {
            MenuButton::NewGame => next_state.set(AppState::FactionSelect),
            MenuButton::LoadGame => next_state.set(AppState::SaveLoadMenu),
            MenuButton::ExitGame => { exit.write(AppExit::Success); }
            _ => {}
        }
    }
}

// === Faction Selection ===

fn spawn_faction_menu(mut commands: Commands) {
    commands.spawn(menu_container()).with_children(|parent| {
        parent.spawn((
            Text::new("ВЫБЕРИТЕ ФРАКЦИЮ"),
            TextFont { font_size: 36.0, ..default() },
            TextColor(materials::UI_TITLE),
            Node { margin: UiRect::bottom(Val::Px(20.0)), ..default() },
        ));

        // Elves
        parent.spawn(Node {
            flex_direction: FlexDirection::Column,
            align_items: AlignItems::Center,
            margin: UiRect::bottom(Val::Px(10.0)),
            ..default()
        }).with_children(|col| {
            col.spawn(menu_button("Лесные Эльфы", MenuButton::SelectElves));
            col.spawn((
                Text::new(Faction::Elves.description()),
                TextFont { font_size: 12.0, ..default() },
                TextColor(Color::srgb(0.6, 0.8, 0.6)),
                Node { max_width: Val::Px(350.0), ..default() },
            ));
        });

        // Palace
        parent.spawn(Node {
            flex_direction: FlexDirection::Column,
            align_items: AlignItems::Center,
            margin: UiRect::bottom(Val::Px(10.0)),
            ..default()
        }).with_children(|col| {
            col.spawn(menu_button("Охрана Дворца", MenuButton::SelectPalace));
            col.spawn((
                Text::new(Faction::Palace.description()),
                TextFont { font_size: 12.0, ..default() },
                TextColor(Color::srgb(0.8, 0.8, 0.6)),
                Node { max_width: Val::Px(350.0), ..default() },
            ));
        });

        // Dark Lord
        parent.spawn(Node {
            flex_direction: FlexDirection::Column,
            align_items: AlignItems::Center,
            margin: UiRect::bottom(Val::Px(10.0)),
            ..default()
        }).with_children(|col| {
            col.spawn(menu_button("Тёмный Властелин", MenuButton::SelectDarkLord));
            col.spawn((
                Text::new(Faction::DarkLord.description()),
                TextFont { font_size: 12.0, ..default() },
                TextColor(Color::srgb(0.8, 0.6, 0.8)),
                Node { max_width: Val::Px(350.0), ..default() },
            ));
        });
    });
}

fn faction_menu_buttons(
    mut next_state: ResMut<NextState<AppState>>,
    mut selected: ResMut<SelectedFaction>,
    query: Query<(&Interaction, &MenuButton), Changed<Interaction>>,
    mut bg_query: Query<(&Interaction, &mut BackgroundColor), (Changed<Interaction>, With<Button>)>,
) {
    for (interaction, mut bg) in &mut bg_query {
        *bg = match *interaction {
            Interaction::Pressed => materials::UI_BUTTON_PRESS.into(),
            Interaction::Hovered => materials::UI_BUTTON_HOVER.into(),
            Interaction::None => materials::UI_BUTTON.into(),
        };
    }

    for (interaction, button) in &query {
        if *interaction != Interaction::Pressed { continue; }
        match button {
            MenuButton::SelectElves => { selected.0 = Some(Faction::Elves); next_state.set(AppState::NameInput); }
            MenuButton::SelectPalace => { selected.0 = Some(Faction::Palace); next_state.set(AppState::NameInput); }
            MenuButton::SelectDarkLord => { selected.0 = Some(Faction::DarkLord); next_state.set(AppState::NameInput); }
            _ => {}
        }
    }
}

// === Name Input ===

#[derive(Component)]
struct NameInputDisplay;

fn spawn_name_input(mut commands: Commands, name: Res<PlayerNameInput>) {
    commands.spawn(menu_container()).with_children(|parent| {
        parent.spawn((
            Text::new("ВВЕДИТЕ ИМЯ ПЕРСОНАЖА"),
            TextFont { font_size: 30.0, ..default() },
            TextColor(materials::UI_TITLE),
            Node { margin: UiRect::bottom(Val::Px(20.0)), ..default() },
        ));
        parent.spawn((
            Text::new("(Введите имя и нажмите Enter)"),
            TextFont { font_size: 14.0, ..default() },
            TextColor(materials::UI_TEXT),
        ));
        parent.spawn((
            Node {
                width: Val::Px(300.0),
                height: Val::Px(40.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                margin: UiRect::vertical(Val::Px(15.0)),
                border_radius: BorderRadius::all(Val::Px(4.0)),
                ..default()
            },
            BackgroundColor(Color::srgb(0.15, 0.15, 0.2)),
        )).with_children(|input| {
            input.spawn((
                Text::new(format!(">{}<", name.0)),
                TextFont { font_size: 22.0, ..default() },
                TextColor(materials::UI_TITLE),
                NameInputDisplay,
            ));
        });
        parent.spawn(menu_button("Начать игру", MenuButton::ConfirmName));
    });
}

fn name_input_system(
    mut commands: Commands,
    mut next_state: ResMut<NextState<AppState>>,
    mut name: ResMut<PlayerNameInput>,
    selected: Res<SelectedFaction>,
    mut char_events: MessageReader<bevy::input::keyboard::KeyboardInput>,
    mut display_q: Query<&mut Text, With<NameInputDisplay>>,
    query: Query<(&Interaction, &MenuButton), Changed<Interaction>>,
    mut bg_query: Query<(&Interaction, &mut BackgroundColor), (Changed<Interaction>, With<Button>)>,
) {
    for (interaction, mut bg) in &mut bg_query {
        *bg = match *interaction {
            Interaction::Pressed => materials::UI_BUTTON_PRESS.into(),
            Interaction::Hovered => materials::UI_BUTTON_HOVER.into(),
            Interaction::None => materials::UI_BUTTON.into(),
        };
    }

    // Handle text input
    for ev in char_events.read() {
        if ev.state != bevy::input::ButtonState::Pressed { continue; }
        match ev.key_code {
            KeyCode::Backspace => { name.0.pop(); }
            KeyCode::Enter => {
                start_game(&mut commands, &mut next_state, &name, &selected);
                return;
            }
            _ => {
                if let Some(ref text) = ev.text {
                    let c: &str = text.as_str();
                    if !c.is_empty() && name.0.len() < 20 {
                        // Filter out control chars
                        let ch: String = c.chars().filter(|ch: &char| !ch.is_control()).collect();
                        name.0.push_str(&ch);
                    }
                }
            }
        }
    }

    if let Ok(mut text) = display_q.single_mut() {
        **text = format!(">{}<", name.0);
    }

    // Button click
    for (interaction, button) in &query {
        if *interaction != Interaction::Pressed { continue; }
        if matches!(button, MenuButton::ConfirmName) {
            start_game(&mut commands, &mut next_state, &name, &selected);
        }
    }
}

fn start_game(
    commands: &mut Commands,
    next_state: &mut ResMut<NextState<AppState>>,
    name: &PlayerNameInput,
    selected: &SelectedFaction,
) {
    let faction = selected.0.unwrap_or(Faction::Elves);
    let player_name = if name.0.is_empty() { "Герой".to_string() } else { name.0.clone() };
    let player = Player::new(player_name, faction);
    let locations = build_world();
    let game_state = GameState {
        player,
        locations,
        caravans: Vec::new(),
        messages: Vec::new(),
        game_over: false,
        victory: false,
    };
    commands.insert_resource(game_state);
    next_state.set(AppState::InGame);
}

// === Pause Menu ===

fn pause_key(
    input: Res<ButtonInput<KeyCode>>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    if input.just_pressed(KeyCode::Escape) {
        next_state.set(AppState::Paused);
    }
}

fn spawn_pause_menu(mut commands: Commands) {
    commands.spawn(menu_container()).with_children(|parent| {
        parent.spawn((
            Text::new("ПАУЗА"),
            TextFont { font_size: 40.0, ..default() },
            TextColor(materials::UI_TITLE),
            Node { margin: UiRect::bottom(Val::Px(20.0)), ..default() },
        ));
        parent.spawn(menu_button("Продолжить", MenuButton::Resume));
        parent.spawn(menu_button("Сохранить", MenuButton::SaveGame));
        parent.spawn(menu_button("Загрузить", MenuButton::LoadSave));
        parent.spawn(menu_button("В главное меню", MenuButton::QuitToMenu));
    });
}

fn pause_menu_buttons(
    mut next_state: ResMut<NextState<AppState>>,
    input: Res<ButtonInput<KeyCode>>,
    query: Query<(&Interaction, &MenuButton), Changed<Interaction>>,
    mut bg_query: Query<(&Interaction, &mut BackgroundColor), (Changed<Interaction>, With<Button>)>,
) {
    for (interaction, mut bg) in &mut bg_query {
        *bg = match *interaction {
            Interaction::Pressed => materials::UI_BUTTON_PRESS.into(),
            Interaction::Hovered => materials::UI_BUTTON_HOVER.into(),
            Interaction::None => materials::UI_BUTTON.into(),
        };
    }

    if input.just_pressed(KeyCode::Escape) {
        next_state.set(AppState::InGame);
        return;
    }

    for (interaction, button) in &query {
        if *interaction != Interaction::Pressed { continue; }
        match button {
            MenuButton::Resume => next_state.set(AppState::InGame),
            MenuButton::SaveGame | MenuButton::LoadSave => next_state.set(AppState::SaveLoadMenu),
            MenuButton::QuitToMenu => next_state.set(AppState::MainMenu),
            _ => {}
        }
    }
}

// === Shop ===

fn shop_open_key(
    input: Res<ButtonInput<KeyCode>>,
    game_state: Res<GameState>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    if input.just_pressed(KeyCode::KeyE) && game_state.player.location.has_shop() {
        next_state.set(AppState::ShopOpen);
    }
}

fn spawn_shop_menu(
    mut commands: Commands,
    game_state: Res<GameState>,
    mut shop_state: ResMut<ShopState>,
) {
    let items = shop_items_for(game_state.player.location);
    shop_state.message.clear();

    commands.spawn(menu_container()).with_children(|parent| {
        parent.spawn((
            Text::new(format!("МАГАЗИН — {}", game_state.player.location.name())),
            TextFont { font_size: 28.0, ..default() },
            TextColor(materials::UI_TITLE),
            Node { margin: UiRect::bottom(Val::Px(10.0)), ..default() },
        ));
        parent.spawn((
            Text::new(format!("Золото: {}", game_state.player.gold)),
            TextFont { font_size: 16.0, ..default() },
            TextColor(materials::UI_TEXT),
            Node { margin: UiRect::bottom(Val::Px(10.0)), ..default() },
        ));

        // Buy section
        parent.spawn(Node {
            flex_direction: FlexDirection::Row,
            width: Val::Percent(90.0),
            justify_content: JustifyContent::SpaceAround,
            ..default()
        }).with_children(|row| {
            // Buy column
            row.spawn(Node {
                flex_direction: FlexDirection::Column,
                width: Val::Percent(45.0),
                max_height: Val::Px(350.0),
                overflow: Overflow::clip_y(),
                ..default()
            }).with_children(|col| {
                col.spawn((
                    Text::new("КУПИТЬ"),
                    TextFont { font_size: 18.0, ..default() },
                    TextColor(materials::UI_TEXT),
                ));
                for (i, item) in items.iter().enumerate() {
                    col.spawn((
                        Button,
                        Node {
                            width: Val::Percent(100.0),
                            height: Val::Px(30.0),
                            justify_content: JustifyContent::Center,
                            align_items: AlignItems::Center,
                            margin: UiRect::vertical(Val::Px(2.0)),
                            ..default()
                        },
                        BackgroundColor(materials::UI_BUTTON),
                        MenuButton::BuyItem(i),
                        children![(
                            Text::new(format!("{} — {} зол.", item.name, item.price)),
                            TextFont { font_size: 13.0, ..default() },
                            TextColor(materials::UI_TEXT),
                        )],
                    ));
                }
            });

            // Sell column
            row.spawn(Node {
                flex_direction: FlexDirection::Column,
                width: Val::Percent(45.0),
                max_height: Val::Px(350.0),
                overflow: Overflow::clip_y(),
                ..default()
            }).with_children(|col| {
                col.spawn((
                    Text::new("ПРОДАТЬ"),
                    TextFont { font_size: 18.0, ..default() },
                    TextColor(materials::UI_TEXT),
                ));
                for (i, item) in game_state.player.inventory.iter().enumerate() {
                    col.spawn((
                        Button,
                        Node {
                            width: Val::Percent(100.0),
                            height: Val::Px(30.0),
                            justify_content: JustifyContent::Center,
                            align_items: AlignItems::Center,
                            margin: UiRect::vertical(Val::Px(2.0)),
                            ..default()
                        },
                        BackgroundColor(materials::UI_BUTTON),
                        MenuButton::SellItem(i),
                        children![(
                            Text::new(format!("{} — {} зол.", item.name, item.price / 2)),
                            TextFont { font_size: 13.0, ..default() },
                            TextColor(materials::UI_TEXT),
                        )],
                    ));
                }
            });
        });

        parent.spawn(menu_button("Закрыть [Esc]", MenuButton::CloseMenu));
    });
}

fn shop_menu_buttons(
    mut commands: Commands,
    mut next_state: ResMut<NextState<AppState>>,
    input: Res<ButtonInput<KeyCode>>,
    mut game_state: ResMut<GameState>,
    query: Query<(&Interaction, &MenuButton), Changed<Interaction>>,
    menu_q: Query<Entity, With<MenuRoot>>,
    mut bg_query: Query<(&Interaction, &mut BackgroundColor), (Changed<Interaction>, With<Button>)>,
) {
    for (interaction, mut bg) in &mut bg_query {
        *bg = match *interaction {
            Interaction::Pressed => materials::UI_BUTTON_PRESS.into(),
            Interaction::Hovered => materials::UI_BUTTON_HOVER.into(),
            Interaction::None => materials::UI_BUTTON.into(),
        };
    }

    if input.just_pressed(KeyCode::Escape) {
        next_state.set(AppState::InGame);
        return;
    }

    let mut needs_refresh = false;
    for (interaction, button) in &query {
        if *interaction != Interaction::Pressed { continue; }
        match button {
            MenuButton::BuyItem(i) => {
                let items = shop_items_for(game_state.player.location);
                let _msg = trade::buy_item(&mut game_state.player, &items, *i);
                needs_refresh = true;
            }
            MenuButton::SellItem(i) => {
                let _msg = trade::sell_item(&mut game_state.player, *i);
                needs_refresh = true;
            }
            MenuButton::CloseMenu => { next_state.set(AppState::InGame); }
            _ => {}
        }
    }

    if needs_refresh {
        // Rebuild shop UI
        for entity in &menu_q {
            commands.entity(entity).despawn();
        }
        // Re-enter shop state to rebuild
        next_state.set(AppState::ShopOpen);
    }
}

// === Inventory ===

fn inventory_key(
    input: Res<ButtonInput<KeyCode>>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    if input.just_pressed(KeyCode::Tab) {
        next_state.set(AppState::InventoryOpen);
    }
}

fn spawn_inventory_menu(mut commands: Commands, game_state: Res<GameState>) {
    commands.spawn(menu_container()).with_children(|parent| {
        parent.spawn((
            Text::new("ИНВЕНТАРЬ"),
            TextFont { font_size: 30.0, ..default() },
            TextColor(materials::UI_TITLE),
            Node { margin: UiRect::bottom(Val::Px(10.0)), ..default() },
        ));

        let p = &game_state.player;

        // Equipment info
        let weapon_name = p.weapon.as_ref().map_or("Нет", |w| w.name.as_str());
        let armor_name = p.armor.as_ref().map_or("Нет", |a| a.name.as_str());
        parent.spawn((
            Text::new(format!("Оружие: {} | Броня: {}", weapon_name, armor_name)),
            TextFont { font_size: 14.0, ..default() },
            TextColor(materials::UI_TEXT),
            Node { margin: UiRect::bottom(Val::Px(10.0)), ..default() },
        ));

        parent.spawn(Node {
            flex_direction: FlexDirection::Column,
            max_height: Val::Px(350.0),
            overflow: Overflow::clip_y(),
            ..default()
        }).with_children(|col| {
            if p.inventory.is_empty() {
                col.spawn((
                    Text::new("Инвентарь пуст"),
                    TextFont { font_size: 14.0, ..default() },
                    TextColor(materials::UI_TEXT),
                ));
            }
            for (i, item) in p.inventory.iter().enumerate() {
                let label = match item.item_type {
                    ItemType::Weapon => format!("{} (Атк:{})", item.name, item.power),
                    ItemType::Armor => format!("{} (Защ:{})", item.name, item.power),
                    ItemType::HealingPotion | ItemType::Food => format!("{} (HP+{})", item.name, item.heal_amount),
                    _ => item.name.clone(),
                };
                col.spawn((
                    Button,
                    Node {
                        width: Val::Px(350.0),
                        height: Val::Px(30.0),
                        justify_content: JustifyContent::Center,
                        align_items: AlignItems::Center,
                        margin: UiRect::vertical(Val::Px(2.0)),
                        ..default()
                    },
                    BackgroundColor(materials::UI_BUTTON),
                    MenuButton::UseItem(i),
                    children![(
                        Text::new(label),
                        TextFont { font_size: 13.0, ..default() },
                        TextColor(materials::UI_TEXT),
                    )],
                ));
            }
        });

        parent.spawn(menu_button("Закрыть [Tab]", MenuButton::CloseMenu));
    });
}

fn inventory_buttons(
    mut commands: Commands,
    mut next_state: ResMut<NextState<AppState>>,
    input: Res<ButtonInput<KeyCode>>,
    mut game_state: ResMut<GameState>,
    query: Query<(&Interaction, &MenuButton), Changed<Interaction>>,
    menu_q: Query<Entity, With<MenuRoot>>,
    mut bg_query: Query<(&Interaction, &mut BackgroundColor), (Changed<Interaction>, With<Button>)>,
) {
    for (interaction, mut bg) in &mut bg_query {
        *bg = match *interaction {
            Interaction::Pressed => materials::UI_BUTTON_PRESS.into(),
            Interaction::Hovered => materials::UI_BUTTON_HOVER.into(),
            Interaction::None => materials::UI_BUTTON.into(),
        };
    }

    if input.just_pressed(KeyCode::Tab) || input.just_pressed(KeyCode::Escape) {
        next_state.set(AppState::InGame);
        return;
    }

    let mut needs_refresh = false;
    for (interaction, button) in &query {
        if *interaction != Interaction::Pressed { continue; }
        match button {
            MenuButton::UseItem(i) => {
                let _msg = game_state.player.use_item(*i);
                needs_refresh = true;
            }
            MenuButton::CloseMenu => { next_state.set(AppState::InGame); }
            _ => {}
        }
    }

    if needs_refresh {
        for entity in &menu_q {
            commands.entity(entity).despawn();
        }
        next_state.set(AppState::InventoryOpen);
    }
}

// === Healer ===

fn healer_key(
    input: Res<ButtonInput<KeyCode>>,
    game_state: Res<GameState>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    if input.just_pressed(KeyCode::KeyH) && game_state.player.location.has_healer() {
        next_state.set(AppState::HealerOpen);
    }
}

fn spawn_healer_menu(mut commands: Commands, game_state: Res<GameState>) {
    commands.spawn(menu_container()).with_children(|parent| {
        parent.spawn((
            Text::new("ЛЕКАРЬ"),
            TextFont { font_size: 30.0, ..default() },
            TextColor(materials::UI_TITLE),
            Node { margin: UiRect::bottom(Val::Px(10.0)), ..default() },
        ));
        parent.spawn((
            Text::new(format!(
                "HP: {}/{} | Золото: {} | Стоимость лечения: {}",
                game_state.player.health, game_state.player.max_health,
                game_state.player.gold, healer_price()
            )),
            TextFont { font_size: 14.0, ..default() },
            TextColor(materials::UI_TEXT),
            Node { margin: UiRect::bottom(Val::Px(10.0)), ..default() },
        ));

        // Show injuries
        for line in game_state.player.injuries.injury_summary() {
            parent.spawn((
                Text::new(line),
                TextFont { font_size: 13.0, ..default() },
                TextColor(Color::srgb(1.0, 0.4, 0.3)),
            ));
        }

        parent.spawn(menu_button("Лечиться (25 зол.)", MenuButton::HealPlayer));
        parent.spawn(menu_button("Закрыть", MenuButton::CloseMenu));
    });
}

fn healer_buttons(
    mut commands: Commands,
    mut next_state: ResMut<NextState<AppState>>,
    input: Res<ButtonInput<KeyCode>>,
    mut game_state: ResMut<GameState>,
    query: Query<(&Interaction, &MenuButton), Changed<Interaction>>,
    menu_q: Query<Entity, With<MenuRoot>>,
    mut bg_query: Query<(&Interaction, &mut BackgroundColor), (Changed<Interaction>, With<Button>)>,
) {
    for (interaction, mut bg) in &mut bg_query {
        *bg = match *interaction {
            Interaction::Pressed => materials::UI_BUTTON_PRESS.into(),
            Interaction::Hovered => materials::UI_BUTTON_HOVER.into(),
            Interaction::None => materials::UI_BUTTON.into(),
        };
    }

    if input.just_pressed(KeyCode::Escape) {
        next_state.set(AppState::InGame);
        return;
    }

    let mut needs_refresh = false;
    for (interaction, button) in &query {
        if *interaction != Interaction::Pressed { continue; }
        match button {
            MenuButton::HealPlayer => {
                let _msg = trade::heal_at_healer(&mut game_state.player);
                needs_refresh = true;
            }
            MenuButton::CloseMenu => { next_state.set(AppState::InGame); }
            _ => {}
        }
    }

    if needs_refresh {
        for entity in &menu_q {
            commands.entity(entity).despawn();
        }
        next_state.set(AppState::HealerOpen);
    }
}

// === Save/Load ===

fn spawn_save_load_menu(mut commands: Commands) {
    let saves = save::list_saves();

    commands.spawn(menu_container()).with_children(|parent| {
        parent.spawn((
            Text::new("СОХРАНЕНИЕ / ЗАГРУЗКА"),
            TextFont { font_size: 30.0, ..default() },
            TextColor(materials::UI_TITLE),
            Node { margin: UiRect::bottom(Val::Px(15.0)), ..default() },
        ));

        for (slot, exists) in &saves {
            let status = if *exists { "Занят" } else { "Пусто" };
            parent.spawn(Node {
                flex_direction: FlexDirection::Row,
                margin: UiRect::vertical(Val::Px(4.0)),
                ..default()
            }).with_children(|row| {
                row.spawn((
                    Text::new(format!("Слот {} [{}]", slot, status)),
                    TextFont { font_size: 16.0, ..default() },
                    TextColor(materials::UI_TEXT),
                    Node {
                        width: Val::Px(150.0),
                        align_self: AlignSelf::Center,
                        ..default()
                    },
                ));
                row.spawn((
                    Button,
                    Node {
                        width: Val::Px(120.0),
                        height: Val::Px(35.0),
                        justify_content: JustifyContent::Center,
                        align_items: AlignItems::Center,
                        margin: UiRect::horizontal(Val::Px(5.0)),
                        ..default()
                    },
                    BackgroundColor(materials::UI_BUTTON),
                    MenuButton::SaveSlot(*slot),
                    children![(
                        Text::new("Сохранить"),
                        TextFont { font_size: 14.0, ..default() },
                        TextColor(materials::UI_TEXT),
                    )],
                ));
                if *exists {
                    row.spawn((
                        Button,
                        Node {
                            width: Val::Px(120.0),
                            height: Val::Px(35.0),
                            justify_content: JustifyContent::Center,
                            align_items: AlignItems::Center,
                            margin: UiRect::horizontal(Val::Px(5.0)),
                            ..default()
                        },
                        BackgroundColor(materials::UI_BUTTON),
                        MenuButton::LoadSlot(*slot),
                        children![(
                            Text::new("Загрузить"),
                            TextFont { font_size: 14.0, ..default() },
                            TextColor(materials::UI_TEXT),
                        )],
                    ));
                }
            });
        }

        parent.spawn(menu_button("Назад", MenuButton::CloseMenu));
    });
}

fn save_load_buttons(
    mut commands: Commands,
    mut next_state: ResMut<NextState<AppState>>,
    input: Res<ButtonInput<KeyCode>>,
    game_state: Option<Res<GameState>>,
    query: Query<(&Interaction, &MenuButton), Changed<Interaction>>,
    mut bg_query: Query<(&Interaction, &mut BackgroundColor), (Changed<Interaction>, With<Button>)>,
) {
    for (interaction, mut bg) in &mut bg_query {
        *bg = match *interaction {
            Interaction::Pressed => materials::UI_BUTTON_PRESS.into(),
            Interaction::Hovered => materials::UI_BUTTON_HOVER.into(),
            Interaction::None => materials::UI_BUTTON.into(),
        };
    }

    if input.just_pressed(KeyCode::Escape) {
        // Return to previous state
        if game_state.is_some() {
            next_state.set(AppState::Paused);
        } else {
            next_state.set(AppState::MainMenu);
        }
        return;
    }

    for (interaction, button) in &query {
        if *interaction != Interaction::Pressed { continue; }
        match button {
            MenuButton::SaveSlot(slot) => {
                if let Some(ref gs) = game_state {
                    let _ = save::save_game(gs, *slot);
                }
            }
            MenuButton::LoadSlot(slot) => {
                match save::load_game(*slot) {
                    Ok(gs) => {
                        commands.insert_resource(gs);
                        next_state.set(AppState::InGame);
                    }
                    Err(_) => {}
                }
            }
            MenuButton::CloseMenu => {
                if game_state.is_some() {
                    next_state.set(AppState::Paused);
                } else {
                    next_state.set(AppState::MainMenu);
                }
            }
            _ => {}
        }
    }
}

// === Game Over ===

fn check_game_over(
    game_state: Res<GameState>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    if game_state.game_over || !game_state.player.is_alive() {
        next_state.set(AppState::GameOver);
    }
}

fn spawn_game_over(mut commands: Commands, game_state: Option<Res<GameState>>) {
    commands.spawn(menu_container()).with_children(|parent| {
        parent.spawn((
            Text::new("ИГРА ОКОНЧЕНА"),
            TextFont { font_size: 48.0, ..default() },
            TextColor(Color::srgb(0.9, 0.2, 0.2)),
            Node { margin: UiRect::bottom(Val::Px(20.0)), ..default() },
        ));

        if let Some(gs) = &game_state {
            parent.spawn((
                Text::new(format!(
                    "Уровень: {} | Золото: {} | Ходов: {}",
                    gs.player.level, gs.player.gold, gs.player.turn_count
                )),
                TextFont { font_size: 16.0, ..default() },
                TextColor(materials::UI_TEXT),
                Node { margin: UiRect::bottom(Val::Px(20.0)), ..default() },
            ));
        }

        parent.spawn(menu_button("В главное меню", MenuButton::BackToMainMenu));
    });
}

fn game_over_buttons(
    mut next_state: ResMut<NextState<AppState>>,
    query: Query<(&Interaction, &MenuButton), Changed<Interaction>>,
    mut bg_query: Query<(&Interaction, &mut BackgroundColor), (Changed<Interaction>, With<Button>)>,
) {
    for (interaction, mut bg) in &mut bg_query {
        *bg = match *interaction {
            Interaction::Pressed => materials::UI_BUTTON_PRESS.into(),
            Interaction::Hovered => materials::UI_BUTTON_HOVER.into(),
            Interaction::None => materials::UI_BUTTON.into(),
        };
    }

    for (interaction, button) in &query {
        if *interaction != Interaction::Pressed { continue; }
        if matches!(button, MenuButton::BackToMainMenu) {
            next_state.set(AppState::MainMenu);
        }
    }
}
