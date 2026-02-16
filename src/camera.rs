use bevy::prelude::*;
use bevy::input::mouse::{MouseMotion, MouseScrollUnit, MouseWheel};
use crate::app_state::AppState;
use crate::character::PlayerEntity;

#[derive(Component)]
pub struct OrbitCamera {
    pub yaw: f32,
    pub pitch: f32,
    pub distance: f32,
    pub min_distance: f32,
    pub max_distance: f32,
}

impl Default for OrbitCamera {
    fn default() -> Self {
        Self {
            yaw: 0.0,
            pitch: -0.4,
            distance: 12.0,
            min_distance: 5.0,
            max_distance: 25.0,
        }
    }
}

pub struct CameraPlugin;

impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(AppState::InGame), spawn_camera)
            .add_systems(
                Update,
                (camera_input, camera_follow)
                    .chain()
                    .run_if(in_state(AppState::InGame)),
            );
    }
}

fn spawn_camera(mut commands: Commands) {
    commands.spawn((
        Camera3d::default(),
        OrbitCamera::default(),
        Transform::from_xyz(0.0, 10.0, 12.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
}

fn camera_input(
    mut mouse_motion: MessageReader<MouseMotion>,
    mut scroll: MessageReader<MouseWheel>,
    mouse_button: Res<ButtonInput<MouseButton>>,
    mut query: Query<&mut OrbitCamera>,
) {
    let Ok(mut orbit) = query.single_mut() else { return };

    // Rotate on right mouse button drag
    if mouse_button.pressed(MouseButton::Right) {
        for ev in mouse_motion.read() {
            orbit.yaw -= ev.delta.x * 0.005;
            orbit.pitch -= ev.delta.y * 0.005;
            orbit.pitch = orbit.pitch.clamp(-1.4, -0.1);
        }
    } else {
        mouse_motion.clear();
    }

    // Zoom with scroll
    for ev in scroll.read() {
        let amount = match ev.unit {
            MouseScrollUnit::Line => ev.y * 1.5,
            MouseScrollUnit::Pixel => ev.y * 0.05,
        };
        orbit.distance = (orbit.distance - amount).clamp(orbit.min_distance, orbit.max_distance);
    }
}

fn camera_follow(
    player_q: Query<&Transform, (With<PlayerEntity>, Without<OrbitCamera>)>,
    mut cam_q: Query<(&OrbitCamera, &mut Transform), Without<PlayerEntity>>,
) {
    let Ok(player_tf) = player_q.single() else { return };
    let Ok((orbit, mut cam_tf)) = cam_q.single_mut() else { return };

    let target = player_tf.translation + Vec3::Y * 1.5;

    let offset = Vec3::new(
        orbit.yaw.sin() * orbit.pitch.cos() * orbit.distance,
        -orbit.pitch.sin() * orbit.distance,
        orbit.yaw.cos() * orbit.pitch.cos() * orbit.distance,
    );

    cam_tf.translation = target + offset;
    cam_tf.look_at(target, Vec3::Y);
}
