class_name Humanoid
extends Node3D
## Procedural 3D body built from separate parts so that arms, legs and
## eyes can be lost, replaced by prostheses, and turned into ragdolls.
## The character faces -Z. Its left side is -X.

const SKIN := Color(0.86, 0.68, 0.55)
const WOOD := Color(0.5, 0.33, 0.17)
const STEEL := Color(0.72, 0.74, 0.78)
const BLOOD := Color(0.5, 0.02, 0.02)
const ATTACK_TIME := 0.4
const PARTS := ["torso", "head", "arm_l", "arm_r", "leg_l", "leg_r"]

static var _mats := {}
static var _mesh_cache := {}

var appearance := {}
var parts := {}
var pose: Node3D
var pivots := {}
var flesh := {}
var prosthesis := {}
var stumps := {}
var eyes := {}
var sword: Node3D
var bow: Node3D
var wheelchair: Node3D
var blood: CPUParticles3D
var drip: CPUParticles3D
var mobility := "walk"
var walk_phase := 0.0
var attack_t := 0.0
var shoot_t := 0.0


static func mat(c: Color, metal := 0.0, rough := 0.85, glow := false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), metal, rough, glow]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metal
		m.roughness = rough
		if glow:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 1.5
		_mats[key] = m
	return _mats[key]


static func palette(faction: int, role: String) -> Dictionary:
	var p := {
		"skin": SKIN, "tunic": Color(0.35, 0.4, 0.6), "pants": Color(0.3, 0.25, 0.2),
		"boots": Color(0.2, 0.14, 0.08), "belt": Color(0.25, 0.16, 0.08), "hat": "cap",
		"hat_color": Color(0.4, 0.3, 0.2), "cape": Color(0.5, 0.1, 0.1),
	}
	match faction:
		Factions.EMPIRE:
			p.tunic = Color(0.66, 0.1, 0.1)
			p.pants = Color(0.25, 0.22, 0.2)
			p.hat = "helmet"
			p.hat_color = STEEL
			p.belt = Color(0.8, 0.65, 0.2)
		Factions.ELVES:
			p.skin = Color(0.93, 0.82, 0.7)
			p.tunic = Color(0.2, 0.46, 0.18)
			p.pants = Color(0.36, 0.26, 0.12)
			p.hat = "hood"
			p.hat_color = Color(0.15, 0.35, 0.13)
		Factions.VILLAIN:
			p.skin = Color(0.62, 0.64, 0.56)
			p.tunic = Color(0.16, 0.1, 0.2)
			p.pants = Color(0.1, 0.09, 0.1)
			p.hat = "horns"
			p.hat_color = Color(0.1, 0.08, 0.08)
			p.cape = Color(0.3, 0.05, 0.35)
	match role:
		"merchant":
			p.tunic = Color(0.55, 0.35, 0.6)
			p.hat = "cap"
			p.hat_color = Color(0.8, 0.65, 0.2)
		"healer":
			p.tunic = Color(0.92, 0.92, 0.88)
			p.hat = "none"
		"civilian":
			p.hat = "none" if randf() < 0.5 else "cap"
			p.tunic = [Color(0.35, 0.4, 0.6), Color(0.6, 0.5, 0.3), Color(0.45, 0.55, 0.4)].pick_random()
		"commander":
			p.belt = Color(0.95, 0.8, 0.2)
			p.hat_color = Color(0.9, 0.75, 0.25)
		"boss":
			p.tunic = Color(0.08, 0.05, 0.08)
			p.hat = "crown"
			p.hat_color = Color(0.1, 0.1, 0.1)
			p.cape = Color(0.5, 0.02, 0.05)
	return p


