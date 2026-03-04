use avian3d::prelude::*;
use bevy::prelude::*;
use crate::app_state::AppState;
use crate::character::PlayerEntity;
use crate::materials;
use crate::types::LocationId;

#[derive(Component)]
pub struct ZoneTrigger {
    pub location: LocationId,
}

#[derive(Component)]
pub struct ZoneGround;

#[derive(Component)]
pub struct Wall;

#[derive(Component)]
pub struct TreeEntity;

#[derive(Component)]
pub struct TreeLodPair {
    near_entity: Entity,
    far_entity: Entity,
    near_distance: f32,
    far_distance: f32,
    use_near: bool,
}

pub struct World3dPlugin;

impl Plugin for World3dPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(AppState::InGame), spawn_world)
            .add_systems(Update, update_tree_lod.run_if(in_state(AppState::InGame)));
    }
}

/// Returns the 3D center position for each location
pub fn location_position(loc: LocationId) -> Vec3 {
    match loc {
        // Town — center of map
        LocationId::TownSquare => Vec3::new(0.0, 0.0, 0.0),
        LocationId::TownMarket => Vec3::new(-15.0, 0.0, -10.0),
        LocationId::TownTavern => Vec3::new(15.0, 0.0, -10.0),
        LocationId::TownGates => Vec3::new(0.0, 0.0, 20.0),
        // Palace — northeast
        LocationId::PalaceGates => Vec3::new(80.0, 0.0, -40.0),
        LocationId::PalaceCourtyard => Vec3::new(95.0, 0.0, -55.0),
        LocationId::PalaceBarracks => Vec3::new(85.0, 0.0, -70.0),
        LocationId::PalaceThroneRoom => Vec3::new(110.0, 0.0, -65.0),
        LocationId::PalaceArmory => Vec3::new(100.0, 0.0, -45.0),
        // Forest — northwest
        LocationId::ForestEdge => Vec3::new(-60.0, 0.0, -20.0),
        LocationId::ForestVillage => Vec3::new(-80.0, 0.0, -40.0),
        LocationId::ForestDepths => Vec3::new(-100.0, 0.0, -55.0),
        LocationId::ForestSacredGrove => Vec3::new(-90.0, 0.0, -70.0),
        LocationId::ForestOutpost => Vec3::new(-55.0, 0.0, -5.0),
        // Dark Fortress — south
        LocationId::MountainPass => Vec3::new(20.0, 2.0, 80.0),
        LocationId::FortGates => Vec3::new(25.0, 4.0, 100.0),
        LocationId::FortCourtyard => Vec3::new(30.0, 5.0, 115.0),
        LocationId::FortDungeon => Vec3::new(20.0, 3.0, 125.0),
        LocationId::FortTower => Vec3::new(35.0, 8.0, 130.0),
        // Roads
        LocationId::RoadNorthSouth => Vec3::new(10.0, 0.0, 50.0),
        LocationId::RoadEastWest => Vec3::new(40.0, 0.0, -15.0),
        LocationId::Crossroads => Vec3::new(-25.0, 0.0, 10.0),
    }
}

fn zone_radius(loc: LocationId) -> f32 {
    match loc {
        LocationId::TownSquare | LocationId::PalaceCourtyard | LocationId::FortCourtyard => 18.0,
        LocationId::Crossroads => 15.0,
        LocationId::RoadNorthSouth | LocationId::RoadEastWest => 12.0,
        LocationId::ForestDepths => 20.0,
        _ => 14.0,
    }
}

fn zone_color(loc: LocationId) -> Color {
    if loc.is_road() {
        materials::ROAD_COLOR
    } else if loc.is_forest() {
        materials::FOREST_COLOR
    } else {
        match loc {
            LocationId::TownSquare | LocationId::TownMarket
            | LocationId::TownTavern | LocationId::TownGates => materials::TOWN_COLOR,
            LocationId::PalaceGates | LocationId::PalaceCourtyard
            | LocationId::PalaceBarracks | LocationId::PalaceThroneRoom
            | LocationId::PalaceArmory => materials::PALACE_COLOR,
            LocationId::MountainPass | LocationId::FortGates
            | LocationId::FortCourtyard | LocationId::FortDungeon
            | LocationId::FortTower => materials::FORTRESS_COLOR,
            _ => materials::ROAD_COLOR,
        }
    }
}

