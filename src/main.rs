use avian3d::prelude::*;
use bevy::prelude::*;
use bevy::text::CosmicFontSystem;
use bevy::window::WindowResolution;

mod app_state;
mod camera;
mod character;
mod combat;
mod combat3d;
mod controller;
mod events;
mod hud;
mod materials;
mod npc_ai;
mod player;
mod save;
mod trade;
mod types;
mod ui_menus;
mod world;
mod world3d;

use app_state::AppState;

fn main() {
    App::new()
        // Load system fonts (for Cyrillic support)
        .insert_resource(CosmicFontSystem(cosmic_text::FontSystem::new()))
        .add_plugins((
            DefaultPlugins.set(WindowPlugin {
                primary_window: Some(Window {
                    title: "КОРОВАНЫ — 3D Экшн-RPG".into(),
                    resolution: WindowResolution::new(1280, 720),
                    ..default()
                }),
                ..default()
            }),
            PhysicsPlugins::default(),
        ))
        .init_state::<AppState>()
        .add_systems(Startup, spawn_ui_camera)
        .add_plugins((
            world3d::World3dPlugin,
            camera::CameraPlugin,
            character::CharacterPlugin,
            controller::ControllerPlugin,
            combat3d::Combat3dPlugin,
            npc_ai::NpcAiPlugin,
            hud::HudPlugin,
            ui_menus::UiMenusPlugin,
        ))
        .add_systems(OnEnter(AppState::InGame), (setup_world_events, despawn_ui_camera))
        .add_systems(
            Update,
            (caravan_spawn_timer, faction_turn_timer, random_encounter_timer, faction_action_input)
                .run_if(in_state(AppState::InGame)),
        )
        .add_systems(OnExit(AppState::InGame), (cleanup_3d_world, spawn_ui_camera))
        .run();
}

#[derive(Component)]
struct UiCamera;

fn spawn_ui_camera(mut commands: Commands) {
    commands.spawn((
        Camera2d,
        UiCamera,
    ));
}

fn despawn_ui_camera(mut commands: Commands, query: Query<Entity, With<UiCamera>>) {
    for entity in &query {
        commands.entity(entity).despawn();
    }
}

#[derive(Resource)]
struct CaravanTimer(Timer);

#[derive(Resource)]
struct FactionTurnTimer(Timer);

#[derive(Resource)]
struct EncounterTimer(Timer);

fn setup_world_events(mut commands: Commands) {
    commands.insert_resource(CaravanTimer(Timer::from_seconds(30.0, TimerMode::Repeating)));
    commands.insert_resource(FactionTurnTimer(Timer::from_seconds(45.0, TimerMode::Repeating)));
    commands.insert_resource(EncounterTimer(Timer::from_seconds(20.0, TimerMode::Repeating)));
}

fn caravan_spawn_timer(
    time: Res<Time>,
    mut timer: ResMut<CaravanTimer>,
    mut game_state: ResMut<types::GameState>,
    mut combat_msgs: MessageWriter<combat3d::CombatMessage>,
    mut commands: Commands,
    existing_q: Query<Entity, With<CaravanEntity>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
) {
    timer.0.tick(time.delta());
    if !timer.0.just_finished() {
        return;
    }

    game_state.move_caravans();
    game_state.spawn_caravan();
    for entity in &existing_q {
        commands.entity(entity).despawn();
    }
    for (idx, caravan) in game_state.caravans.iter().enumerate() {
        let pos = world3d::location_position(caravan.location);
        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(3.0, 2.0, 5.0))),
            MeshMaterial3d(mats.add(StandardMaterial {
                base_color: materials::CARAVAN_COLOR,
                ..default()
            })),
            Transform::from_translation(pos + Vec3::Y * 1.0),
            RigidBody::Static,
            Collider::cuboid(3.0, 2.0, 5.0),
            CaravanEntity { caravan_index: idx },
        ));
    }

    game_state.player.turn_count += 1;
    combat_msgs.write(combat3d::CombatMessage {
        text: format!("Корованы двигаются... (ход {})", game_state.player.turn_count),
        color: Color::srgb(0.7, 0.7, 0.5),
    });
}

