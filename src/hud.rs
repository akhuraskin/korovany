use bevy::prelude::*;
use crate::app_state::AppState;
use crate::combat3d::CombatMessage;
use crate::materials;
use crate::types::*;
use crate::character::*;
use crate::world3d::ZoneTrigger;

pub struct HudPlugin;

impl Plugin for HudPlugin {
    fn build(&self, app: &mut App) {
        app.insert_resource(CombatLog::default())
            .insert_resource(CurrentZoneName("".into()))
            .add_systems(OnEnter(AppState::InGame), spawn_hud)
            .add_systems(OnExit(AppState::InGame), despawn_hud)
            .add_systems(
                Update,
                (
                    update_health_bar,
                    update_stats_text,
                    update_injury_icons,
                    update_combat_log,
                    collect_combat_messages,
                    update_zone_name,
                    update_interaction_prompt,
                    update_enemy_health_bar,
                )
                    .run_if(in_state(AppState::InGame)),
            );
    }
}

#[derive(Resource, Default)]
pub struct CombatLog {
    pub messages: Vec<(String, Color, f32)>, // text, color, time_remaining
}

#[derive(Resource)]
pub struct CurrentZoneName(pub String);

// HUD marker components
#[derive(Component)]
struct HudRoot;

#[derive(Component)]
struct HealthBarFill;

#[derive(Component)]
struct HealthText;

#[derive(Component)]
struct StatsText;

#[derive(Component)]
struct InjuryPanel;

#[derive(Component)]
struct CombatLogText;

#[derive(Component)]
struct ZoneNameText;

#[derive(Component)]
struct InteractionPrompt;

#[derive(Component)]
struct EnemyHealthBar;

#[derive(Component)]
struct EnemyHealthFill;

#[derive(Component)]
struct EnemyNameText;

fn spawn_hud(mut commands: Commands) {
    commands.spawn((
        Node {
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            position_type: PositionType::Absolute,
            flex_direction: FlexDirection::Column,
            justify_content: JustifyContent::SpaceBetween,
            ..default()
        },
        HudRoot,
    )).with_children(|parent| {
        // Top bar: health + stats
        parent.spawn(Node {
            width: Val::Percent(100.0),
            height: Val::Px(80.0),
            padding: UiRect::all(Val::Px(8.0)),
            flex_direction: FlexDirection::Row,
            justify_content: JustifyContent::SpaceBetween,
            align_items: AlignItems::Start,
            ..default()
        }).with_children(|top| {
            // Left: health bar
            top.spawn(Node {
                flex_direction: FlexDirection::Column,
                width: Val::Px(250.0),
                ..default()
            }).with_children(|health_col| {
                // Health bar background
                health_col.spawn((
                    Node {
                        width: Val::Px(240.0),
                        height: Val::Px(20.0),
                        ..default()
                    },
                    BackgroundColor(materials::HEALTH_BAR_BG),
                )).with_children(|bar_bg| {
                    bar_bg.spawn((
                        Node {
                            width: Val::Percent(100.0),
                            height: Val::Percent(100.0),
                            ..default()
                        },
                        BackgroundColor(materials::HEALTH_BAR_FG),
                        HealthBarFill,
                    ));
                });
                // Health text
                health_col.spawn((
                    Text::new("100/100"),
                    TextFont { font_size: 14.0, ..default() },
                    TextColor(materials::UI_TEXT),
                    HealthText,
                ));
            });

            // Center: zone name
            top.spawn((
                Text::new(""),
                TextFont { font_size: 18.0, ..default() },
                TextColor(materials::UI_TITLE),
                ZoneNameText,
            ));

            // Right: stats
            top.spawn((
                Text::new(""),
                TextFont { font_size: 14.0, ..default() },
                TextColor(materials::UI_TEXT),
                StatsText,
            ));
        });

        // Middle section: combat log (left) + injuries (right)
        parent.spawn(Node {
            width: Val::Percent(100.0),
            flex_grow: 1.0,
            flex_direction: FlexDirection::Row,
            justify_content: JustifyContent::SpaceBetween,
            align_items: AlignItems::End,
            padding: UiRect::all(Val::Px(8.0)),
            ..default()
        }).with_children(|mid| {
            // Combat log
            mid.spawn(Node {
                flex_direction: FlexDirection::Column,
                width: Val::Px(400.0),
                max_height: Val::Px(200.0),
                overflow: Overflow::clip(),
                ..default()
            }).with_children(|log| {
                log.spawn((
                    Text::new(""),
                    TextFont { font_size: 13.0, ..default() },
                    TextColor(materials::UI_TEXT),
                    CombatLogText,
                ));
            });

            // Injury panel
            mid.spawn((
                Node {
                    flex_direction: FlexDirection::Column,
                    width: Val::Px(200.0),
                    ..default()
                },
                InjuryPanel,
            ));
        });

        // Bottom bar: interaction prompt + enemy health
        parent.spawn(Node {
            width: Val::Percent(100.0),
            height: Val::Px(60.0),
            padding: UiRect::all(Val::Px(8.0)),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            flex_direction: FlexDirection::Column,
            ..default()
        }).with_children(|bot| {
            // Enemy health bar (hidden by default)
            bot.spawn((
                Node {
                    width: Val::Px(200.0),
                    height: Val::Px(16.0),
                    display: Display::None,
                    ..default()
                },
                BackgroundColor(materials::HEALTH_BAR_BG),
                EnemyHealthBar,
            )).with_children(|bar| {
                bar.spawn((
                    Node {
                        width: Val::Percent(100.0),
                        height: Val::Percent(100.0),
                        ..default()
                    },
                    BackgroundColor(Color::srgb(0.9, 0.3, 0.1)),
                    EnemyHealthFill,
                ));
            });

            bot.spawn((
                Text::new(""),
                TextFont { font_size: 14.0, ..default() },
                TextColor(materials::UI_TEXT),
                EnemyNameText,
            ));

            // Interaction prompt
            bot.spawn((
                Text::new(""),
                TextFont { font_size: 16.0, ..default() },
                TextColor(Color::srgb(0.8, 0.9, 1.0)),
                InteractionPrompt,
            ));
        });
    });
}