func build(app: Dictionary) -> void:
	appearance = app
	var faction := int(app.get("faction", 0))
	var role := str(app.get("role", "warrior"))
	var pal := palette(faction, role)
	scale = Vector3.ONE * float(app.get("scale", 1.0))
	pose = Node3D.new()
	pose.name = "Pose"
	add_child(pose)

	var torso := _pivot("torso", Vector3(0, 0.95, 0))
	_add(torso, "box", Vector3(0.5, 0.64, 0.28), Vector3(0, 0.33, 0), pal.tunic)
	_add(torso, "box", Vector3(0.52, 0.08, 0.3), Vector3(0, 0.04, 0), pal.belt)
	if role in ["commander", "boss"] or (faction == Factions.VILLAIN and role == "player"):
		_add(torso, "box", Vector3(0.5, 0.95, 0.04), Vector3(0, 0.2, 0.17), pal.cape)

	var head := _pivot("head", Vector3(0, 1.59, 0))
	_add(head, "sphere", Vector3(0.17, 0.34, 0), Vector3(0, 0.19, 0), pal.skin)
	for side in [-1, 1]:
		eyes["eye_l" if side < 0 else "eye_r"] = _add(head, "sphere", Vector3(0.033, 0.066, 0), Vector3(0.066 * side, 0.22, -0.15), Color(0.06, 0.06, 0.08))
	_hat(head, pal, faction)

	for side in [-1, 1]:
		var pname := "arm_l" if side < 0 else "arm_r"
		var arm := _pivot(pname, Vector3(0.33 * side, 1.5, 0))
		var f := _group(arm, "Flesh")
		_add(f, "capsule", Vector3(0.075, 0.62, 0), Vector3(0, -0.3, 0), pal.tunic)
		_add(f, "sphere", Vector3(0.07, 0.14, 0), Vector3(0, -0.63, 0), pal.skin)
		flesh[pname] = f
		var pr := _group(arm, "Prosthesis")
		_add(pr, "cylinder", Vector3(0.05, 0.6, 0), Vector3(0, -0.3, 0), WOOD)
		_add(pr, "sphere", Vector3(0.06, 0.12, 0), Vector3(0, -0.63, 0), STEEL)
		pr.visible = false
		prosthesis[pname] = pr
		stumps[pname] = _add(torso, "sphere", Vector3(0.085, 0.17, 0), Vector3(0.3 * side, 0.55, 0), BLOOD)
		stumps[pname].visible = false

	for side in [-1, 1]:
		var pname := "leg_l" if side < 0 else "leg_r"
		var leg := _pivot(pname, Vector3(0.12 * side, 0.93, 0))
		var f := _group(leg, "Flesh")
		_add(f, "capsule", Vector3(0.1, 0.86, 0), Vector3(0, -0.43, 0), pal.pants)
		_add(f, "box", Vector3(0.14, 0.12, 0.26), Vector3(0, -0.87, -0.05), pal.boots)
		flesh[pname] = f
		var pr := _group(leg, "Prosthesis")
		_add(pr, "cylinder", Vector3(0.1, 0.14, 0), Vector3(0, -0.07, 0), WOOD)
		_add(pr, "cylinder", Vector3(0.035, 0.8, 0), Vector3(0, -0.53, 0), WOOD)
		pr.visible = false
		prosthesis[pname] = pr
		stumps[pname] = _add(torso, "sphere", Vector3(0.1, 0.2, 0), Vector3(0.12 * side, -0.02, 0), BLOOD)
		stumps[pname].visible = false

	if role not in ["civilian", "merchant", "healer"]:
		sword = Node3D.new()
		sword.name = "Sword"
		sword.position = Vector3(0, -0.64, 0)
		pivots["arm_r"].add_child(sword)
		var blade := STEEL if faction != Factions.VILLAIN else Color(0.15, 0.15, 0.18)
		_add(sword, "box", Vector3(0.05, 0.025, 0.9), Vector3(0, 0, -0.5), blade, 0.8)
		_add(sword, "box", Vector3(0.24, 0.04, 0.04), Vector3(0, 0, -0.05), pal.belt)
	if app.get("ranged", false):
		bow = Node3D.new()
		bow.name = "Bow"
		bow.position = Vector3(0, -0.64, 0)
		pivots["arm_l"].add_child(bow)
		_add(bow, "box", Vector3(0.035, 0.035, 1.2), Vector3(0, 0, -0.05), WOOD)
		_add(bow, "box", Vector3(0.008, 0.008, 1.1), Vector3(0, -0.12, -0.05), Color(0.9, 0.9, 0.85))

	wheelchair = Node3D.new()
	wheelchair.name = "Wheelchair"
	add_child(wheelchair)
	var dark := Color(0.2, 0.2, 0.22)
	_add(wheelchair, "box", Vector3(0.55, 0.08, 0.5), Vector3(0, 0.5, 0), dark)
	_add(wheelchair, "box", Vector3(0.55, 0.55, 0.06), Vector3(0, 0.8, 0.26), dark)
	for side in [-1, 1]:
		var w := _add(wheelchair, "cylinder", Vector3(0.36, 0.05, 0), Vector3(0.33 * side, 0.36, 0.05), STEEL)
		w.rotation.z = PI * 0.5
		var s := _add(wheelchair, "cylinder", Vector3(0.1, 0.05, 0), Vector3(0.22 * side, 0.1, -0.3), dark)
		s.rotation.z = PI * 0.5
	wheelchair.visible = false

	blood = _particles(true)
	drip = _particles(false)

	parts = app.get("parts", {}).duplicate()
	for p in parts:
		set_part(p, parts[p])


