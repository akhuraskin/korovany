class_name Actor
extends CharacterBody3D
## Anything that walks, fights, bleeds and dies: the player and all NPCs.
##
## Body parts: arm_l, arm_r, leg_l, leg_r, eye_l, eye_r.
## Each is "ok", "lost" or "prosthetic".
## - Lost arm or leg: you bleed. Without a bandage or a healer you die.
## - Lost eye: half of the screen goes dark (player).
## - Lost leg: crawl, ride a wheelchair, or fit a prosthesis.

signal died(actor, killer)

const GRAVITY := 22.0
const JUMP_VELOCITY := 8.0
const LIMBS := ["arm_l", "arm_r", "leg_l", "leg_r"]
const PART_NAMES := {
	"arm_l": "left arm", "arm_r": "right arm", "leg_l": "left leg", "leg_r": "right leg",
	"eye_l": "left eye", "eye_r": "right eye", "head": "head", "torso": "body",
}

var uid := ""
var faction := Factions.HUMANS
var role := "civilian"
var display_name := "Someone"
var is_player := false
var max_hp := 100.0
var hp := 100.0
var base_speed := 4.2
var base_damage := 9.0
var armor := 0.0
var gold := 0
var weapon := ""
var armor_item := ""
var inventory := {}
var model_scale := 1.0
var ranged := false

var parts := {"arm_l": "ok", "arm_r": "ok", "leg_l": "ok", "leg_r": "ok", "eye_l": "ok", "eye_r": "ok"}
var limb_hp := {}
var bleeding := 0.0
var has_wheelchair := false
var use_wheelchair := true
var dead := false
var aggro := {}

var model: Humanoid
var move_dir := Vector3.ZERO
var want_jump := false
var sprinting := false
var face_yaw := 0.0
var attack_cd := 0.0
var _pending_hit := -1.0
var _pending_part := ""


func _ready() -> void:
	add_to_group("actors")
	collision_layer = 2
	collision_mask = 1 | 2
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35 * model_scale
	cap.height = 1.8 * model_scale
	cs.shape = cap
	cs.position.y = 0.9 * model_scale
	add_child(cs)
	for l in LIMBS:
		if not limb_hp.has(l):
			limb_hp[l] = 25.0
	if not limb_hp.has("head"):
		limb_hp["head"] = 30.0
	model = Humanoid.new()
	model.name = "Model"
	add_child(model)
	model.build(appearance())
	model.set_bleeding(bleeding > 0.0)
	rotation.y = face_yaw


func appearance() -> Dictionary:
	return {
		"faction": faction, "role": "player" if is_player else role, "scale": model_scale,
		"parts": parts.duplicate(), "ranged": ranged,
	}


# --- abilities ------------------------------------------------------------

func legs_lost() -> int:
	var n := 0
	for l in ["leg_l", "leg_r"]:
		if parts[l] == "lost":
			n += 1
	return n


func mobility() -> String:
	if legs_lost() == 0:
		return "walk"
	if has_wheelchair and use_wheelchair:
		return "wheelchair"
	return "crawl"


func speed() -> float:
	match mobility():
		"crawl":
			return 1.3
		"wheelchair":
			return 3.8
	var s := base_speed
	if parts.leg_l == "prosthetic" or parts.leg_r == "prosthetic":
		s *= 0.9
	if sprinting:
		s *= 1.6
	return s


func arm_factor() -> float:
	if parts.arm_r == "ok":
		return 1.0
	if parts.arm_r == "prosthetic":
		return 0.85
	if parts.arm_l != "lost":
		return 0.65
	return 0.0


func can_attack() -> bool:
	return arm_factor() > 0.0


func can_shoot() -> bool:
	return ranged and parts.arm_l != "lost" and parts.arm_r != "lost"


func weapon_damage() -> float:
	if weapon != "" and ItemDB.ITEMS.has(weapon):
		return float(ItemDB.ITEMS[weapon].get("damage", base_damage))
	return base_damage


func total_armor() -> float:
	var a := armor
	if armor_item != "" and ItemDB.ITEMS.has(armor_item):
		a += float(ItemDB.ITEMS[armor_item].get("armor", 0.0))
	return a


func eyes_lost() -> int:
	var n := 0
	for e in ["eye_l", "eye_r"]:
		if parts[e] == "lost":
			n += 1
	return n


func count_item(id: String) -> int:
	return int(inventory.get(id, 0))


func add_item(id: String, n := 1) -> void:
	inventory[id] = count_item(id) + n
	if inventory[id] <= 0:
		inventory.erase(id)