#[derive(Component)]
pub struct CaravanEntity {
    pub caravan_index: usize,
}

fn faction_turn_timer(
    time: Res<Time>,
    mut timer: ResMut<FactionTurnTimer>,
    mut game_state: ResMut<types::GameState>,
    mut combat_msgs: MessageWriter<combat3d::CombatMessage>,
) {
    timer.0.tick(time.delta());
    if !timer.0.just_finished() {
        return;
    }

    let messages = events::process_faction_turn(&mut game_state);
    for msg in messages {
        combat_msgs.write(combat3d::CombatMessage {
            text: msg,
            color: Color::srgb(0.6, 0.8, 1.0),
        });
    }
}

fn random_encounter_timer(
    time: Res<Time>,
    mut timer: ResMut<EncounterTimer>,
    mut game_state: ResMut<types::GameState>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
    mut combat_msgs: MessageWriter<combat3d::CombatMessage>,
) {
    timer.0.tick(time.delta());
    if !timer.0.just_finished() {
        return;
    }

    let npcs_before: usize = game_state.locations.iter().map(|l| l.npcs.len()).sum();
    game_state.maybe_spawn_random_encounter();
    let npcs_after: usize = game_state.locations.iter().map(|l| l.npcs.len()).sum();

    if npcs_after > npcs_before {
        // Find the new NPC and spawn its 3D entity
        let player_loc = game_state.player.location;
        if let Some(loc) = game_state.find_location(player_loc) {
            if let Some(npc) = loc.npcs.last() {
                let pos = world3d::location_position(player_loc);
                let mut rng = rand::thread_rng();
                use rand::Rng;
                let offset = Vec3::new(
                    rng.gen_range(-8.0..8.0),
                    1.5,
                    rng.gen_range(-8.0..8.0),
                );

                let color = match npc.npc_type {
                    types::NpcType::Bandit => materials::BANDIT_COLOR,
                    types::NpcType::Beast => materials::BEAST_COLOR,
                    _ => materials::BANDIT_COLOR,
                };

                commands.spawn((
                    Mesh3d(meshes.add(Capsule3d::new(0.35, 1.0))),
                    MeshMaterial3d(mats.add(StandardMaterial {
                        base_color: color,
                        ..default()
                    })),
                    Transform::from_translation(pos + offset),
                    RigidBody::Dynamic,
                    Collider::capsule(0.35, 1.0),
                    LockedAxes::ROTATION_LOCKED,
                    LinearDamping(8.0),
                    character::NpcEntity,
                    character::NpcHealth {
                        current: npc.health,
                        max: npc.max_health,
                        attack: npc.attack,
                        defense: npc.defense,
                        gold: npc.gold,
                        npc_type: npc.npc_type,
                        name: npc.name.clone(),
                    },
                    character::HostileNpc,
                ));

                combat_msgs.write(combat3d::CombatMessage {
                    text: format!("{} появился рядом!", npc.name),
                    color: Color::srgb(1.0, 0.5, 0.3),
                });
            }
        }
    }
}

fn faction_action_input(
    input: Res<ButtonInput<KeyCode>>,
    mut game_state: ResMut<types::GameState>,
    mut combat_msgs: MessageWriter<combat3d::CombatMessage>,
) {
    if !input.just_pressed(KeyCode::KeyM) {
        return;
    }

    let messages = events::perform_faction_action(&mut game_state);
    for msg in messages {
        combat_msgs.write(combat3d::CombatMessage {
            text: msg,
            color: Color::srgb(0.7, 0.9, 1.0),
        });
    }
}

fn cleanup_3d_world(
    mut commands: Commands,
    query: Query<Entity, Or<(
        With<character::PlayerEntity>,
        With<character::NpcEntity>,
        With<world3d::ZoneGround>,
        With<world3d::Wall>,
        With<world3d::ZoneTrigger>,
        With<world3d::TreeEntity>,
        With<world3d::TreeLodPair>,
        With<CaravanEntity>,
        With<combat3d::LootDrop>,
        With<camera::OrbitCamera>,
    )>>,
) {
    for entity in &query {
        commands.entity(entity).despawn();
    }
}
