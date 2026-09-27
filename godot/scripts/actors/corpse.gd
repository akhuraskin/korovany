class_name Corpse
extends Node3D
## A 3D ragdoll corpse. Each remaining body part becomes a rigid body,
## joined to the torso. Corpses can be searched for loot.

const SPECS := {
	# part: [shape, dims, collision offset y, mass]
	"torso": ["box", Vector3(0.5, 0.66, 0.3), 0.33, 20.0],
	"head": ["sphere", Vector3(0.17, 0, 0), 0.19, 5.0],
	"arm_l": ["capsule", Vector3(0.08, 0.7, 0), -0.32, 3.0],
	"arm_r": ["capsule", Vector3(0.08, 0.7, 0), -0.32, 3.0],
	"leg_l": ["capsule", Vector3(0.1, 0.95, 0), -0.45, 6.0],
	"leg_r": ["capsule", Vector3(0.1, 0.95, 0), -0.45, 6.0],
}

var display_name := ""
var gold := 0
var items := {}
var appearance := {}
var bodies := {}
var _freeze_t := 8.0


func _ready() -> void:
	add_to_group("corpses")
	add_to_group("interactable")


## Turns an existing (already posed) Humanoid into a ragdoll.
func build_from_model(model: Humanoid, vel: Vector3, push: Vector3) -> void:
	appearance = model.appearance.duplicate(true)
	var s := model.scale.x
	for part in Humanoid.PARTS:
		if model.parts.get(part, "ok") == "lost":
			continue
		var pivot: Node3D = model.pivots[part]
		var spec: Array = SPECS[part]
		var body := RigidBody3D.new()
		body.name = part
		body.collision_layer = 4
		body.collision_mask = 1 | 4
		body.mass = spec[3]
		body.linear_damp = 0.3
		body.angular_damp = 1.5
		add_child(body)
		body.global_transform = pivot.global_transform.orthonormalized()
		pivot.reparent(body, true)
		var cs := CollisionShape3D.new()
		cs.shape = _shape(spec, s)
		cs.position = Vector3(0, spec[2] * s, 0)
		body.add_child(cs)
		body.linear_velocity = vel
		bodies[part] = body
	var torso: RigidBody3D = bodies["torso"]
	for part in bodies:
		if part == "torso":
			continue
		var b: RigidBody3D = bodies[part]
		var j := ConeTwistJoint3D.new()
		add_child(j)
		# twist axis (X) along the limb
		j.global_transform = Transform3D(b.global_basis * Basis(Vector3.BACK, -PI * 0.5), b.global_position)
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(35.0 if part == "head" else 60.0))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(25.0))
		j.node_a = j.get_path_to(torso)
		j.node_b = j.get_path_to(b)
	torso.apply_central_impulse(push)
	model.queue_free()


## Rebuilds a corpse from a save file.
func restore(d: Dictionary) -> void:
	display_name = str(d.get("name", ""))
	gold = int(d.get("gold", 0))
	items = {}
	for k in d.get("items", {}):
		items[k] = int(d.items[k])
	var p: Array = d.get("pos", [0, 0, 0])
	var model := Humanoid.new()
	add_child(model)
	model.global_position = Vector3(p[0], p[1] + 0.3, p[2])
	var app: Dictionary = d.get("app", {})
	model.build(app)
	build_from_model(model, Vector3.ZERO, Vector3(randf_range(-20, 20), 0, randf_range(-20, 20)))


func _shape(spec: Array, s: float) -> Shape3D:
	var dims: Vector3 = spec[1] * s
	match spec[0]:
		"box":
			var b := BoxShape3D.new()
			b.size = dims
			return b
		"sphere":
			var sp := SphereShape3D.new()
			sp.radius = dims.x
			return sp
	var c := CapsuleShape3D.new()
	c.radius = dims.x
	c.height = dims.y
	return c


func _physics_process(delta: float) -> void:
	_freeze_t -= delta
	if _freeze_t <= 0.0:
		for b in bodies.values():
			b.freeze = true
		set_physics_process(false)


func interact_position() -> Vector3:
	if bodies.has("torso") and is_instance_valid(bodies["torso"]):
		return bodies["torso"].global_position
	return global_position


func can_interact(_p) -> bool:
	return gold > 0 or not items.is_empty()


func interact_text(_p) -> String:
	return "E: Search the body of %s" % display_name


func interact(p) -> void:
	var found: Array = []
	if gold > 0:
		p.gold += gold
		found.append("%d gold" % gold)
		gold = 0
	for id in items:
		p.add_item(id, items[id])
		found.append("%s x%d" % [ItemDB.name_of(id), items[id]])
	items = {}
	Game.post("You found: " + ", ".join(found), Color(1, 0.9, 0.5))


func to_dict() -> Dictionary:
	var pos := interact_position()
	return {"name": display_name, "gold": gold, "items": items, "app": appearance, "pos": [pos.x, pos.y, pos.z]}