# --- per-frame ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_cd = maxf(0.0, attack_cd - delta)
	if _pending_hit >= 0.0:
		_pending_hit -= delta
		if _pending_hit < 0.0:
			_resolve_melee()
	if bleeding > 0.0:
		hp -= bleeding * delta
		if hp <= 0.0:
			die(null)
			return

	_brain(delta)

	var spd := speed()
	var target_v := move_dir * spd
	var k := clampf((12.0 if is_on_floor() else 2.5) * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, target_v.x, k)
	velocity.z = lerpf(velocity.z, target_v.z, k)
	if is_on_floor():
		if want_jump and mobility() == "walk":
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	want_jump = false
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, face_yaw, clampf(10.0 * delta, 0.0, 1.0))

	if Game.world:
		var gh: float = Game.world.height_at(global_position.x, global_position.z)
		if global_position.y < gh - 3.0:
			global_position.y = gh + 0.5
			velocity.y = 0.0
	model.animate(delta, Vector2(velocity.x, velocity.z).length(), is_on_floor(), mobility())


## Overridden by Player (input) and NPC (AI). Sets move_dir, face_yaw, want_jump.
func _brain(_delta: float) -> void:
	pass


# --- combat ---------------------------------------------------------------

func try_attack(part := "") -> bool:
	if dead or attack_cd > 0.0 or not can_attack():
		return false
	attack_cd = 0.85 if arm_factor() >= 0.85 else 1.15
	_pending_hit = 0.2
	_pending_part = part
	model.play_attack()
	return true


func _resolve_melee() -> void:
	var fwd := -global_transform.basis.z
	var reach := 2.3 * maxf(model_scale, 1.0)
	var best = null
	var best_score := 1e9
	for a in get_tree().get_nodes_in_group("actors"):
		if a == self or a.dead:
			continue
		var to: Vector3 = a.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > reach + 0.35 * a.model_scale:
			continue
		if d > 0.3 and fwd.dot(to / d) < 0.3:
			continue
		var hostile := Game.are_hostile(self, a)
		if not hostile and not is_player:
			continue
		var score := d + (0.0 if hostile else 5.0)  # the player prefers enemies
		if score < best_score:
			best = a
			best_score = score
	if best:
		var dmg := weapon_damage() * arm_factor() * randf_range(0.8, 1.2)
		best.take_hit(self, dmg, _pending_part, true)
	_pending_part = ""


func shoot_at(point: Vector3) -> bool:
	if dead or attack_cd > 0.0 or not can_shoot():
		return false
	attack_cd = 1.1
	var from := global_position + Vector3(0, 1.45 * model_scale, 0) - global_transform.basis.z * 0.6
	var p := Projectile.new()
	Game.world.effects_root.add_child(p)
	p.launch(self, from, (point - from).normalized() * 45.0, 12.0)
	model.play_shoot()
	return true


func take_hit(attacker, amount: float, part := "", sharp := true) -> void:
	if dead:
		return
	if part == "":
		part = _random_part()
	var dmg := maxf(1.0, amount - total_armor())
	if part == "head":
		dmg *= 1.35
	hp -= dmg
	model.blood_burst(part)
	if attacker != null and is_instance_valid(attacker):
		var friendly_fire: bool = attacker.faction == faction and not attacker.is_player and not is_player
		if not friendly_fire:
			aggro[attacker.get_instance_id()] = Time.get_ticks_msec()
			_on_attacked(attacker)
			if attacker.is_player and not is_player:
				Game.on_player_hit(self)
	if part in LIMBS:
		if parts[part] == "ok":
			limb_hp[part] = float(limb_hp.get(part, 25.0)) - dmg
			if limb_hp[part] <= 0.0 and sharp and randf() < 0.65:
				sever(part, attacker)
	elif part == "head":
		limb_hp["head"] = float(limb_hp.get("head", 30.0)) - dmg
		if limb_hp["head"] <= 0.0 and randf() < 0.55:
			limb_hp["head"] = 30.0
			var left := []
			for e in ["eye_l", "eye_r"]:
				if parts[e] == "ok":
					left.append(e)
			if not left.is_empty():
				gouge_eye(left.pick_random(), attacker)
	if hp <= 0.0:
		die(attacker)
	elif is_player and Game.hud:
		Game.hud.flash_damage()


func _random_part() -> String:
	var r := randf()
	if r < 0.12:
		return "head"
	if r < 0.5:
		return "torso"
	if r < 0.62:
		return "arm_l"
	if r < 0.74:
		return "arm_r"
	if r < 0.87:
		return "leg_l"
	return "leg_r"


## Virtual: react to being attacked.
func _on_attacked(_attacker) -> void:
	pass


# --- injuries -------------------------------------------------------------

func sever(part: String, attacker = null) -> void:
	if parts.get(part, "") != "ok":
		return
	var xform: Transform3D = model.pivots[part].global_transform
	var limb := model.make_severed_limb(part)
	parts[part] = "lost"
	bleeding += 1.6 if part.begins_with("leg") else 1.2
	model.set_part(part, "lost")
	model.set_bleeding(true)
	if limb and Game.world:
		var away := Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1))
		if attacker != null and is_instance_valid(attacker):
			away += (global_position - attacker.global_position).normalized() * 2.0
		Game.world.add_debris(limb, xform, away)
	if is_player:
		Game.post("Your %s has been cut off! You are bleeding: use a bandage (B) or find a healer!" % PART_NAMES[part], Color(1, 0.3, 0.3))
	elif attacker != null and is_instance_valid(attacker) and attacker.is_player:
		Game.post("You cut off %s's %s!" % [display_name, PART_NAMES[part]], Color(1, 0.75, 0.3))


