use avian3d::prelude::*;
use bevy::prelude::*;
use rand::Rng;
use crate::app_state::AppState;
use crate::character::*;
use crate::combat::apply_dismemberment;
use crate::materials;
use crate::trade;
use crate::types::GameState;

pub struct Combat3dPlugin;

impl Plugin for Combat3dPlugin {
    fn build(&self, app: &mut App) {
        app.add_message::<DamageEvent>()
            .add_message::<CombatMessage>()
            .insert_resource(DodgeCooldown(Timer::from_seconds(1.0, TimerMode::Once)))
            .insert_resource(BleedTimer(Timer::from_seconds(3.0, TimerMode::Repeating)))
            .add_systems(
                Update,
                (
                    player_attack_input,
                    player_block_input,
                    player_dodge_input,
                    hitbox_lifetime,
                    hitbox_collision,
                    process_damage_events,
                    npc_death_system,
                    bleeding_system,
                    invincibility_timer,
                    loot_pickup_system,
                    caravan_interaction_system,
                )
                    .run_if(in_state(AppState::InGame)),
            );
    }
}

#[derive(Message)]
pub struct DamageEvent {
    pub target: Entity,
    pub damage: i32,
    pub is_crit: bool,
    pub attacker_is_player: bool,
}

#[derive(Message)]
pub struct CombatMessage {
    pub text: String,
    pub color: Color,
}

#[derive(Component)]
pub struct Hitbox {
    pub damage: i32,
    pub is_player: bool,
}

#[derive(Component)]
pub struct HitboxLifetime(pub Timer);

#[derive(Component)]
pub struct Blocking;

#[derive(Component)]
pub struct Invincible(pub Timer);

#[derive(Resource)]
pub struct DodgeCooldown(pub Timer);

#[derive(Resource)]
pub struct BleedTimer(pub Timer);

#[derive(Component)]
pub struct LootDrop {
    pub items: Vec<crate::types::Item>,
    pub gold: i32,
}

#[derive(Component)]
pub struct CaravanGuardNpc {
    pub caravan_index: usize,
    pub guard_index: usize,
}

fn player_attack_input(
    mut commands: Commands,
    mouse: Res<ButtonInput<MouseButton>>,
    game_state: Res<GameState>,
    player_q: Query<&Transform, With<PlayerEntity>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
) {
    if !mouse.just_pressed(MouseButton::Left) {
        return;
    }
    if !game_state.player.injuries.can_fight() {
        return;
    }

    let Ok(player_tf) = player_q.single() else { return };

    let forward = player_tf.forward();
    let hitbox_pos = player_tf.translation + forward * 1.5 + Vec3::Y * 0.5;
    let damage = game_state.player.effective_attack() as i32;

    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(1.2, 1.5, 1.0))),
        MeshMaterial3d(mats.add(StandardMaterial {
            base_color: Color::srgba(1.0, 0.8, 0.2, 0.3),
            alpha_mode: AlphaMode::Blend,
            unlit: true,
            ..default()
        })),
        Transform::from_translation(hitbox_pos)
            .with_rotation(player_tf.rotation),
        Collider::cuboid(1.2, 1.5, 1.0),
        Sensor,
        RigidBody::Kinematic,
        Hitbox {
            damage,
            is_player: true,
        },
        HitboxLifetime(Timer::from_seconds(0.2, TimerMode::Once)),
    ));
}

fn player_block_input(
    mut commands: Commands,
    mouse: Res<ButtonInput<MouseButton>>,
    player_q: Query<Entity, With<PlayerEntity>>,
) {
    let Ok(entity) = player_q.single() else { return };

    if mouse.just_pressed(MouseButton::Right) {
        commands.entity(entity).insert(Blocking);
    }
    if mouse.just_released(MouseButton::Right) {
        commands.entity(entity).remove::<Blocking>();
    }
}

fn player_dodge_input(
    mut commands: Commands,
    input: Res<ButtonInput<KeyCode>>,
    time: Res<Time>,
    mut cooldown: ResMut<DodgeCooldown>,
    mut player_q: Query<(Entity, &Transform, &mut LinearVelocity), With<PlayerEntity>>,
) {
    cooldown.0.tick(time.delta());

    if !input.just_pressed(KeyCode::KeyQ) || !cooldown.0.is_finished() {
        return;
    }

    let Ok((entity, transform, mut velocity)) = player_q.single_mut() else { return };

    let forward = transform.forward();
    let impulse_dir = Vec3::new(forward.x, 0.0, forward.z).normalize_or_zero();
    velocity.x = impulse_dir.x * 15.0;
    velocity.z = impulse_dir.z * 15.0;

    commands.entity(entity).insert(Invincible(Timer::from_seconds(0.3, TimerMode::Once)));
    cooldown.0.reset();
}

