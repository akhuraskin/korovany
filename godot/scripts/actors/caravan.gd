class_name Caravan
extends Node3D
## A trade caravan: an ox pulling a covered wagon along a road,
## escorted by guards. Kill or dodge the guards and rob it (E).

var cid := 0
var route: Array = []
var seg := 0
var speed := 2.6
var looted := false
var gold := 0
var cargo := {}
var guards: Array = []
var owner_faction := Factions.HUMANS
var _cover: MeshInstance3D


func setup(id: int, pts: Array) -> void:
	cid = id
	route = pts
	gold = randi_range(60, 160)
	cargo = {"goods": randi_range(2, 4)}
	if randf() < 0.6:
		cargo["silk"] = randi_range(1, 2)


func _ready() -> void:
	add_to_group("caravans")
	add_to_group("interactable")
	var wood := Color(0.45, 0.3, 0.16)
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0, 2.2, 3.8)
	cs.shape = bs
	cs.position = Vector3(0, 1.3, 0.8)
	body.add_child(cs)
	add_child(body)
	_part("box", Vector3(1.8, 0.5, 3.4), Vector3(0, 0.9, 0.8), wood)
	_cover = _part("box", Vector3(1.7, 1.2, 3.0), Vector3(0, 1.75, 0.8), Color(0.92, 0.87, 0.74))
	for sx in [-1, 1]:
		for sz in [-0.4, 2.0]:
			var w := _part("cylinder", Vector3(0.45, 0.12, 0), Vector3(0.95 * sx, 0.45, sz), Color(0.3, 0.2, 0.1))
			w.rotation.z = PI * 0.5
	# the ox
	var ox := Color(0.4, 0.28, 0.2)
	_part("box", Vector3(0.9, 0.9, 1.8), Vector3(0, 1.2, -2.2), ox)
	_part("box", Vector3(0.5, 0.5, 0.6), Vector3(0, 1.5, -3.3), ox)
	for sx in [-0.3, 0.3]:
		for sz in [-2.8, -1.6]:
			_part("box", Vector3(0.18, 0.8, 0.18), Vector3(sx, 0.4, sz), ox)
		var horn := _part("cylinder", Vector3(0.04, 0.4, 0), Vector3(sx * 1.2, 1.8, -3.3), Color(0.9, 0.9, 0.8))
		horn.rotation.z = sx * 2.5
	_part("box", Vector3(0.1, 0.1, 1.2), Vector3(0, 1.0, -1.0), wood)


func _part(kind: String, dims: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if kind == "box":
		var b := BoxMesh.new()
		b.size = dims
		mi.mesh = b
	else:
		var c := CylinderMesh.new()
		c.top_radius = dims.x
		c.bottom_radius = dims.x
		c.height = dims.y
		mi.mesh = c
	mi.material_override = Humanoid.mat(color)
	mi.position = pos
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	if looted or _guards_fighting():
		return
	if seg >= route.size() - 1:
		_arrive()
		return
	var target: Vector3 = route[seg + 1]
	var to := target - global_position
	to.y = 0.0
	if to.length() < 1.0:
		seg += 1
		return
	var dir := to.normalized()
	var pos := global_position + dir * speed * delta
	pos.y = Game.world.height_at(pos.x, pos.z)
	global_position = pos
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(3.0 * delta, 0.0, 1.0))


func _guards_fighting() -> bool:
	for g in guards:
		if is_instance_valid(g) and not g.dead and g.target != null:
			return true
	return false


func _arrive() -> void:
	var p = Game.player
	if p != null and is_instance_valid(p) and global_position.distance_to(p.global_position) < 60.0:
		return  # don't vanish in front of the player
	for g in guards:
		if is_instance_valid(g):
			g.queue_free()
	queue_free()


func interact_position() -> Vector3:
	return global_position + global_basis * Vector3(0, 1, 0.8)


func can_interact(_p) -> bool:
	return not looted


func interact_text(_p) -> String:
	return "E: Rob the caravan!"


func interact(p) -> void:
	looted = true
	p.gold += gold
	var got := ["%d gold" % gold]
	for id in cargo:
		p.add_item(id, cargo[id])
		got.append("%s x%d" % [ItemDB.name_of(id), cargo[id]])
	Game.post("You robbed the caravan: " + ", ".join(got), Color(1, 0.85, 0.3))
	Game.change_reputation(owner_faction, -25, "caravan robbery")
	_cover.material_override = Humanoid.mat(Color(0.5, 0.45, 0.4))
	for g in guards:
		if is_instance_valid(g) and not g.dead:
			g.aggro[p.get_instance_id()] = Time.get_ticks_msec()
			g.target = p
	if Game.director:
		Game.director.on_caravan_robbed(self, p)


func to_dict() -> Dictionary:
	var pts: Array = []
	for v in route:
		pts.append([v.x, v.y, v.z])
	var pos := global_position
	return {
		"cid": cid, "route": pts, "seg": seg, "looted": looted, "gold": gold, "cargo": cargo,
		"pos": [pos.x, pos.y, pos.z], "yaw": rotation.y,
	}


func from_dict(d: Dictionary) -> void:
	cid = int(d.get("cid", 0))
	route = []
	for v in d.get("route", []):
		route.append(Vector3(v[0], v[1], v[2]))
	seg = int(d.get("seg", 0))
	looted = bool(d.get("looted", false))
	gold = int(d.get("gold", 0))
	cargo = {}
	for k in d.get("cargo", {}):
		cargo[k] = int(d.cargo[k])
	var p: Array = d.get("pos", [0, 0, 0])
	position = Vector3(p[0], p[1], p[2])
	rotation.y = float(d.get("yaw", 0.0))