func gouge_eye(eye: String, attacker = null) -> void:
	if parts.get(eye, "") != "ok":
		return
	parts[eye] = "lost"
	bleeding += 0.4
	model.set_part(eye, "lost")
	model.set_bleeding(true)
	if is_player:
		Game.post("Your %s has been gouged out! Half of the world went dark." % PART_NAMES[eye], Color(1, 0.3, 0.3))
	elif attacker != null and is_instance_valid(attacker) and attacker.is_player:
		Game.post("You gouged out %s's %s!" % [display_name, PART_NAMES[eye]], Color(1, 0.75, 0.3))


func apply_bandage() -> bool:
	if bleeding <= 0.0:
		return false
	bleeding = 0.0
	model.set_bleeding(false)
	return true


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


## kind: "arm", "leg" or "eye". Returns false if nothing is missing.
func install_prosthesis(kind: String) -> bool:
	var order: Array = {"arm": ["arm_r", "arm_l"], "leg": ["leg_l", "leg_r"], "eye": ["eye_r", "eye_l"]}.get(kind, [])
	for p in order:
		if parts[p] == "lost":
			parts[p] = "prosthetic"
			limb_hp[p] = 25.0
			model.set_part(p, "prosthetic")
			apply_bandage()
			return true
	return false


func has_lost(kind: String) -> bool:
	for p in parts:
		if p.begins_with(kind) and parts[p] == "lost":
			return true
	return false


func die(killer) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	remove_from_group("actors")
	remove_from_group("interactable")
	var push := Vector3(0, 1.5, 0)
	if killer != null and is_instance_valid(killer):
		push += (global_position - killer.global_position).normalized() * 4.0
	var corpse := Corpse.new()
	corpse.display_name = display_name
	corpse.gold = gold if not is_player else 0
	corpse.items = _loot() if not is_player else {}
	Game.world.add_corpse(corpse)
	model.reparent(corpse, true)
	model.set_bleeding(false)
	corpse.build_from_model(model, velocity, push * 10.0)
	model = null
	Game.actor_killed.emit(self, killer)
	died.emit(self, killer)
	if is_player:
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		if Game.hud:
			Game.hud.show_death()
	else:
		queue_free()


func _loot() -> Dictionary:
	var items := inventory.duplicate()
	if randf() < 0.4:
		items["bandage"] = int(items.get("bandage", 0)) + 1
	if weapon != "" and randf() < 0.25:
		items[weapon] = int(items.get(weapon, 0)) + 1
	return items


# --- save / load ----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"uid": uid, "faction": faction, "role": role, "name": display_name,
		"pos": [global_position.x, global_position.y, global_position.z], "yaw": rotation.y,
		"hp": hp, "max_hp": max_hp, "speed": base_speed, "damage": base_damage, "armor": armor,
		"gold": gold, "weapon": weapon, "armor_item": armor_item, "inventory": inventory,
		"scale": model_scale, "ranged": ranged, "parts": parts, "limb_hp": limb_hp,
		"bleeding": bleeding, "wheelchair": has_wheelchair, "use_wheelchair": use_wheelchair,
	}


func from_dict(d: Dictionary) -> void:
	uid = str(d.get("uid", ""))
	faction = int(d.get("faction", 0))
	role = str(d.get("role", "warrior"))
	display_name = str(d.get("name", "Someone"))
	var p: Array = d.get("pos", [0, 0, 0])
	position = Vector3(p[0], p[1] + 0.2, p[2])
	face_yaw = float(d.get("yaw", 0.0))
	hp = float(d.get("hp", 100))
	max_hp = float(d.get("max_hp", 100))
	base_speed = float(d.get("speed", 4.2))
	base_damage = float(d.get("damage", 9))
	armor = float(d.get("armor", 0))
	gold = int(d.get("gold", 0))
	weapon = str(d.get("weapon", ""))
	armor_item = str(d.get("armor_item", ""))
	inventory = {}
	for k in d.get("inventory", {}):
		inventory[k] = int(d.inventory[k])
	model_scale = float(d.get("scale", 1.0))
	ranged = bool(d.get("ranged", false))
	for k in d.get("parts", {}):
		parts[k] = str(d.parts[k])
	limb_hp = {}
	for k in d.get("limb_hp", {}):
		limb_hp[k] = float(d.limb_hp[k])
	bleeding = float(d.get("bleeding", 0.0))
	has_wheelchair = bool(d.get("wheelchair", false))
	use_wheelchair = bool(d.get("use_wheelchair", true))
