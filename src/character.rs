use avian3d::prelude::*;
use bevy::prelude::*;
use crate::app_state::AppState;
use crate::materials;
use crate::types::*;
use crate::world3d::location_position;

// Marker components
#[derive(Component)]
pub struct PlayerEntity;

#[derive(Component)]
pub struct NpcEntity;

#[derive(Component)]
pub struct MerchantNpc;

#[derive(Component)]
pub struct HostileNpc;

#[derive(Component)]
pub struct NpcHealth {
    pub current: i32,
    pub max: i32,
    pub attack: i32,
    pub defense: i32,
    pub gold: i32,
    pub npc_type: NpcType,
    pub name: String,
}

#[derive(Component)]
pub struct Limb;

#[derive(Component)]
pub struct WeaponVisual;

pub struct CharacterPlugin;

impl Plugin for CharacterPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(AppState::InGame), spawn_characters);
    }
}

fn faction_color(faction: Faction) -> Color {
    match faction {
        Faction::Elves => materials::ELF_COLOR,
        Faction::Palace => materials::PALACE_GUARD_COLOR,
        Faction::DarkLord => materials::DARK_LORD_COLOR,
    }
}

fn npc_type_color(npc_type: NpcType) -> Color {
    match npc_type {
        NpcType::Bandit => materials::BANDIT_COLOR,
        NpcType::ImperialSoldier => materials::IMPERIAL_COLOR,
        NpcType::ElfWarrior => materials::ELF_WARRIOR_COLOR,
        NpcType::DarkSoldier => materials::DARK_SOLDIER_COLOR,
        NpcType::Beast => materials::BEAST_COLOR,
        NpcType::CaravanGuard => materials::CARAVAN_GUARD_COLOR,
        NpcType::Commander => materials::COMMANDER_COLOR,
        NpcType::Merchant => materials::MERCHANT_COLOR,
    }
}

fn spawn_characters(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
    game_state: Res<GameState>,
) {
    let player = &game_state.player;
    let start_pos = location_position(player.location);

    // Spawn player capsule with limbs
    let body_mesh = meshes.add(Capsule3d::new(0.4, 1.2));
    let body_mat = mats.add(StandardMaterial {
        base_color: faction_color(player.faction),
        ..default()
    });

    let arm_mesh = meshes.add(Cuboid::new(0.15, 0.6, 0.15));
    let leg_mesh = meshes.add(Cuboid::new(0.18, 0.7, 0.18));
    let head_mesh = meshes.add(Sphere::new(0.25));
    let limb_mat = mats.add(StandardMaterial {
        base_color: Color::srgb(0.85, 0.7, 0.55),
        ..default()
    });

    // Weapon visual
    let weapon_mesh = meshes.add(Cuboid::new(0.08, 0.8, 0.08));
    let weapon_mat = mats.add(StandardMaterial {
        base_color: Color::srgb(0.6, 0.6, 0.65),
        metallic: 0.8,
        ..default()
    });

    commands.spawn((
        Mesh3d(body_mesh),
        MeshMaterial3d(body_mat),
        Transform::from_translation(start_pos + Vec3::Y * 1.5),
        RigidBody::Dynamic,
        Collider::capsule(0.4, 1.2),
        LockedAxes::ROTATION_LOCKED,
        LinearDamping(5.0),
        PlayerEntity,
    )).with_children(|parent| {
        // Head
        parent.spawn((
            Mesh3d(head_mesh.clone()),
            MeshMaterial3d(limb_mat.clone()),
            Transform::from_xyz(0.0, 0.9, 0.0),
            Limb,
        ));
        // Left arm
        parent.spawn((
            Mesh3d(arm_mesh.clone()),
            MeshMaterial3d(limb_mat.clone()),
            Transform::from_xyz(-0.55, 0.2, 0.0),
            Limb,
        ));
        // Right arm
        parent.spawn((
            Mesh3d(arm_mesh.clone()),
            MeshMaterial3d(limb_mat.clone()),
            Transform::from_xyz(0.55, 0.2, 0.0),
            Limb,
        ));
        // Weapon (attached to right hand)
        parent.spawn((
            Mesh3d(weapon_mesh),
            MeshMaterial3d(weapon_mat),
            Transform::from_xyz(0.55, -0.2, 0.3),
            WeaponVisual,
        ));
        // Left leg
        parent.spawn((
            Mesh3d(leg_mesh.clone()),
            MeshMaterial3d(limb_mat.clone()),
            Transform::from_xyz(-0.2, -0.9, 0.0),
            Limb,
        ));
        // Right leg
        parent.spawn((
            Mesh3d(leg_mesh),
            MeshMaterial3d(limb_mat),
            Transform::from_xyz(0.2, -0.9, 0.0),
            Limb,
        ));
    });

    // Spawn NPCs from world data
    for location in &game_state.locations {
        let loc_pos = location_position(location.id);
        for (i, npc) in location.npcs.iter().enumerate() {
            let npc_color = npc_type_color(npc.npc_type);
            let offset = Vec3::new(
                (i as f32 * 3.7).sin() * 5.0,
                1.5,
                (i as f32 * 2.3).cos() * 5.0,
            );

            let npc_body = meshes.add(Capsule3d::new(0.35, 1.0));
            let npc_mat = mats.add(StandardMaterial {
                base_color: npc_color,
                ..default()
            });

            let mut entity_cmds = commands.spawn((
                Mesh3d(npc_body),
                MeshMaterial3d(npc_mat),
                Transform::from_translation(loc_pos + offset),
                RigidBody::Dynamic,
                Collider::capsule(0.35, 1.0),
                LockedAxes::ROTATION_LOCKED,
                LinearDamping(8.0),
                NpcEntity,
                NpcHealth {
                    current: npc.health,
                    max: npc.max_health,
                    attack: npc.attack,
                    defense: npc.defense,
                    gold: npc.gold,
                    npc_type: npc.npc_type,
                    name: npc.name.clone(),
                },
            ));

            if npc.is_hostile() {
                entity_cmds.insert(HostileNpc);
            }
            if npc.npc_type == NpcType::Merchant {
                entity_cmds.insert(MerchantNpc);
            }
        }
    }
}
