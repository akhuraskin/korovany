class_name Player
extends Actor
## Third-person player controller: WASD, mouse look, jump, sprint,
## melee (LMB), bow (RMB), interact (E), bandage (B), potion (H).
## Aim decides where the blow lands: look up for the head (eyes),
## down for the legs.

var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var yaw := 0.0
var pitch := -0.2
var zoom := 3.4
var mouse_sens := 0.0025
var focus = null
var _focus_t := 0.0


func _ready() -> void:
	is_player = true
	super._ready()
	add_to_group("player")
	if yaw == 0.0:
		yaw = face_yaw
	cam_pivot = Node3D.new()
	cam_pivot.name = "CameraPivot"
	cam_pivot.top_level = true
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = zoom
	spring.collision_mask = 1
	spring.margin = 0.2
	spring.position.x = 0.45
	spring.add_excluded_object(get_rid())
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 900.0
	spring.add_child(camera)
	camera.current = true
	_update_camera()
	if not Game.ui_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if dead or Game.ui_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sens
		pitch = clampf(pitch - event.relative.y * mouse_sens, -1.25, 0.9)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.4, 1.5, 9.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.4, 1.5, 9.0)


func _brain(delta: float) -> void:
	_update_camera()
	move_dir = Vector3.ZERO
	if Game.ui_open:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move_dir = Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	if move_dir.length() > 1.0:
		move_dir = move_dir.normalized()
	sprinting = Input.is_action_pressed("sprint") and mobility() == "walk"
	if Input.is_action_just_pressed("jump"):
		want_jump = true
	if move_dir.length() > 0.1 or Input.is_action_pressed("attack") or Input.is_action_pressed("shoot"):
		face_yaw = yaw
	if Input.is_action_just_pressed("attack"):
		if not try_attack(aimed_part()) and not can_attack():
			Game.post("You have no arms to fight with! Get a prosthesis.", Color(1, 0.6, 0.3))
	if Input.is_action_just_pressed("shoot"):
		_shoot()
	if Input.is_action_just_pressed("interact") and focus != null and is_instance_valid(focus):
		focus.interact(self)
	if Input.is_action_just_pressed("bandage"):
		use_item("bandage")
	if Input.is_action_just_pressed("potion"):
		use_item("potion")
	_focus_t -= delta
	if _focus_t <= 0.0:
		_focus_t = 0.15
		_update_focus()


func _update_camera() -> void:
	var eye := 1.6
	match mobility():
		"crawl":
			eye = 0.7
		"wheelchair":
			eye = 1.2
	cam_pivot.global_position = global_position + Vector3(0, eye * model_scale, 0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	spring.spring_length = zoom


## Looking up aims at the head, looking down at the legs.
func aimed_part() -> String:
	if pitch > 0.12:
		return "head" if randf() < 0.6 else ""
	if pitch < -0.45:
		return ["leg_l", "leg_r"].pick_random() if randf() < 0.65 else ""
	if randf() < 0.35:
		return ["arm_l", "arm_r"].pick_random()
	return ""


func aim_name() -> String:
	if pitch > 0.12:
		return "head"
	if pitch < -0.45:
		return "legs"
	return "body / arms"


func _shoot() -> void:
	if not ranged:
		return
	if not can_shoot():
		Game.post("You need both hands to shoot a bow.", Color(1, 0.6, 0.3))
		return
	var from := camera.global_position
	var to := from - camera.global_basis.z * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	shoot_at(hit.position if not hit.is_empty() else to)


func _update_focus() -> void:
	var best = null
	var bd := 3.2
	for n in get_tree().get_nodes_in_group("interactable"):
		if n == self or not n.has_method("interact"):
			continue
		var d := global_position.distance_to(n.interact_position())
		if d < bd and n.can_interact(self):
			best = n
			bd = d
	focus = best
	if Game.hud:
		Game.hud.set_prompt(best.interact_text(self) if best != null else "")


func use_item(id: String) -> void:
	if count_item(id) <= 0:
		Game.post("You have no %s." % ItemDB.name_of(id).to_lower(), Color(1, 0.6, 0.3))
		return
	var item: Dictionary = ItemDB.ITEMS.get(id, {})
	match id:
		"bandage":
			if apply_bandage():
				add_item(id, -1)
				Game.post("You bandaged your wounds. The bleeding stopped.", Color(0.6, 1, 0.6))
			else:
				Game.post("You are not bleeding.")
		"potion":
			add_item(id, -1)
			heal(60.0)
			Game.post("You drink a healing potion.", Color(0.6, 1, 0.6))
		"wheelchair":
			add_item(id, -1)
			has_wheelchair = true
			use_wheelchair = true
			Game.post("You now own a wheelchair. It is used automatically when you are missing a leg.", Color(0.6, 1, 0.6))
		"bow":
			add_item(id, -1)
			ranged = true
			Game.post("You take up the bow (right mouse button).", Color(0.6, 1, 0.6))
		_:
			if item.has("prosthesis"):
				if install_prosthesis(item.prosthesis):
					add_item(id, -1)
					Game.post("You fit the %s." % ItemDB.name_of(id).to_lower(), Color(0.6, 1, 0.6))
				else:
					Game.post("You are not missing an %s." % item.prosthesis if item.prosthesis != "leg" else "You are not missing a leg.")
			elif item.get("slot", "") == "weapon":
				add_item(id, -1)
				if weapon != "":
					add_item(weapon, 1)
				weapon = id
				Game.post("You equip the %s." % ItemDB.name_of(id).to_lower())
			elif item.get("slot", "") == "armor":
				add_item(id, -1)
				if armor_item != "":
					add_item(armor_item, 1)
				armor_item = id
				Game.post("You put on the %s." % ItemDB.name_of(id).to_lower())
			else:
				Game.post("You can't use that. Sell it to a merchant.")


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["cam_yaw"] = yaw
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	yaw = float(d.get("cam_yaw", face_yaw))