fn hitbox_lifetime(
    mut commands: Commands,
    time: Res<Time>,
    mut query: Query<(Entity, &mut HitboxLifetime)>,
) {
    for (entity, mut lifetime) in &mut query {
        lifetime.0.tick(time.delta());
        if lifetime.0.is_finished() {
            commands.entity(entity).despawn();
        }
    }
}

fn hitbox_collision(
    mut events: MessageWriter<DamageEvent>,
    hitbox_q: Query<(&Hitbox, &CollidingEntities)>,
    npc_q: Query<Entity, With<NpcHealth>>,
    player_q: Query<Entity, With<PlayerEntity>>,
) {
    for (hitbox, colliding) in &hitbox_q {
        for &entity in colliding.iter() {
            if hitbox.is_player {
                // Player's hitbox → damage NPCs
                if npc_q.contains(entity) {
                    let mut rng = rand::thread_rng();
                    let is_crit = rng.gen_range(0..100) < 15;
                    let damage = if is_crit {
                        hitbox.damage + hitbox.damage / 2
                    } else {
                        hitbox.damage
                    };
                    events.write(DamageEvent {
                        target: entity,
                        damage,
                        is_crit,
                        attacker_is_player: true,
                    });
                }
            } else {
                // NPC hitbox → damage player
                if player_q.contains(entity) {
                    events.write(DamageEvent {
                        target: entity,
                        damage: hitbox.damage,
                        is_crit: false,
                        attacker_is_player: false,
                    });
                }
            }
        }
    }
}

fn process_damage_events(
    mut commands: Commands,
    mut events: MessageReader<DamageEvent>,
    mut combat_msgs: MessageWriter<CombatMessage>,
    mut game_state: ResMut<GameState>,
    mut npc_q: Query<&mut NpcHealth>,
    invincible_q: Query<&Invincible>,
    blocking_q: Query<&Blocking>,
    player_q: Query<Entity, With<PlayerEntity>>,
) {
    for event in events.read() {
        if event.attacker_is_player {
            // Damage NPC
            if let Ok(mut npc_health) = npc_q.get_mut(event.target) {
                let defense = npc_health.defense as f64;
                let mut damage = (event.damage as f64 - defense * 0.3).max(1.0) as i32;

                // Random variance
                let mut rng = rand::thread_rng();
                damage = (damage as f64 * (0.8 + rng.gen::<f64>() * 0.4)) as i32;
                damage = damage.max(1);

                // Elf forest bonus
                if game_state.player.faction == crate::types::Faction::Elves
                    && game_state.player.location.is_forest()
                {
                    damage = (damage as f64 * 1.3) as i32;
                    combat_msgs.write(CombatMessage {
                        text: "Бонус леса! (+30%)".into(),
                        color: Color::srgb(0.2, 0.9, 0.3),
                    });
                }

                npc_health.current -= damage;
                let msg = if event.is_crit {
                    format!("КРИТ! {} → {} (-{})", game_state.player.name, npc_health.name, damage)
                } else {
                    format!("{} → {} (-{})", game_state.player.name, npc_health.name, damage)
                };
                combat_msgs.write(CombatMessage {
                    text: msg,
                    color: Color::srgb(1.0, 0.9, 0.2),
                });
            }
        } else {
            // Damage player
            let Ok(player_entity) = player_q.single() else { continue };
            if event.target != player_entity {
                continue;
            }

            // Check invincibility
            if invincible_q.get(event.target).is_ok() {
                combat_msgs.write(CombatMessage {
                    text: "Уворот!".into(),
                    color: Color::srgb(0.5, 0.8, 1.0),
                });
                continue;
            }

            let mut damage = event.damage;
            // Check blocking
            if blocking_q.get(event.target).is_ok() {
                damage = (damage as f64 * 0.3) as i32;
                combat_msgs.write(CombatMessage {
                    text: format!("Блок! (-{})", damage),
                    color: Color::srgb(0.3, 0.6, 1.0),
                });
            }

            game_state.player.take_damage(damage);
            combat_msgs.write(CombatMessage {
                text: format!("Вы получили {} урона!", damage),
                color: Color::srgb(1.0, 0.3, 0.3),
            });

            // Crit chance for dismemberment from NPCs (10%)
            let mut rng = rand::thread_rng();
            if rng.gen_range(0..100) < 10 {
                let extra = damage / 2;
                game_state.player.take_damage(extra);
                combat_msgs.write(CombatMessage {
                    text: format!("КРИТИЧЕСКИЙ УДАР! +{} урона!", extra),
                    color: Color::srgb(1.0, 0.1, 0.1),
                });

                if rng.gen_range(0..100) < 50 {
                    let msg = apply_dismemberment(&mut game_state.player, &mut rng);
                    combat_msgs.write(CombatMessage {
                        text: msg,
                        color: Color::srgb(1.0, 0.0, 0.0),
                    });
                }
            }

            if !game_state.player.is_alive() {
                game_state.game_over = true;
                commands.trigger(GameOverTrigger);
            }
        }
    }
}