fn all_locations() -> Vec<LocationId> {
    use LocationId::*;
    vec![
        TownSquare, TownMarket, TownTavern, TownGates,
        PalaceGates, PalaceCourtyard, PalaceBarracks, PalaceThroneRoom, PalaceArmory,
        ForestEdge, ForestVillage, ForestDepths, ForestSacredGrove, ForestOutpost,
        MountainPass, FortGates, FortCourtyard, FortDungeon, FortTower,
        RoadNorthSouth, RoadEastWest, Crossroads,
    ]
}

fn spawn_world(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
) {
    // Directional light (sun)
    commands.spawn((
        DirectionalLight {
            shadows_enabled: true,
            illuminance: 8000.0,
            ..default()
        },
        Transform::from_rotation(Quat::from_euler(EulerRot::XYZ, -0.9, 0.4, 0.0)),
    ));

    // Ambient light
    commands.insert_resource(GlobalAmbientLight {
        color: Color::srgb(0.6, 0.6, 0.7),
        brightness: 200.0,
        ..default()
    });

    // Global ground collider — a large flat cuboid at y=0
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(500.0, 0.1, 500.0))),
        MeshMaterial3d(mats.add(StandardMaterial {
            base_color: Color::srgb(0.35, 0.32, 0.28),
            perceptual_roughness: 1.0,
            ..default()
        })),
        Transform::from_translation(Vec3::new(0.0, -0.05, 0.0)),
        RigidBody::Static,
        Collider::cuboid(500.0, 0.1, 500.0),
    ));

    // Spawn ground planes and zone triggers for each location
    for loc in all_locations() {
        let pos = location_position(loc);
        let radius = zone_radius(loc);
        let color = zone_color(loc);

        // Ground plane
        commands.spawn((
            Mesh3d(meshes.add(Circle::new(radius))),
            MeshMaterial3d(mats.add(StandardMaterial {
                base_color: color,
                perceptual_roughness: 0.9,
                ..default()
            })),
            Transform::from_translation(pos + Vec3::Y * 0.01)
                .with_rotation(Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2)),
            ZoneGround,
        ));

        // Zone trigger sensor (invisible collider)
        commands.spawn((
            RigidBody::Static,
            Collider::cylinder(radius, 4.0),
            Sensor,
            Transform::from_translation(pos + Vec3::Y * 2.0),
            ZoneTrigger { location: loc },
        ));

        // Location name sign (small floating text marker — we'll skip 3D text and use HUD)
    }

    // Spawn walls/boundaries for enclosed areas
    spawn_town_walls(&mut commands, &mut meshes, &mut mats);
    spawn_palace_walls(&mut commands, &mut meshes, &mut mats);
    spawn_fortress_walls(&mut commands, &mut meshes, &mut mats);

    // Spawn road paths as elongated planes connecting locations
    spawn_roads(&mut commands, &mut meshes, &mut mats);

    // Forest trees (decorative cubes)
    spawn_forest_trees(&mut commands, &mut meshes, &mut mats);
}

fn spawn_wall_segment(
    commands: &mut Commands,
    meshes: &mut ResMut<Assets<Mesh>>,
    mats: &mut ResMut<Assets<StandardMaterial>>,
    pos: Vec3,
    size: Vec3,
) {
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(size.x, size.y, size.z))),
        MeshMaterial3d(mats.add(StandardMaterial {
            base_color: materials::WALL_COLOR,
            perceptual_roughness: 0.8,
            ..default()
        })),
        Transform::from_translation(pos + Vec3::Y * size.y * 0.5),
        RigidBody::Static,
        Collider::cuboid(size.x, size.y, size.z),
        Wall,
    ));
}

fn spawn_town_walls(
    commands: &mut Commands,
    meshes: &mut ResMut<Assets<Mesh>>,
    mats: &mut ResMut<Assets<StandardMaterial>>,
) {
    let center = location_position(LocationId::TownSquare);
    let wall_h = 4.0;
    let wall_t = 1.5;
    let half = 25.0;

    // North wall
    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(0.0, 0.0, -half), Vec3::new(half * 2.0, wall_h, wall_t));
    // South wall (with gap for gate)
    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(-15.0, 0.0, half), Vec3::new(20.0, wall_h, wall_t));
    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(15.0, 0.0, half), Vec3::new(20.0, wall_h, wall_t));
    // East wall
    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(half, 0.0, 0.0), Vec3::new(wall_t, wall_h, half * 2.0));
    // West wall
    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(-half, 0.0, 0.0), Vec3::new(wall_t, wall_h, half * 2.0));
}