fn despawn_hud(mut commands: Commands, query: Query<Entity, With<HudRoot>>) {
    for entity in &query {
        commands.entity(entity).despawn();
    }
}

fn update_health_bar(
    game_state: Res<GameState>,
    mut fill_q: Query<&mut Node, With<HealthBarFill>>,
    mut text_q: Query<&mut Text, With<HealthText>>,
) {
    let pct = game_state.player.health as f32 / game_state.player.max_health as f32 * 100.0;

    if let Ok(mut node) = fill_q.single_mut() {
        node.width = Val::Percent(pct.max(0.0));
    }
    if let Ok(mut text) = text_q.single_mut() {
        **text = format!("HP: {}/{}", game_state.player.health, game_state.player.max_health);
    }
}

fn update_stats_text(
    game_state: Res<GameState>,
    mut query: Query<&mut Text, With<StatsText>>,
) {
    let Ok(mut text) = query.single_mut() else { return };
    let p = &game_state.player;
    **text = format!(
        "Ур.{} | Атк:{:.0} | Защ:{:.0} | Зол:{} | Опыт:{}/{}",
        p.level,
        p.effective_attack(),
        p.effective_defense(),
        p.gold,
        p.experience,
        p.level * 100,
    );
}

fn update_injury_icons(
    game_state: Res<GameState>,
    mut commands: Commands,
    panel_q: Query<Entity, With<InjuryPanel>>,
    children_q: Query<&Children>,
) {
    let Ok(panel) = panel_q.single() else { return };

    // Clear existing children
    if let Ok(children) = children_q.get(panel) {
        for child in children.iter() {
            commands.entity(child).despawn();
        }
    }

    let injuries = &game_state.player.injuries;
    if !injuries.has_any_injury() {
        return;
    }

    commands.entity(panel).with_children(|parent| {
        for line in injuries.injury_summary() {
            parent.spawn((
                Text::new(line),
                TextFont { font_size: 12.0, ..default() },
                TextColor(Color::srgb(1.0, 0.4, 0.3)),
            ));
        }
    });
}

fn collect_combat_messages(
    mut events: MessageReader<CombatMessage>,
    mut log: ResMut<CombatLog>,
) {
    for msg in events.read() {
        log.messages.push((msg.text.clone(), msg.color, 5.0));
    }
    // Keep last 8 messages
    while log.messages.len() > 8 {
        log.messages.remove(0);
    }
}

