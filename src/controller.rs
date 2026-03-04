use avian3d::prelude::*;
use bevy::prelude::*;
use crate::app_state::AppState;
use crate::camera::OrbitCamera;
use crate::character::PlayerEntity;
use crate::types::GameState;
use crate::world3d::location_position;

pub struct ControllerPlugin;

impl Plugin for ControllerPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(
            Update,
            player_movement.run_if(in_state(AppState::InGame)),
        );
    }
}

fn player_movement(
    input: Res<ButtonInput<KeyCode>>,
    game_state: Res<GameState>,
    cam_q: Query<&OrbitCamera>,
    mut player_q: Query<(&mut LinearVelocity, &mut Transform), With<PlayerEntity>>,
) {
    let Ok(orbit) = cam_q.single() else { return };
    let Ok((mut velocity, mut transform)) = player_q.single_mut() else { return };

    let mut direction = Vec3::ZERO;

    if input.pressed(KeyCode::KeyW) {
        direction.z -= 1.0;
    }
    if input.pressed(KeyCode::KeyS) {
        direction.z += 1.0;
    }
    if input.pressed(KeyCode::KeyA) {
        direction.x -= 1.0;
    }
    if input.pressed(KeyCode::KeyD) {
        direction.x += 1.0;
    }

    if direction != Vec3::ZERO {
        direction = direction.normalize();

        // Rotate direction relative to camera yaw
        let yaw_rot = Quat::from_rotation_y(orbit.yaw);
        let world_dir = yaw_rot * direction;

        // Base speed modified by injuries
        let base_speed = 8.0;
        let speed_mult = game_state.player.injuries.movement_speed() as f32;
        let sprint = if input.pressed(KeyCode::ShiftLeft) { 1.6 } else { 1.0 };
        let speed = base_speed * speed_mult * sprint;

        velocity.x = world_dir.x * speed;
        velocity.z = world_dir.z * speed;

        // Rotate player to face movement direction
        let look_dir = Vec3::new(world_dir.x, 0.0, world_dir.z);
        if look_dir.length_squared() > 0.01 {
            let target_rot = Quat::from_rotation_arc(Vec3::NEG_Z, look_dir.normalize());
            transform.rotation = transform.rotation.slerp(target_rot, 0.15);
        }
    }

    // Grounded jump: `Space` is jump; dodge is mapped elsewhere to avoid key conflict.
    let ground_y = location_position(game_state.player.location).y + 1.5;
    let is_grounded = (transform.translation.y - ground_y).abs() < 0.15 && velocity.y.abs() < 0.6;
    if input.just_pressed(KeyCode::Space) && is_grounded {
        velocity.y = 8.5;
    }
}
