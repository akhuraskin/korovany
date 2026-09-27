class_name Projectile
extends Node3D
## An arrow. Moves each physics step and ray-casts the path it covered.

var shooter = null
var vel := Vector3.ZERO
var damage := 12.0
var life := 6.0
var stuck := false


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.03, 0.03, 0.8)
	m.material = Humanoid.mat(Color(0.45, 0.3, 0.15))
	mi.mesh = m
	add_child(mi)


func launch(from_actor, from: Vector3, velocity: Vector3, dmg: float) -> void:
	shooter = from_actor
	global_position = from
	vel = velocity
	damage = dmg
	_orient()


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if stuck:
		return
	vel.y -= 4.0 * delta
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	if shooter != null and is_instance_valid(shooter):
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		var c = hit.collider
		if c is Actor and not c.dead:
			c.take_hit(shooter if is_instance_valid(shooter) else null, damage, "", false)
			queue_free()
			return
		stuck = true
		life = 8.0
		return
	global_position = to
	_orient()


func _orient() -> void:
	var d := vel.normalized()
	if d.length() > 0.5 and absf(d.y) < 0.99:
		look_at(global_position + d, Vector3.UP)
