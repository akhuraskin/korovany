use avian3d::prelude::*;
use bevy::prelude::*;
use rand::Rng;
use crate::app_state::AppState;
use crate::character::*;
use crate::combat3d::*;

#[derive(Component)]
pub struct AiState {
    pub state: AiFsm,
    pub home_position: Vec3,
    pub attack_timer: Timer,
    pub aggro_range: f32,
    pub attack_range: f32,
    pub chase_speed: f32,
    pub leash_range: f32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AiFsm {
    Idle,
    Chase,
    Attack,
    ReturnHome,
}

impl Default for AiState {
    fn default() -> Self {
        Self {
            state: AiFsm::Idle,
            home_position: Vec3::ZERO,
            attack_timer: Timer::from_seconds(1.2, TimerMode::Repeating),
            aggro_range: 15.0,
            attack_range: 2.5,
            chase_speed: 5.0,
            leash_range: 25.0,
        }
    }
}

pub struct NpcAiPlugin;

impl Plugin for NpcAiPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(AppState::InGame), init_ai_states)
            .add_systems(
                Update,
                (ai_fsm_system, ai_attack_system)
                    .run_if(in_state(AppState::InGame)),
            );
    }
}

fn init_ai_states(
    mut commands: Commands,
    query: Query<(Entity, &Transform, &NpcHealth), Without<AiState>>,
) {
    for (entity, transform, npc_health) in &query {
        let is_hostile = matches!(
            npc_health.npc_type,
            crate::types::NpcType::Bandit | crate::types::NpcType::Beast
        );

        let mut ai = AiState {
            home_position: transform.translation,
            ..default()
        };

        if !is_hostile {
            // Non-hostile NPCs don't aggro proactively
            ai.aggro_range = 0.0;
        }

        // Randomize attack timer slightly
        let mut rng = rand::thread_rng();
        ai.attack_timer = Timer::from_seconds(
            1.0 + rng.gen::<f32>() * 0.5,
            TimerMode::Repeating,
        );

        commands.entity(entity).insert(ai);
    }
}

fn ai_fsm_system(
    time: Res<Time>,
    player_q: Query<&Transform, With<PlayerEntity>>,
    mut npc_q: Query<(
        &mut AiState,
        &NpcHealth,
        &Transform,
        &mut LinearVelocity,
    ), Without<PlayerEntity>>,
) {
    let Ok(player_tf) = player_q.single() else { return };

    for (mut ai, npc_health, npc_tf, mut velocity) in &mut npc_q {
        if npc_health.current <= 0 {
            velocity.x = 0.0;
            velocity.z = 0.0;
            continue;
        }

        let to_player = player_tf.translation - npc_tf.translation;
        let dist_to_player = to_player.length();
        let to_home = ai.home_position - npc_tf.translation;
        let dist_to_home = to_home.length();

        match ai.state {
            AiFsm::Idle => {
                velocity.x = 0.0;
                velocity.z = 0.0;

                if ai.aggro_range > 0.0 && dist_to_player < ai.aggro_range {
                    ai.state = AiFsm::Chase;
                }
            }
            AiFsm::Chase => {
                if dist_to_player < ai.attack_range {
                    ai.state = AiFsm::Attack;
                    velocity.x = 0.0;
                    velocity.z = 0.0;
                } else if dist_to_player > ai.leash_range {
                    ai.state = AiFsm::ReturnHome;
                } else {
                    let dir = Vec3::new(to_player.x, 0.0, to_player.z).normalize_or_zero();
                    velocity.x = dir.x * ai.chase_speed;
                    velocity.z = dir.z * ai.chase_speed;
                }
            }
            AiFsm::Attack => {
                ai.attack_timer.tick(time.delta());

                if dist_to_player > ai.attack_range * 1.5 {
                    ai.state = AiFsm::Chase;
                } else if dist_to_player > ai.leash_range {
                    ai.state = AiFsm::ReturnHome;
                } else {
                    // Face player
                    velocity.x = 0.0;
                    velocity.z = 0.0;
                }
            }
            AiFsm::ReturnHome => {
                if dist_to_home < 3.0 {
                    ai.state = AiFsm::Idle;
                    velocity.x = 0.0;
                    velocity.z = 0.0;
                } else {
                    let dir = to_home.normalize();
                    velocity.x = dir.x * 3.0;
                    velocity.z = dir.z * 3.0;
                }
            }
        }
    }
}

fn ai_attack_system(
    mut commands: Commands,
    npc_q: Query<(
        &AiState,
        &NpcHealth,
        &Transform,
    )>,
    player_q: Query<&Transform, With<PlayerEntity>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
) {
    let Ok(player_tf) = player_q.single() else { return };

    for (ai, npc_health, npc_tf) in &npc_q {
        if ai.state != AiFsm::Attack || npc_health.current <= 0 {
            continue;
        }

        if !ai.attack_timer.just_finished() {
            continue;
        }

        let to_player = player_tf.translation - npc_tf.translation;
        let dir = Vec3::new(to_player.x, 0.0, to_player.z).normalize_or_zero();
        let hitbox_pos = npc_tf.translation + dir * 1.5 + Vec3::Y * 0.5;

        let damage = npc_health.attack;

        // Use a unique entity each attack
        let npc_entity = commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(1.0, 1.2, 0.8))),
            MeshMaterial3d(mats.add(StandardMaterial {
                base_color: Color::srgba(1.0, 0.2, 0.2, 0.3),
                alpha_mode: AlphaMode::Blend,
                unlit: true,
                ..default()
            })),
            Transform::from_translation(hitbox_pos),
            Collider::cuboid(1.0, 1.2, 0.8),
            Sensor,
            RigidBody::Kinematic,
            Hitbox {
                damage,
                is_player: false,
            },
            HitboxLifetime(Timer::from_seconds(0.15, TimerMode::Once)),
        )).id();

        let _ = npc_entity;
    }
}