#[derive(Event)]
pub struct GameOverTrigger;  // Event for observers, not Message

fn npc_death_system(
    mut commands: Commands,
    mut combat_msgs: MessageWriter<CombatMessage>,
    mut game_state: ResMut<GameState>,
    query: Query<(Entity, &NpcHealth, &Transform, Option<&CaravanGuardNpc>)>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
) {
    for (entity, npc_health, transform, maybe_caravan_guard) in &query {
        if npc_health.current <= 0 {
            if let Some(caravan_guard) = maybe_caravan_guard {
                if let Some(caravan) = game_state.caravans.get_mut(caravan_guard.caravan_index) {
                    if let Some(guard) = caravan.guards.get_mut(caravan_guard.guard_index) {
                        guard.health = 0;
                    }
                }
            }

            let exp = 20 + npc_health.max / 2;
            if game_state.player.add_experience(exp) {
                combat_msgs.write(CombatMessage {
                    text: format!("Уровень {}!", game_state.player.level),
                    color: Color::srgb(1.0, 1.0, 0.0),
                });
            }
            combat_msgs.write(CombatMessage {
                text: format!("{} повержен! +{} опыта", npc_health.name, exp),
                color: Color::srgb(0.2, 1.0, 0.2),
            });

            if npc_health.gold > 0 {
                game_state.player.gold += npc_health.gold;
                combat_msgs.write(CombatMessage {
                    text: format!("+{} золота", npc_health.gold),
                    color: Color::srgb(1.0, 0.85, 0.0),
                });
            }

            // Spawn loot cube
            if npc_health.gold > 0 {
                commands.spawn((
                    Mesh3d(meshes.add(Cuboid::new(0.5, 0.5, 0.5))),
                    MeshMaterial3d(mats.add(StandardMaterial {
                        base_color: crate::materials::LOOT_COLOR,
                        emissive: LinearRgba::new(1.0, 0.8, 0.0, 1.0),
                        ..default()
                    })),
                    Transform::from_translation(transform.translation),
                    RigidBody::Dynamic,
                    Collider::cuboid(0.5, 0.5, 0.5),
                    LootDrop {
                        items: Vec::new(),
                        gold: 0, // gold already given directly
                    },
                ));
            }

            // Despawn defeated NPCs so they no longer interact with combat systems.
            commands.entity(entity).despawn();
        }
    }
}

fn bleeding_system(
    time: Res<Time>,
    mut bleed_timer: ResMut<BleedTimer>,
    mut game_state: ResMut<GameState>,
    mut combat_msgs: MessageWriter<CombatMessage>,
) {
    bleed_timer.0.tick(time.delta());
    if !bleed_timer.0.just_finished() {
        return;
    }

    if let Some(msg) = game_state.player.tick_bleeding() {
        combat_msgs.write(CombatMessage {
            text: msg,
            color: Color::srgb(0.8, 0.0, 0.0),
        });
    }
}

fn invincibility_timer(
    mut commands: Commands,
    time: Res<Time>,
    mut query: Query<(Entity, &mut Invincible)>,
) {
    for (entity, mut inv) in &mut query {
        inv.0.tick(time.delta());
        if inv.0.is_finished() {
            commands.entity(entity).remove::<Invincible>();
        }
    }
}

fn loot_pickup_system(
    mut commands: Commands,
    input: Res<ButtonInput<KeyCode>>,
    player_q: Query<&Transform, With<PlayerEntity>>,
    loot_q: Query<(Entity, &Transform, &LootDrop)>,
    mut game_state: ResMut<GameState>,
    mut combat_msgs: MessageWriter<CombatMessage>,
) {
    if !input.just_pressed(KeyCode::KeyE) {
        return;
    }

    let Ok(player_tf) = player_q.single() else { return };

    for (entity, loot_tf, loot) in &loot_q {
        let dist = player_tf.translation.distance(loot_tf.translation);
        if dist < 3.0 {
            for item in &loot.items {
                game_state.player.inventory.push(item.clone());
                combat_msgs.write(CombatMessage {
                    text: format!("Подобрано: {}", item.name),
                    color: Color::srgb(0.2, 0.8, 1.0),
                });
            }
            if loot.gold > 0 {
                game_state.player.gold += loot.gold;
                combat_msgs.write(CombatMessage {
                    text: format!("+{} золота", loot.gold),
                    color: Color::srgb(1.0, 0.85, 0.0),
                });
            }
            commands.entity(entity).despawn();
        }
    }
}