fn spawn_palace_walls(
    commands: &mut Commands,
    meshes: &mut ResMut<Assets<Mesh>>,
    mats: &mut ResMut<Assets<StandardMaterial>>,
) {
    let center = location_position(LocationId::PalaceCourtyard);
    let wall_h = 6.0;
    let wall_t = 2.0;
    let half = 30.0;

    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(0.0, 0.0, -half), Vec3::new(half * 2.0, wall_h, wall_t));
    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(0.0, 0.0, half), Vec3::new(half * 2.0, wall_h, wall_t));
    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(half, 0.0, 0.0), Vec3::new(wall_t, wall_h, half * 2.0));
    // West wall with gap for gate
    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(-half, 0.0, -15.0), Vec3::new(wall_t, wall_h, 25.0));
    spawn_wall_segment(commands, meshes, mats, center + Vec3::new(-half, 0.0, 15.0), Vec3::new(wall_t, wall_h, 25.0));
}

fn spawn_fortress_walls(
    commands: &mut Commands,
    meshes: &mut ResMut<Assets<Mesh>>,
    mats: &mut ResMut<Assets<StandardMaterial>>,
) {
    let center = location_position(LocationId::FortCourtyard);
    let wall_h = 7.0;
    let wall_t = 2.5;
    let half = 25.0;

    let dark_wall = Color::srgb(0.2, 0.15, 0.2);
    let mat = |mats: &mut ResMut<Assets<StandardMaterial>>| {
        mats.add(StandardMaterial {
            base_color: dark_wall,
            perceptual_roughness: 0.9,
            ..default()
        })
    };

    // Fortress walls
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(half * 2.0, wall_h, wall_t))),
        MeshMaterial3d(mat(mats)),
        Transform::from_translation(center + Vec3::new(0.0, wall_h * 0.5, half)),
        RigidBody::Static,
        Collider::cuboid(half * 2.0, wall_h, wall_t),
        Wall,
    ));
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(wall_t, wall_h, half * 2.0))),
        MeshMaterial3d(mat(mats)),
        Transform::from_translation(center + Vec3::new(half, wall_h * 0.5, 0.0)),
        RigidBody::Static,
        Collider::cuboid(wall_t, wall_h, half * 2.0),
        Wall,
    ));
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(wall_t, wall_h, half * 2.0))),
        MeshMaterial3d(mat(mats)),
        Transform::from_translation(center + Vec3::new(-half, wall_h * 0.5, 0.0)),
        RigidBody::Static,
        Collider::cuboid(wall_t, wall_h, half * 2.0),
        Wall,
    ));
    // North wall with gap
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(18.0, wall_h, wall_t))),
        MeshMaterial3d(mat(mats)),
        Transform::from_translation(center + Vec3::new(-12.0, wall_h * 0.5, -half)),
        RigidBody::Static,
        Collider::cuboid(18.0, wall_h, wall_t),
        Wall,
    ));
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(18.0, wall_h, wall_t))),
        MeshMaterial3d(mat(mats)),
        Transform::from_translation(center + Vec3::new(12.0, wall_h * 0.5, -half)),
        RigidBody::Static,
        Collider::cuboid(18.0, wall_h, wall_t),
        Wall,
    ));
}

fn spawn_roads(
    commands: &mut Commands,
    meshes: &mut ResMut<Assets<Mesh>>,
    mats: &mut ResMut<Assets<StandardMaterial>>,
) {
    let road_mat = mats.add(StandardMaterial {
        base_color: materials::ROAD_COLOR,
        perceptual_roughness: 1.0,
        ..default()
    });

    // Connect locations with road strips
    let connections: Vec<(LocationId, LocationId)> = vec![
        (LocationId::TownGates, LocationId::Crossroads),
        (LocationId::Crossroads, LocationId::RoadNorthSouth),
        (LocationId::Crossroads, LocationId::RoadEastWest),
        (LocationId::Crossroads, LocationId::ForestEdge),
        (LocationId::RoadNorthSouth, LocationId::TownGates),
        (LocationId::RoadNorthSouth, LocationId::MountainPass),
        (LocationId::RoadEastWest, LocationId::PalaceGates),
        (LocationId::RoadEastWest, LocationId::ForestOutpost),
    ];

    for (from, to) in connections {
        let a = location_position(from);
        let b = location_position(to);
        let mid = (a + b) * 0.5;
        let diff = b - a;
        let length = diff.length();
        let angle = f32::atan2(diff.x, diff.z);

        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(4.0, 0.05, length))),
            MeshMaterial3d(road_mat.clone()),
            Transform::from_translation(mid + Vec3::Y * 0.02)
                .with_rotation(Quat::from_rotation_y(angle)),
        ));
    }
}

