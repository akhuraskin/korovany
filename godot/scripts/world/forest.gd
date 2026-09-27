class_name Forest
extends Node3D
## Dense forest. Trees are grouped into cells. Each cell has two
## MultiMeshes: real 3D trees for close range and flat camera-facing
## "picture" impostors for far range. Godot's visibility ranges swap
## them with a crossfade, so distant trees are pictures and turn into
## 3D trees as you walk up to them.

const CELL := 40.0
const SWITCH_DIST := 75.0
const FADE := 10.0

const IMPOSTOR_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform sampler2D tex : source_color, filter_linear_mipmap;

void vertex() {
	// Fixed-Y billboard: turn the quad to face the camera plane.
	vec3 back = INV_VIEW_MATRIX[2].xyz;
	vec2 d = normalize(back.xz + vec2(0.0001, 0.0));
	vec3 right = vec3(d.y, 0.0, -d.x);
	VERTEX = right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
	NORMAL = vec3(d.x, 0.0, d.y);
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
"""

var tree_count := 0
var cell_count := 0
var _bodies: Array[RID] = []
var _trunk_shape := CylinderShape3D.new()
var _meshes := {}
var _impostors := {}


func build(world: World) -> void:
	_trunk_shape.radius = 0.35
	_trunk_shape.height = 4.0
	_make_tree_assets()
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var cells := {}

	# The dense elven forest (south-east quadrant).
	var step := 4.2
	var x := 22.0
	while x < 386.0:
		var z := 22.0
		while z < 386.0:
			var px := x + rng.randf_range(-1.6, 1.6)
			var pz := z + rng.randf_range(-1.6, 1.6)
			if rng.randf() < 0.9 and _can_place(world, px, pz, 5.0):
				_add(cells, world, px, pz, "fir" if rng.randf() < 0.7 else "oak", rng)
			z += step
		x += step

	# Sparse trees in the other three zones.
	step = 11.0
	x = -388.0
	while x < 388.0:
		var z := -388.0
		while z < 388.0:
			var px := x + rng.randf_range(-4.0, 4.0)
			var pz := z + rng.randf_range(-4.0, 4.0)
			z += step
			if px > 20.0 and pz > 20.0:
				continue
			var zone := world.zone_at(Vector3(px, 0, pz))
			var chance := 0.1
			if zone == Factions.VILLAIN:
				chance = 0.16
				if world.height_at(px, pz) > 42.0:
					continue
			if rng.randf() < chance and _can_place(world, px, pz, 6.0):
				var kind := "oak" if zone == Factions.HUMANS or zone == Factions.EMPIRE else "fir"
				_add(cells, world, px, pz, kind, rng)
		x += step

	_create_cells(cells)


func _exit_tree() -> void:
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()


func _can_place(world: World, x: float, z: float, road_clear: float) -> bool:
	if maxf(absf(x), absf(z)) > 385.0:
		return false
	if world.near_settlement(x, z, 8.0):
		return false
	return world.road_distance(x, z) > road_clear


func _add(cells: Dictionary, world: World, x: float, z: float, kind: String, rng: RandomNumberGenerator) -> void:
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	if not cells.has(key):
		cells[key] = {"fir": [], "oak": []}
	var s := rng.randf_range(0.8, 1.3)
	cells[key][kind].append([Vector3(x, world.height_at(x, z) - 0.2, z), s, rng.randf() * TAU])
	tree_count += 1


func _create_cells(cells: Dictionary) -> void:
	var space := get_world_3d().space
	for key in cells:
		var center := Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
		var ys := 0.0
		var n := 0
		for kind in cells[key]:
			for t in cells[key][kind]:
				ys += t[0].y
				n += 1
		center.y = ys / maxf(n, 1)
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.body_set_collision_layer(body, 1)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		_bodies.append(body)
		for kind in cells[key]:
			var list: Array = cells[key][kind]
			if list.is_empty():
				continue
			var near_mm := MultiMesh.new()
			near_mm.transform_format = MultiMesh.TRANSFORM_3D
			near_mm.mesh = _meshes[kind]
			near_mm.instance_count = list.size()
			var far_mm := MultiMesh.new()
			far_mm.transform_format = MultiMesh.TRANSFORM_3D
			far_mm.mesh = _impostors[kind]
			far_mm.instance_count = list.size()
			for i in list.size():
				var pos: Vector3 = list[i][0]
				var s: float = list[i][1]
				var local := pos - center
				near_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, list[i][2]).scaled(Vector3.ONE * s), local))
				# impostors must stay unrotated: the shader turns them to the camera
				far_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), local))
				PhysicsServer3D.body_add_shape(body, _trunk_shape.get_rid(), Transform3D(Basis(), pos + Vector3(0, 2.0, 0)))

			var near := MultiMeshInstance3D.new()
			near.multimesh = near_mm
			near.position = center
			near.visibility_range_end = SWITCH_DIST
			near.visibility_range_end_margin = FADE
			near.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(near)

			var far := MultiMeshInstance3D.new()
			far.multimesh = far_mm
			far.position = center
			far.visibility_range_begin = SWITCH_DIST
			far.visibility_range_begin_margin = FADE
			far.visibility_range_end = 520.0
			far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(far)
		cell_count += 1


# --- tree assets ----------------------------------------------------------

func _make_tree_assets() -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.33, 0.22, 0.13)
	bark.roughness = 1.0
	var needles := StandardMaterial3D.new()
	needles.albedo_color = Color(0.13, 0.3, 0.14)
	needles.roughness = 1.0
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.22, 0.42, 0.16)
	leaves.roughness = 1.0

	# Fir: trunk + three stacked cones, ~11 m tall.
	var fir := ArrayMesh.new()
	_append(fir, [[_cyl(0.28, 0.2, 3.5), Vector3(0, 1.75, 0)]], bark)
	_append(fir, [
		[_cyl(2.5, 0.0, 4.5), Vector3(0, 5.0, 0)],
		[_cyl(2.0, 0.0, 4.0), Vector3(0, 7.2, 0)],
		[_cyl(1.4, 0.0, 3.4), Vector3(0, 9.4, 0)],
	], needles)
	_meshes["fir"] = fir

	# Oak: trunk + blobby crown, ~9 m tall.
	var oak := ArrayMesh.new()
	_append(oak, [[_cyl(0.4, 0.3, 4.5), Vector3(0, 2.25, 0)]], bark)
	_append(oak, [
		[_sphere(2.8), Vector3(0, 6.0, 0)],
		[_sphere(2.0), Vector3(1.5, 6.8, 0.6)],
		[_sphere(2.1), Vector3(-1.3, 6.5, -0.8)],
		[_sphere(1.8), Vector3(0.2, 7.9, 0.3)],
	], leaves)
	_meshes["oak"] = oak

	_impostors["fir"] = _impostor_mesh(_draw_fir(), Vector2(5.4, 11.4))
	_impostors["oak"] = _impostor_mesh(_draw_oak(), Vector2(6.8, 9.6))


func _cyl(bottom: float, top: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = bottom
	m.top_radius = top
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 1.7
	m.radial_segments = 10
	m.rings = 6
	return m


func _append(target: ArrayMesh, pieces: Array, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece in pieces:
		st.append_from(piece[0], 0, Transform3D(Basis(), piece[1]))
	st.commit(target)
	target.surface_set_material(target.get_surface_count() - 1, material)


func _impostor_mesh(img: Image, size: Vector2) -> QuadMesh:
	img.generate_mipmaps()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = IMPOSTOR_SHADER
	sm.shader = sh
	sm.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(0, size.y * 0.5, 0)
	q.material = sm
	return q


## Paints the "picture" of a fir the same shape as the 3D fir.
func _draw_fir() -> Image:
	var w := 64
	var h := 136
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tiers := [[0.364, 0.759, 0.463], [0.193, 0.544, 0.37], [0.026, 0.325, 0.26]]  # top, bottom, half width (fractions)
	for py in h:
		var v := float(py) / h
		for px in w:
			var u := float(px) / w
			var c := Color(0, 0, 0, 0)
			if v > 0.6 and absf(u - 0.5) < 0.052:
				c = Color(0.3, 0.2, 0.12, 1)
			for t in tiers:
				if v >= t[0] and v <= t[1]:
					var k: float = (v - t[0]) / (t[1] - t[0])
					if absf(u - 0.5) < t[2] * k:
						var shade := 0.75 + 0.5 * u + randf_range(-0.08, 0.08)
						c = Color(0.12 * shade, 0.29 * shade, 0.13 * shade, 1)
			img.set_pixel(px, py, c)
	return img


func _draw_oak() -> Image:
	var w := 80
	var h := 112
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var blobs := [[0.5, 0.375, 0.29], [0.72, 0.29, 0.21], [0.31, 0.32, 0.22], [0.53, 0.18, 0.19]]
	for py in h:
		var v := float(py) / h
		for px in w:
			var u := float(px) / w
			var c := Color(0, 0, 0, 0)
			if v > 0.5 and absf(u - 0.5) < 0.05:
				c = Color(0.33, 0.22, 0.13, 1)
			for b in blobs:
				var d := Vector2((u - b[0]) * w / h, v - b[1]).length()
				if d < b[2]:
					var shade := 0.75 + 0.5 * u - v * 0.3 + randf_range(-0.08, 0.08)
					c = Color(0.22 * shade, 0.42 * shade, 0.16 * shade, 1)
			img.set_pixel(px, py, c)
	return img