fn caravan_interaction_system(
    input: Res<ButtonInput<KeyCode>>,
    mut commands: Commands,
    mut game_state: ResMut<GameState>,
    player_q: Query<&Transform, With<PlayerEntity>>,
    mut caravan_q: Query<(Entity, &Transform, &mut crate::CaravanEntity)>,
    caravan_guard_q: Query<&CaravanGuardNpc>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
    mut combat_msgs: MessageWriter<CombatMessage>,
) {
    if !input.just_pressed(KeyCode::KeyE) {
        return;
    }

    let Ok(player_tf) = player_q.single() else { return };
    let mut nearest: Option<(f32, usize, Vec3)> = None;
    let mut nearest_entity: Option<Entity> = None;
    for (entity, tf, caravan_entity) in &mut caravan_q {
        let dist = player_tf.translation.distance(tf.translation);
        if dist > 6.0 {
            continue;
        }
        match nearest {
            Some((best, _, _)) if dist >= best => {}
            _ => {
                nearest = Some((dist, caravan_entity.caravan_index, tf.translation));
                nearest_entity = Some(entity);
            }
        }
    }

    let Some((_, caravan_index, caravan_pos)) = nearest else { return };
    if caravan_index >= game_state.caravans.len() {
        return;
    }

    if game_state.caravans[caravan_index].location != game_state.player.location {
        return;
    }

    let mut alive_world_guards = 0usize;
    for guard in &caravan_guard_q {
        if guard.caravan_index == caravan_index {
            alive_world_guards += 1;
        }
    }
    if alive_world_guards > 0 {
        combat_msgs.write(CombatMessage {
            text: "Сначала победите охрану корована!".into(),
            color: Color::srgb(1.0, 0.6, 0.2),
        });
        return;
    }

    let has_alive_state_guards = game_state.caravans[caravan_index].guards.iter().any(|g| g.is_alive());
    if has_alive_state_guards {
        let alive_guards: Vec<(usize, crate::types::Npc)> = game_state.caravans[caravan_index]
            .guards
            .iter()
            .enumerate()
            .filter(|(_, g)| g.is_alive())
            .map(|(i, g)| (i, g.clone()))
            .collect();

        for (guard_index, guard) in alive_guards {
            let offset = Vec3::new(
                (guard_index as f32 * 2.1).sin() * 2.4,
                0.0,
                (guard_index as f32 * 2.7).cos() * 2.4,
            );
            commands.spawn((
                Mesh3d(meshes.add(Capsule3d::new(0.35, 1.0))),
                MeshMaterial3d(mats.add(StandardMaterial {
                    base_color: materials::CARAVAN_GUARD_COLOR,
                    ..default()
                })),
                Transform::from_translation(caravan_pos + offset + Vec3::Y * 1.5),
                RigidBody::Dynamic,
                Collider::capsule(0.35, 1.0),
                LockedAxes::ROTATION_LOCKED,
                LinearDamping(8.0),
                NpcHealth {
                    current: guard.health,
                    max: guard.max_health,
                    attack: guard.attack,
                    defense: guard.defense,
                    gold: guard.gold,
                    npc_type: guard.npc_type,
                    name: guard.name,
                },
                HostileNpc,
                CaravanGuardNpc {
                    caravan_index,
                    guard_index,
                },
            ));
        }

        combat_msgs.write(CombatMessage {
            text: "Охрана корована вступила в бой!".into(),
            color: Color::srgb(1.0, 0.5, 0.3),
        });
        return;
    }

    let (msgs, _) = trade::raid_caravan(&mut game_state, caravan_index);
    for text in msgs {
        combat_msgs.write(CombatMessage {
            text,
            color: Color::srgb(0.8, 0.8, 0.4),
        });
    }
    if let Some(entity) = nearest_entity {
        commands.entity(entity).despawn();
    }
    for (_, _, mut caravan_entity) in &mut caravan_q {
        if caravan_entity.caravan_index > caravan_index {
            caravan_entity.caravan_index -= 1;
        }
    }
}