fn spawn_forest_trees(
    commands: &mut Commands,
    meshes: &mut ResMut<Assets<Mesh>>,
    mats: &mut ResMut<Assets<StandardMaterial>>,
) {
    let trunk_mat = mats.add(StandardMaterial {
        base_color: Color::srgb(0.4, 0.25, 0.1),
        ..default()
    });
    let leaf_mat = mats.add(StandardMaterial {
        base_color: Color::srgb(0.15, 0.45, 0.15),
        ..default()
    });

    let trunk_mesh = meshes.add(Cylinder::new(0.3, 3.0));
    let leaf_mesh = meshes.add(Sphere::new(1.8));

    let forest_locs = [
        LocationId::ForestEdge, LocationId::ForestVillage,
        LocationId::ForestDepths, LocationId::ForestSacredGrove, LocationId::ForestOutpost,
    ];

    let mut seed: u32 = 42;
    for loc in forest_locs {
        let center = location_position(loc);
        let radius = zone_radius(loc);
        for _ in 0..8 {
            // Simple pseudo-random scatter
            seed = seed.wrapping_mul(1103515245).wrapping_add(12345);
            let angle = (seed % 628) as f32 / 100.0;
            seed = seed.wrapping_mul(1103515245).wrapping_add(12345);
            let dist = (seed % 100) as f32 / 100.0 * radius * 0.8;
            let x = center.x + angle.cos() * dist;
            let z = center.z + angle.sin() * dist;

            let world_pos = Vec3::new(x, 0.0, z);

            let mut near_entity = commands.spawn((
                Mesh3d(trunk_mesh.clone()),
                MeshMaterial3d(trunk_mat.clone()),
                Transform::from_xyz(x, 1.5, z),
                RigidBody::Static,
                Collider::cylinder(0.3, 3.0),
                Visibility::Hidden,
                TreeEntity,
            ));
            near_entity.with_children(|parent| {
                parent.spawn((
                    Mesh3d(leaf_mesh.clone()),
                    MeshMaterial3d(leaf_mat.clone()),
                    Transform::from_xyz(0.0, 2.5, 0.0),
                ));
            });

            let near_id = near_entity.id();
            let far_id = commands.spawn((
                Mesh3d(meshes.add(Cuboid::new(1.2, 4.0, 0.12))),
                MeshMaterial3d(mats.add(StandardMaterial {
                    base_color: Color::srgb(0.18, 0.35, 0.14),
                    unlit: true,
                    ..default()
                })),
                Transform::from_xyz(world_pos.x, 2.0, world_pos.z),
                TreeEntity,
            )).id();

            commands.spawn(TreeLodPair {
                near_entity: near_id,
                far_entity: far_id,
                near_distance: 26.0,
                far_distance: 34.0,
                use_near: false,
            });

        }
    }
}

fn update_tree_lod(
    player_q: Query<&Transform, With<PlayerEntity>>,
    mut lod_q: Query<&mut TreeLodPair>,
    mut vis_q: Query<&mut Visibility>,
    tf_q: Query<&Transform>,
) {
    let Ok(player_tf) = player_q.single() else { return };
    for mut lod in &mut lod_q {
        let Ok(near_tf) = tf_q.get(lod.near_entity) else { continue };
        let dist = player_tf.translation.distance(near_tf.translation);

        if lod.use_near && dist > lod.far_distance {
            lod.use_near = false;
        } else if !lod.use_near && dist < lod.near_distance {
            lod.use_near = true;
        }

        if let Ok(mut vis) = vis_q.get_mut(lod.near_entity) {
            *vis = if lod.use_near { Visibility::Visible } else { Visibility::Hidden };
        }
        if let Ok(mut vis) = vis_q.get_mut(lod.far_entity) {
            *vis = if lod.use_near { Visibility::Hidden } else { Visibility::Visible };
        }
    }
}