func _pivot(pname: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pname
	n.position = pos
	pose.add_child(n)
	pivots[pname] = n
	return n


func _group(parent: Node3D, gname: String) -> Node3D:
	var n := Node3D.new()
	n.name = gname
	parent.add_child(n)
	return n


func _add(parent: Node3D, kind: String, dims: Vector3, pos: Vector3, color: Color, metal := 0.0) -> MeshInstance3D:
	var key := "%s|%s|%s|%s" % [kind, dims, color.to_html(), metal]
	if not _mesh_cache.has(key):
		var m: PrimitiveMesh
		match kind:
			"box":
				var b := BoxMesh.new()
				b.size = dims
				m = b
			"sphere":
				var sp := SphereMesh.new()
				sp.radius = dims.x
				sp.height = dims.y
				sp.radial_segments = 12
				sp.rings = 6
				m = sp
			"capsule":
				var c := CapsuleMesh.new()
				c.radius = dims.x
				c.height = dims.y
				c.radial_segments = 8
				c.rings = 2
				m = c
			_:
				var cy := CylinderMesh.new()
				cy.top_radius = 0.0 if kind == "cone" else dims.x
				cy.bottom_radius = dims.x
				cy.height = dims.y
				cy.radial_segments = 8 if kind == "cone" else 10
				m = cy
		m.material = mat(color, metal, 0.35 if metal > 0.0 else 0.85)
		_mesh_cache[key] = m
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_cache[key]
	mi.position = pos
	parent.add_child(mi)
	return mi


func _hat(head: Node3D, pal: Dictionary, faction: int) -> void:
	var c: Color = pal.hat_color
	match pal.hat:
		"helmet":
			_add(head, "cylinder", Vector3(0.18, 0.16, 0), Vector3(0, 0.3, 0), c, 0.7)
			_add(head, "cone", Vector3(0.18, 0.14, 0), Vector3(0, 0.45, 0), c, 0.7)
		"hood":
			_add(head, "cone", Vector3(0.19, 0.3, 0), Vector3(0, 0.38, 0.03), c)
		"horns":
			for side in [-1, 1]:
				var h := _add(head, "cone", Vector3(0.05, 0.22, 0), Vector3(0.12 * side, 0.36, 0), Color(0.85, 0.8, 0.7))
				h.rotation.z = -0.5 * side
		"crown":
			_add(head, "cylinder", Vector3(0.19, 0.1, 0), Vector3(0, 0.33, 0), c, 0.6)
			for i in 5:
				var a := i * TAU / 5.0
				_add(head, "cone", Vector3(0.04, 0.16, 0), Vector3(cos(a) * 0.15, 0.44, sin(a) * 0.15), Color(0.5, 0.05, 0.05))
		"cap":
			_add(head, "cylinder", Vector3(0.18, 0.1, 0), Vector3(0, 0.33, 0), c)
	if faction == Factions.ELVES:
		for side in [-1, 1]:
			var ear := _add(head, "cone", Vector3(0.035, 0.16, 0), Vector3(0.17 * side, 0.22, 0.02), pal.skin)
			ear.rotation.z = -1.1 * side


func _particles(one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = one_shot
	p.amount = 28 if one_shot else 8
	p.lifetime = 0.7 if one_shot else 0.8
	p.explosiveness = 0.95 if one_shot else 0.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0 if one_shot else 25.0
	p.initial_velocity_min = 1.5 if one_shot else 0.2
	p.initial_velocity_max = 3.5 if one_shot else 0.8
	p.local_coords = false
	var m := BoxMesh.new()
	m.size = Vector3(0.045, 0.045, 0.045)
	m.material = mat(Color(0.65, 0.02, 0.02), 0.0, 0.3)
	p.mesh = m
	add_child(p)
	if not one_shot:
		p.position = Vector3(0, 1.1, 0)
	return p


# --- state ----------------------------------------------------------------

func set_part(part: String, state: String) -> void:
	parts[part] = state
	appearance["parts"] = parts
	if eyes.has(part):
		var e: MeshInstance3D = eyes[part]
		match state:
			"lost":
				e.material_override = mat(BLOOD)
				e.scale = Vector3.ONE * 1.4
			"prosthetic":
				e.material_override = mat(Color(0.45, 0.8, 1.0), 0.3, 0.1, true)
				e.scale = Vector3.ONE
			_:
				e.material_override = null
				e.scale = Vector3.ONE
		return
	if not flesh.has(part):
		return
	flesh[part].visible = state == "ok"
	prosthesis[part].visible = state == "prosthetic"
	stumps[part].visible = state == "lost"
	if part == "arm_r" and sword:
		sword.visible = state != "lost"
	if part == "arm_l" and bow:
		bow.visible = state != "lost"


func part_position(part: String) -> Vector3:
	match part:
		"head", "eye_l", "eye_r":
			return pivots["head"].global_position + Vector3(0, 0.2, 0)
		"torso":
			return pivots["torso"].global_position + Vector3(0, 0.35, 0)
	if pivots.has(part):
		return pivots[part].global_position
	return global_position + Vector3(0, 1.2, 0)


func blood_burst(part: String) -> void:
	blood.global_position = part_position(part)
	blood.restart()


func set_bleeding(on: bool) -> void:
	drip.emitting = on


func play_attack() -> void:
	attack_t = ATTACK_TIME


func play_shoot() -> void:
	shoot_t = 0.5


## A copy of the limb that flies off as a physics object.
func make_severed_limb(part: String) -> RigidBody3D:
	if not flesh.has(part):
		return null
	var s := scale.x
	var body := RigidBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 1 | 4
	body.mass = 3.0
	var copy: Node3D = flesh[part].duplicate()
	copy.visible = true
	copy.scale = Vector3.ONE * s
	body.add_child(copy)
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	var leg := part.begins_with("leg")
	sh.radius = (0.1 if leg else 0.08) * s
	sh.height = (0.95 if leg else 0.7) * s
	cs.shape = sh
	cs.position.y = (-0.45 if leg else -0.32) * s
	body.add_child(cs)
	_add(copy, "sphere", Vector3(0.08, 0.16, 0), Vector3.ZERO, BLOOD)
	return body


# --- animation ------------------------------------------------------------

func animate(delta: float, speed: float, on_floor: bool, mob: String) -> void:
	if mob != mobility:
		_set_mobility(mob)
	var amp := clampf(speed / 4.5, 0.0, 1.0)
	if speed > 0.1:
		walk_phase += delta * (3.0 + speed * 1.6)
	var s := sin(walk_phase)
	var arm_l: Node3D = pivots["arm_l"]
	var arm_r: Node3D = pivots["arm_r"]
	var leg_l: Node3D = pivots["leg_l"]
	var leg_r: Node3D = pivots["leg_r"]
	match mobility:
		"walk":
			if on_floor:
				leg_l.rotation.x = s * 0.7 * amp
				leg_r.rotation.x = -s * 0.7 * amp
			else:
				leg_l.rotation.x = 0.6
				leg_r.rotation.x = 0.15
			arm_l.rotation.x = -s * 0.5 * amp
			arm_r.rotation.x = s * 0.5 * amp
			pose.position.y = absf(s) * 0.04 * amp
		"crawl":
			arm_l.rotation.x = 2.7 + s * 0.5 * amp
			arm_r.rotation.x = 2.7 - s * 0.5 * amp
			leg_l.rotation.x = s * 0.15 * amp
			leg_r.rotation.x = -s * 0.15 * amp
		"wheelchair":
			leg_l.rotation.x = 1.45
			leg_r.rotation.x = 1.45
			arm_l.rotation.x = 0.3 + s * 0.4 * amp
			arm_r.rotation.x = 0.3 + s * 0.4 * amp
	if attack_t > 0.0:
		attack_t -= delta
		var k := 1.0 - attack_t / ATTACK_TIME
		var r := lerpf(2.9, 0.4, ease(k, 0.4)) if k > 0.25 else lerpf(0.4, 2.9, k * 4.0)
		if parts.get("arm_r", "ok") != "lost":
			arm_r.rotation.x = r
		else:
			arm_l.rotation.x = r
	if shoot_t > 0.0:
		shoot_t -= delta
		arm_l.rotation.x = 1.55
		arm_r.rotation.x = 1.45


func _set_mobility(m: String) -> void:
	mobility = m
	wheelchair.visible = m == "wheelchair"
	match m:
		"crawl":
			pose.rotation.x = -1.35
			pose.position = Vector3(0, 0.22, 0.85)
		"wheelchair":
			pose.rotation.x = 0.0
			pose.position = Vector3(0, -0.42, 0)
		_:
			pose.rotation.x = 0.0
			pose.position = Vector3.ZERO