fn update_combat_log(
    time: Res<Time>,
    mut log: ResMut<CombatLog>,
    mut query: Query<&mut Text, With<CombatLogText>>,
) {
    // Tick timers
    for entry in &mut log.messages {
        entry.2 -= time.delta_secs();
    }
    log.messages.retain(|e| e.2 > 0.0);

    let Ok(mut text) = query.single_mut() else { return };
    let display: String = log.messages
        .iter()
        .map(|(t, _, _)| t.as_str())
        .collect::<Vec<_>>()
        .join("\n");
    **text = display;
}

fn update_zone_name(
    player_q: Query<&Transform, With<PlayerEntity>>,
    zone_q: Query<(&Transform, &ZoneTrigger)>,
    mut text_q: Query<&mut Text, With<ZoneNameText>>,
    mut zone_name: ResMut<CurrentZoneName>,
    mut game_state: ResMut<GameState>,
) {
    let Ok(player_tf) = player_q.single() else { return };

    let mut closest: Option<(f32, LocationId)> = None;
    for (zone_tf, trigger) in &zone_q {
        let dist = player_tf.translation.xz().distance(zone_tf.translation.xz());
        if let Some((best_dist, _)) = closest {
            if dist < best_dist {
                closest = Some((dist, trigger.location));
            }
        } else {
            closest = Some((dist, trigger.location));
        }
    }

    if let Some((_, loc)) = closest {
        game_state.player.location = loc;
        zone_name.0 = loc.name().to_string();
        if let Ok(mut text) = text_q.single_mut() {
            **text = loc.name().to_string();
        }
    }
}

fn update_interaction_prompt(
    player_q: Query<&Transform, With<PlayerEntity>>,
    merchant_q: Query<(&Transform, &MerchantNpc)>,
    game_state: Res<GameState>,
    mut text_q: Query<&mut Text, With<InteractionPrompt>>,
) {
    let Ok(player_tf) = player_q.single() else { return };
    let Ok(mut text) = text_q.single_mut() else { return };

    // Check nearby merchants
    for (npc_tf, _) in &merchant_q {
        if player_tf.translation.distance(npc_tf.translation) < 4.0 {
            **text = "[E] Торговать".to_string();
            return;
        }
    }

    // Check if at healer location
    if game_state.player.location.has_healer() {
        **text = "[H] Лекарь".to_string();
        return;
    }

    // Check if at shop location
    if game_state.player.location.has_shop() {
        **text = "[E] Магазин".to_string();
        return;
    }

    **text = String::new();
}

fn update_enemy_health_bar(
    player_q: Query<&Transform, With<PlayerEntity>>,
    npc_q: Query<(&Transform, &NpcHealth)>,
    mut bar_q: Query<&mut Node, With<EnemyHealthBar>>,
    mut fill_q: Query<&mut Node, (With<EnemyHealthFill>, Without<EnemyHealthBar>)>,
    mut name_q: Query<&mut Text, With<EnemyNameText>>,
) {
    let Ok(player_tf) = player_q.single() else { return };

    // Find closest enemy in range
    let mut closest: Option<(&NpcHealth, f32)> = None;
    for (npc_tf, health) in &npc_q {
        if health.current <= 0 { continue; }
        let dist = player_tf.translation.distance(npc_tf.translation);
        if dist < 15.0 {
            if let Some((_, best)) = closest {
                if dist < best {
                    closest = Some((health, dist));
                }
            } else {
                closest = Some((health, dist));
            }
        }
    }

    if let Some((health, _)) = closest {
        if let Ok(mut bar_node) = bar_q.single_mut() {
            bar_node.display = Display::Flex;
        }
        if let Ok(mut fill_node) = fill_q.single_mut() {
            let pct = health.current as f32 / health.max as f32 * 100.0;
            fill_node.width = Val::Percent(pct.max(0.0));
        }
        if let Ok(mut name) = name_q.single_mut() {
            **name = format!("{} ({}/{})", health.name, health.current, health.max);
        }
    } else {
        if let Ok(mut bar_node) = bar_q.single_mut() {
            bar_node.display = Display::None;
        }
        if let Ok(mut name) = name_q.single_mut() {
            **name = String::new();
        }
    }
}
