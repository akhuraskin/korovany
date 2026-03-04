use rand::Rng;

use crate::types::{DismemberTarget, EyeState, LimbState, Player};

pub fn apply_dismemberment(player: &mut Player, rng: &mut impl Rng) -> String {
    let targets = [
        DismemberTarget::LeftArm,
        DismemberTarget::RightArm,
        DismemberTarget::LeftLeg,
        DismemberTarget::RightLeg,
        DismemberTarget::LeftEye,
        DismemberTarget::RightEye,
    ];

    let target = targets[rng.gen_range(0..targets.len())];

    match target {
        DismemberTarget::LeftArm => match player.injuries.left_arm {
            LimbState::Healthy => {
                player.injuries.left_arm = LimbState::Wounded;
                "Вражеский удар ранил вашу левую руку!".to_string()
            }
            LimbState::Wounded => {
                player.injuries.left_arm = LimbState::Severed;
                player.injuries.bleeding = true;
                player.injuries.bleed_turns_left = 5;
                "Вражеский удар ОТРУБИЛ вашу левую руку! Вы истекаете кровью!".to_string()
            }
            _ => "Удар попал по уже раненой руке.".to_string(),
        },
        DismemberTarget::RightArm => match player.injuries.right_arm {
            LimbState::Healthy => {
                player.injuries.right_arm = LimbState::Wounded;
                "Вражеский удар ранил вашу правую руку!".to_string()
            }
            LimbState::Wounded => {
                player.injuries.right_arm = LimbState::Severed;
                player.injuries.bleeding = true;
                player.injuries.bleed_turns_left = 5;
                "Вражеский удар ОТРУБИЛ вашу правую руку! Вы истекаете кровью!".to_string()
            }
            _ => "Удар попал по уже раненой руке.".to_string(),
        },
        DismemberTarget::LeftLeg => match player.injuries.left_leg {
            LimbState::Healthy => {
                player.injuries.left_leg = LimbState::Wounded;
                "Вражеский удар ранил вашу левую ногу!".to_string()
            }
            LimbState::Wounded => {
                player.injuries.left_leg = LimbState::Severed;
                player.injuries.bleeding = true;
                player.injuries.bleed_turns_left = 5;
                "Вражеский удар ОТРУБИЛ вашу левую ногу! Вы истекаете кровью!".to_string()
            }
            _ => "Удар попал по уже раненой ноге.".to_string(),
        },
        DismemberTarget::RightLeg => match player.injuries.right_leg {
            LimbState::Healthy => {
                player.injuries.right_leg = LimbState::Wounded;
                "Вражеский удар ранил вашу правую ногу!".to_string()
            }
            LimbState::Wounded => {
                player.injuries.right_leg = LimbState::Severed;
                player.injuries.bleeding = true;
                player.injuries.bleed_turns_left = 5;
                "Вражеский удар ОТРУБИЛ вашу правую ногу! Вы истекаете кровью!".to_string()
            }
            _ => "Удар попал по уже раненой ноге.".to_string(),
        },
        DismemberTarget::LeftEye => match player.injuries.left_eye {
            EyeState::Healthy => {
                player.injuries.left_eye = EyeState::Wounded;
                "Вражеский удар ранил ваш левый глаз!".to_string()
            }
            EyeState::Wounded => {
                player.injuries.left_eye = EyeState::Lost;
                player.injuries.bleeding = true;
                player.injuries.bleed_turns_left = 4;
                "Вражеский удар ВЫБИЛ ваш левый глаз! Вы истекаете кровью!".to_string()
            }
            _ => "Удар попал по уже раненому глазу.".to_string(),
        },
        DismemberTarget::RightEye => match player.injuries.right_eye {
            EyeState::Healthy => {
                player.injuries.right_eye = EyeState::Wounded;
                "Вражеский удар ранил ваш правый глаз!".to_string()
            }
            EyeState::Wounded => {
                player.injuries.right_eye = EyeState::Lost;
                player.injuries.bleeding = true;
                player.injuries.bleed_turns_left = 4;
                "Вражеский удар ВЫБИЛ ваш правый глаз! Вы истекаете кровью!".to_string()
            }
            _ => "Удар попал по уже раненому глазу.".to_string(),
        },
    }
}
