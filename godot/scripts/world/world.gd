class_name World
extends Node3D
## Builds the whole map procedurally: terrain with 4 zones, roads,
## the palace, the elven village, the human village, the old fort,
## the dense forest, lighting and sky.

const SIZE := 800.0
const BUILDING_LAYER := 8  # physics layer 4: walls and houses (also on layer 1)
const HALF := 400.0
const GRID := 160

const LOCATIONS := {
	"human_village": Vector3(-200, 0, 200),
	"palace": Vector3(-200, 0, -200),
	"elf_village": Vector3(210, 0, 210),
	"fort": Vector3(235, 0, -235),
	"crossroads": Vector3(0, 0, 0),
}
const FLAT_RADIUS := {
	"human_village": 55.0, "palace": 50.0, "elf_village": 36.0, "fort": 34.0, "crossroads": 14.0,
}
## Road ends at each settlement's gates (relative to its center).
const GATES := {
	"human_village": [Vector2(0, -30), Vector2(25, -15)],
	"palace": [Vector2(0, 32)],
	"elf_village": [Vector2(-20, -15)],
	"fort": [Vector2(1, 23)],
}
## Walled places: [ring half-size, point just outside the gate (relative)].
const WALL_RINGS := {
	"palace": [42.0, Vector2(0, 40)],
	"fort": [32.0, Vector2(1, 29)],
}
const LOCATION_NAMES := {
	"human_village": "Human village", "palace": "Emperor's palace",
	"elf_village": "Elven village", "fort": "Old fort", "crossroads": "Crossroads",
}
## Road polylines (x, z). Caravans travel along these.
const ROADS := {
	"village_palace": [Vector2(-200, 170), Vector2(-208, 60), Vector2(-196, -60), Vector2(-200, -168)],
	"village_cross": [Vector2(-175, 185), Vector2(-100, 110), Vector2(-40, 30), Vector2(0, 0)],
	"cross_palace": [Vector2(0, 0), Vector2(-60, -70), Vector2(-130, -140), Vector2(-185, -160), Vector2(-200, -168)],
	"cross_elves": [Vector2(0, 0), Vector2(70, 60), Vector2(130, 140), Vector2(190, 195)],
	"cross_fort": [Vector2(0, 0), Vector2(70, -60), Vector2(150, -150), Vector2(230, -190), Vector2(236, -212)],
}

var noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var flats: Array = []
var road_segments: Array = []
var locations := {}
var nav_nodes: Array = []   # Vector2 road-graph nodes (roads + settlement centers)
var nav_edges := {}         # node index -> Array of node indices

var actors_root: Node3D
var corpses_root: Node3D
var debris_root: Node3D
var effects_root: Node3D
var buildings: Node3D
var forest: Forest
var sun: DirectionalLight3D
var environment: Environment

var _mat_cache := {}


func _init() -> void:
	noise.seed = 1337
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	ridge_noise.seed = 7
	ridge_noise.frequency = 0.006
	for key in LOCATIONS:
		var p: Vector3 = LOCATIONS[key]
		flats.append([Vector2(p.x, p.z), FLAT_RADIUS[key], raw_height(p.x, p.z)])
	for key in ROADS:
		var pts: Array = ROADS[key]
		for i in pts.size() - 1:
			road_segments.append([pts[i], pts[i + 1]])
	for key in LOCATIONS:
		var p: Vector3 = LOCATIONS[key]
		locations[key] = Vector3(p.x, height_at(p.x, p.z), p.z)
	_build_nav()


func build() -> void:
	for n in ["Buildings", "Actors", "Corpses", "Debris", "Effects"]:
		var node := Node3D.new()
		node.name = n
		add_child(node)
	buildings = $Buildings
	actors_root = $Actors
	corpses_root = $Corpses
	debris_root = $Debris
	effects_root = $Effects
	_build_environment()
	_build_terrain()
	_build_palace()
	_build_elf_village()
	_build_human_village()
	_build_fort()
	_build_crossroads()
	forest = Forest.new()
	forest.name = "Forest"
	add_child(forest)
	forest.build(self)


# --- height & zones -------------------------------------------------------

func raw_height(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 5.0
	var depth := minf(x, -z)  # > 0 inside the Villain's quadrant
	var m := smoothstep(15.0, 150.0, depth)
	h += m * (10.0 + (ridge_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 30.0)
	h += smoothstep(260.0, 390.0, depth) * 45.0
	var edge := maxf(absf(x), absf(z))
	h += smoothstep(365.0, 400.0, edge) * 35.0
	return h


func height_at(x: float, z: float) -> float:
	var h := raw_height(x, z)
	var p := Vector2(x, z)
	for f in flats:
		var d := p.distance_to(f[0])
		var t := 1.0 - smoothstep(f[1], f[1] + 30.0, d)
		if t > 0.0:
			h = lerpf(h, f[2], t)
	return h


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


func zone_at(p: Vector3) -> int:
	if p.x < 0.0:
		return Factions.HUMANS if p.z > 0.0 else Factions.EMPIRE
	return Factions.ELVES if p.z > 0.0 else Factions.VILLAIN


func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	for s in road_segments:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func near_settlement(x: float, z: float, margin: float) -> bool:
	var p := Vector2(x, z)
	for f in flats:
		if p.distance_to(f[0]) < f[1] + margin:
			return true
	return false


func route(names: Array, reverse := false) -> Array:
	var pts: Array = []
	for n in names:
		for v in ROADS[n]:
			if pts.is_empty() or pts[-1] != v:
				pts.append(v)
	if reverse:
		pts.reverse()
	var out: Array = []
	for v in pts:
		out.append(Vector3(v.x, height_at(v.x, v.y), v.y))
	return out


# --- road-graph pathfinding ----------------------------------------------
# Long trips follow the roads; every settlement center is linked to the
# road ends at its gates, so troops leave walled places through the gate.

func _nav_node(v: Vector2) -> int:
	for i in nav_nodes.size():
		if nav_nodes[i].distance_to(v) < 1.0:
			return i
	nav_nodes.append(v)
	nav_edges[nav_nodes.size() - 1] = []
	return nav_nodes.size() - 1


func _nav_link(a: int, b: int) -> void:
	if a != b and not nav_edges[a].has(b):
		nav_edges[a].append(b)
		nav_edges[b].append(a)


func _build_nav() -> void:
	for key in ROADS:
		var pts: Array = ROADS[key]
		for i in pts.size() - 1:
			_nav_link(_nav_node(pts[i]), _nav_node(pts[i + 1]))
	# Settlement centers connect to their gates (the road ends), never to a
	# road point on the other side of a wall.
	for key in GATES:
		var c3: Vector3 = LOCATIONS[key]
		var c := _nav_node(Vector2(c3.x, c3.z))
		for g in GATES[key]:
			_nav_link(c, _nav_node(Vector2(c3.x, c3.z) + g))
	# A ring of waypoints around each walled place, joined in front of its
	# (south) gate, so troops can walk around the walls to get in or out.
	for key in WALL_RINGS:
		var c3: Vector3 = LOCATIONS[key]
		var c := Vector2(c3.x, c3.z)
		var r: float = WALL_RINGS[key][0]
		var outside := _nav_node(c + WALL_RINGS[key][1])
		var ring: Array = []
		for corner in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
			ring.append(_nav_node(c + corner))
		for i in 4:
			_nav_link(ring[i], ring[(i + 1) % 4])
		_nav_link(ring[2], outside)
		_nav_link(ring[3], outside)
		_nav_link(outside, _nav_node(c + GATES[key][0]))


## True if no building stands between a and b (trees and hills don't count).
func clear_line(a: Vector3, b: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var q := PhysicsRayQueryParameters3D.create(Vector3(a.x, height_at(a.x, a.z) + 1.2, a.z),
			Vector3(b.x, height_at(b.x, b.z) + 1.2, b.z), BUILDING_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Nearest road-graph node that can be reached in a straight line.
func _nearest_nav(v: Vector3) -> int:
	var order: Array = []
	for i in nav_nodes.size():
		order.append([nav_nodes[i].distance_to(Vector2(v.x, v.z)), i])
	order.sort_custom(func(x, y): return x[0] < y[0])
	for k in mini(10, order.size()):
		var n: Vector2 = nav_nodes[order[k][1]]
		if clear_line(v, Vector3(n.x, 0, n.y)):
			return order[k][1]
	return order[0][1]


## Waypoints from `from` to `to` (the last one is `to` itself).
func find_path(from: Vector3, to: Vector3) -> Array:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	if a.distance_to(b) < 50.0 and clear_line(from, to):
		return [to]
	var s := _nearest_nav(from)
	var e := _nearest_nav(to)
	if s == e:
		return [to]
	# Dijkstra over a few dozen nodes
	var dist := {s: 0.0}
	var prev := {}
	var open := [s]
	while not open.is_empty():
		var cur: int = open[0]
		for o in open:
			if dist[o] < dist[cur]:
				cur = o
		open.erase(cur)
		if cur == e:
			break
		for n in nav_edges[cur]:
			var nd: float = dist[cur] + nav_nodes[cur].distance_to(nav_nodes[n])
			if not dist.has(n) or nd < dist[n]:
				dist[n] = nd
				prev[n] = cur
				open.append(n)
	if not prev.has(e):
		return [to]
	var idx: Array = [e]
	while idx[0] != s:
		idx.push_front(prev[idx[0]])
	var out: Array = []
	for i in idx:
		var v: Vector2 = nav_nodes[i]
		out.append(Vector3(v.x, height_at(v.x, v.y), v.y))
	# don't walk back to the first node if the second one is closer
	if out.size() > 1 and a.distance_to(nav_nodes[idx[1]]) < nav_nodes[idx[0]].distance_to(nav_nodes[idx[1]]):
		out.pop_front()
	if b.distance_to(nav_nodes[e]) < 3.0:
		out.pop_back()
	out.append(to)
	return out


# --- runtime helpers ------------------------------------------------------

func add_debris(body: RigidBody3D, xform: Transform3D, impulse: Vector3) -> void:
	debris_root.add_child(body)
	body.global_transform = xform.orthonormalized()
	body.apply_central_impulse(impulse)
	if debris_root.get_child_count() > 40:
		debris_root.get_child(0).queue_free()
	# freeze after a while to save CPU (the connection dies with the body)
	get_tree().create_timer(12.0).timeout.connect(body.set.bind("freeze", true))


func add_corpse(corpse: Node3D) -> void:
	corpses_root.add_child(corpse)
	if corpses_root.get_child_count() > 35:
		corpses_root.get_child(0).queue_free()


func mat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), rough, metal]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.metallic = metal
		_mat_cache[key] = m
	return _mat_cache[key]


# --- environment ----------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.84)
	sky_mat.ground_horizon_color = Color(0.6, 0.64, 0.66)
	sky.sky_material = sky_mat
	env.sky = sky
	# A fixed ambient color looks the same in Forward+ and in the web
	# (Compatibility) renderer; sky ambient over-brightens the latter.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.74, 0.8)
	env.fog_density = 0.0028
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


# --- terrain --------------------------------------------------------------

func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := SIZE / GRID
	var e := 1.5
	for iz in GRID + 1:
		for ix in GRID + 1:
			var x := -HALF + ix * step
			var z := -HALF + iz * step
			var h := height_at(x, z)
			var n := Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e,
					height_at(x, z - e) - height_at(x, z + e)).normalized()
			st.set_color(_ground_color(x, z, h, n.y))
			st.set_normal(n)
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, h, z))
	for iz in GRID:
		for ix in GRID:
			var i := iz * (GRID + 1) + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + GRID + 1)
			st.add_index(i + 1)
			st.add_index(i + GRID + 2)
			st.add_index(i + GRID + 1)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


func _ground_color(x: float, z: float, h: float, ny: float) -> Color:
	var human := Color(0.42, 0.58, 0.26)
	var empire := Color(0.5, 0.56, 0.28)
	var elves := Color(0.2, 0.34, 0.13)
	var villain := Color(0.36, 0.38, 0.3)
	var wx := smoothstep(-25.0, 25.0, x)
	var wz := smoothstep(-25.0, 25.0, z)
	var c := empire.lerp(villain, wx).lerp(human.lerp(elves, wx), wz)
	var rock := Color(0.42, 0.4, 0.38)
	c = c.lerp(rock, clampf((0.86 - ny) * 5.0, 0.0, 1.0))
	c = c.lerp(rock, smoothstep(22.0, 40.0, h) * 0.8)
	c = c.lerp(Color(0.92, 0.93, 0.96), smoothstep(62.0, 74.0, h))
	var rd := road_distance(x, z)
	c = c.lerp(Color(0.46, 0.38, 0.26), 1.0 - smoothstep(2.5, 5.0, rd))
	var n := noise.get_noise_2d(x * 7.0, z * 7.0) * 0.06
	return Color(c.r + n, c.g + n, c.b + n)


# --- building helpers -----------------------------------------------------

## Adds a box. `pos` is the center of the box's bottom face in world space.
func box(pos: Vector3, size: Vector3, color: Color, rot_y := 0.0, collide := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat(color)
	mi.mesh = bm
	return _place(mi, pos + Vector3(0, size.y * 0.5, 0), rot_y, collide, _box_shape(size))


func cylinder(pos: Vector3, radius: float, height: float, color: Color, top_radius := -1.0, collide := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = 12
	cm.material = mat(color)
	mi.mesh = cm
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	return _place(mi, pos + Vector3(0, height * 0.5, 0), 0.0, collide, sh)


func roof(pos: Vector3, size: Vector3, color: Color, rot_y := 0.0) -> Node3D:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	pm.material = mat(color)
	mi.mesh = pm
	return _place(mi, pos + Vector3(0, size.y * 0.5, 0), rot_y, false, null)


func label(pos: Vector3, text: String, size := 64, color := Color.WHITE) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = pos
	buildings.add_child(l)


func house(pos: Vector3, rot_y: float, w: float, d: float, h: float, wall: Color, roof_color: Color) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	box(pos + Vector3(0, -1.0, 0), Vector3(w, h + 1.0, d), wall, rot_y)
	roof(pos + Vector3(0, h, 0), Vector3(w + 0.6, h * 0.6, d + 0.6), roof_color, rot_y + PI * 0.5 if w > d else rot_y)
	box(pos + basis * Vector3(0, 0, d * 0.5 + 0.03), Vector3(1.0, 1.9, 0.08), Color(0.25, 0.16, 0.08), rot_y, false)
	box(pos + basis * Vector3(w * 0.28, 1.2, d * 0.5 + 0.03), Vector3(0.7, 0.6, 0.06), Color(0.95, 0.85, 0.5), rot_y, false)


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _place(mi: MeshInstance3D, center: Vector3, rot_y: float, collide: bool, shape: Shape3D) -> Node3D:
	if collide and shape != null:
		var body := StaticBody3D.new()
		body.collision_layer = 1 | BUILDING_LAYER
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		body.add_child(mi)
		body.position = center
		body.rotation.y = rot_y
		buildings.add_child(body)
		return body
	mi.position = center
	mi.rotation.y = rot_y
	buildings.add_child(mi)
	return mi


# --- settlements ----------------------------------------------------------

func _build_palace() -> void:
	var c: Vector3 = locations["palace"]
	var stone := Color(0.7, 0.66, 0.58)
	var red := Color(0.62, 0.1, 0.1)
	var gold := Color(0.85, 0.68, 0.2)
	var base := c + Vector3(0, -1.5, 0)
	var wall_h := 10.5
	box(base + Vector3(0, 0, -31), Vector3(64, wall_h, 2.5), stone)
	box(base + Vector3(-31, 0, 0), Vector3(2.5, wall_h, 64), stone)
	box(base + Vector3(31, 0, 0), Vector3(2.5, wall_h, 64), stone)
	box(base + Vector3(-18.5, 0, 31), Vector3(27, wall_h, 2.5), stone)
	box(base + Vector3(18.5, 0, 31), Vector3(27, wall_h, 2.5), stone)
	for corner in [Vector3(-31, 0, -31), Vector3(31, 0, -31), Vector3(-31, 0, 31), Vector3(31, 0, 31)]:
		cylinder(base + corner, 4.5, 16.5, stone)
		cylinder(base + corner + Vector3(0, 16.5, 0), 5.2, 6.0, red, 0.0, false)
	for gx in [-6.5, 6.5]:
		cylinder(base + Vector3(gx, 0, 32), 2.6, 13.5, stone)
		cylinder(base + Vector3(gx, 13.5, 32), 3.0, 4.0, red, 0.0, false)
	# banners on the gate
	for gx in [-3.5, 3.5]:
		box(c + Vector3(gx, 3.5, 32.4), Vector3(1.6, 4.5, 0.1), red, 0.0, false)
	# the keep
	box(base + Vector3(0, 0, -10), Vector3(26, 15.5, 18), Color(0.76, 0.7, 0.62))
	roof(base + Vector3(0, 15.5, -10), Vector3(27, 6, 19), red, PI * 0.5)
	cylinder(base + Vector3(0, 0, -10), 5.0, 29.0, Color(0.88, 0.84, 0.76))
	cylinder(base + Vector3(0, 29, -10), 5.8, 9.0, gold, 0.0, false)
	box(c + Vector3(0, 0, -0.9), Vector3(4, 3.2, 0.3), Color(0.35, 0.2, 0.1), 0.0, false)
	# market stalls for the quartermaster and the medic
	_stall(c + Vector3(-12, 0, 12), red)
	_stall(c + Vector3(12, 0, 12), Color(0.9, 0.9, 0.9))
	label(c + Vector3(0, 12.5, 33.5), "Emperor's Palace", 96, Color(1, 0.85, 0.5))


func _build_elf_village() -> void:
	var c: Vector3 = locations["elf_village"]
	var wood := Color(0.47, 0.31, 0.16)
	var dark_wood := Color(0.33, 0.21, 0.1)
	var moss := Color(0.25, 0.42, 0.18)
	# the great tree in the middle
	cylinder(c + Vector3(0, -1, 0), 2.6, 26.0, Color(0.36, 0.25, 0.15))
	for i in 5:
		var a := i * TAU / 5.0
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 7.0
		sm.height = 10.0
		sm.material = mat(Color(0.22, 0.45, 0.18))
		mi.mesh = sm
		_place(mi, c + Vector3(cos(a) * 5.0, 24.0 + (i % 2) * 3.0, sin(a) * 5.0), 0.0, false, null)
	# wooden houses, half of them on stilts
	for i in 8:
		var a := i * TAU / 8.0 + 0.2
		var r := 19.0 if i % 2 == 0 else 24.0
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = height_at(p.x, p.z)
		var rot := -a - PI * 0.5
		if i % 2 == 1:
			for sx in [-1.8, 1.8]:
				for sz in [-1.6, 1.6]:
					cylinder(p + Vector3(sx, -1, sz), 0.22, 4.2, dark_wood)
			box(p + Vector3(0, 3.0, 0), Vector3(5.2, 0.3, 4.8), dark_wood, rot)
			house(p + Vector3(0, 4.3, 0), rot, 4.2, 3.8, 2.8, wood, moss)
			var basis := Basis(Vector3.UP, rot)
			box(p + basis * Vector3(0, -0.5, 3.6), Vector3(1.2, 0.2, 3.0), dark_wood, rot, false).rotation.x = 0.8
		else:
			house(p, rot, 5.0, 4.5, 3.2, wood, moss)
	_stall(c + Vector3(-8, 0, 8), moss)
	_stall(c + Vector3(8, 0, -8), Color(0.8, 0.8, 0.6))
	label(c + Vector3(0, 9, 40), "Elven village", 72, Color(0.6, 1, 0.6))


func _build_human_village() -> void:
	var c: Vector3 = locations["human_village"]
	var walls := [Color(0.85, 0.8, 0.65), Color(0.75, 0.62, 0.45), Color(0.9, 0.88, 0.8)]
	var roofs := [Color(0.55, 0.22, 0.12), Color(0.45, 0.35, 0.2), Color(0.35, 0.3, 0.28)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 12:
		var a := i * TAU / 12.0 + rng.randf_range(-0.12, 0.12)
		var r := rng.randf_range(26.0, 42.0)
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		# keep the roads free
		if road_distance(p.x, p.z) < 8.0:
			a += 0.3
			p = c + Vector3(cos(a) * r, 0, sin(a) * r)
		if road_distance(p.x, p.z) < 8.0:
			continue
		p.y = height_at(p.x, p.z)
		house(p, -a - PI * 0.5, rng.randf_range(5, 8), rng.randf_range(5, 7), rng.randf_range(3, 4.5), walls[i % 3], roofs[i % 3])
	# inn
	var inn := c + Vector3(16, 0, -14)
	house(Vector3(inn.x, height_at(inn.x, inn.z), inn.z), 0.4, 11, 8, 5.5, Color(0.7, 0.55, 0.38), Color(0.4, 0.18, 0.1))
	# well and market
	cylinder(c + Vector3(0, -0.5, 0), 1.3, 1.5, Color(0.5, 0.5, 0.5))
	_stall(c + Vector3(-7, 0, 6), Color(0.3, 0.4, 0.8))
	_stall(c + Vector3(7, 0, 6), Color(0.9, 0.9, 0.9))
	_stall(c + Vector3(0, 0, 11), Color(0.8, 0.6, 0.2))
	label(c + Vector3(0, 6, -58), "Human village (neutral)", 96, Color(1, 0.95, 0.7))


func _build_fort() -> void:
	var c: Vector3 = locations["fort"]
	var stone := Color(0.28, 0.26, 0.28)
	var moss := Color(0.25, 0.3, 0.2)
	var base := c + Vector3(0, -1.5, 0)
	# old ruined walls with gaps
	box(base + Vector3(-12, 0, -21), Vector3(18, 9, 2.5), stone)
	box(base + Vector3(12, 0, -21), Vector3(14, 6, 2.5), stone)
	box(base + Vector3(-21, 0, 0), Vector3(2.5, 8.5, 40), stone)
	box(base + Vector3(21, 0, -8), Vector3(2.5, 9, 24), stone)
	box(base + Vector3(21, 0, 15), Vector3(2.5, 4, 8), moss)
	box(base + Vector3(-13, 0, 21), Vector3(14, 8, 2.5), stone)
	box(base + Vector3(14, 0, 21), Vector3(12, 5, 2.5), stone)
	cylinder(base + Vector3(-21, 0, -21), 4.0, 15.0, stone)
	cylinder(base + Vector3(21, 0, -21), 4.0, 7.0, stone)  # broken tower
	cylinder(base + Vector3(-21, 0, 21), 4.0, 12.0, stone)
	cylinder(base + Vector3(-21, 15, -21), 4.6, 5.0, Color(0.12, 0.08, 0.14), 0.0, false)
	# the keep
	box(base + Vector3(0, 0, -8), Vector3(16, 12, 12), Color(0.22, 0.2, 0.22))
	box(c + Vector3(0, 0, -1.9), Vector3(3.5, 3.5, 0.3), Color(0.08, 0.05, 0.05), 0.0, false)
	# purple banners
	for gx in [-5.0, 5.0]:
		box(c + Vector3(gx, 5.0, -1.8), Vector3(1.5, 5.0, 0.1), Color(0.35, 0.1, 0.45), 0.0, false)
	# scattered rocks
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 14:
		var p := c + Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-45, 45))
		if Vector2(p.x - c.x, p.z - c.z).length() < 26:
			continue
		p.y = height_at(p.x, p.z) - 0.5
		box(p, Vector3(rng.randf_range(1.5, 4), rng.randf_range(1, 3), rng.randf_range(1.5, 4)), Color(0.4, 0.39, 0.38), rng.randf() * TAU)
	_stall(c + Vector3(-9, 0, 9), Color(0.3, 0.1, 0.35))
	_stall(c + Vector3(9, 0, 9), Color(0.2, 0.2, 0.2))
	label(c + Vector3(0, 12, 26), "The old fort", 96, Color(0.85, 0.6, 1))


func _build_crossroads() -> void:
	var c: Vector3 = locations["crossroads"]
	cylinder(c + Vector3(0, -0.5, 0), 0.15, 4.0, Color(0.4, 0.28, 0.15))
	var signs := {
		"Human village": Vector2(-1, 1), "Palace": Vector2(-1, -1),
		"Elven forest": Vector2(1, 1), "Old fort": Vector2(1, -1),
	}
	var y := 2.9
	for text in signs:
		var dir: Vector2 = signs[text].normalized()
		var rot := atan2(-dir.x, -dir.y) + PI * 0.5
		var p := c + Vector3(dir.x * 0.8, y, dir.y * 0.8)
		box(p, Vector3(1.8, 0.35, 0.08), Color(0.55, 0.4, 0.22), rot, false)
		label(p + Vector3(dir.x * 0.4, 0.55, dir.y * 0.4), text, 40)
		y -= 0.45


func _stall(pos: Vector3, awning: Color) -> void:
	pos.y = height_at(pos.x, pos.z)
	box(pos + Vector3(0, 0, -0.6), Vector3(2.6, 1.0, 0.9), Color(0.45, 0.3, 0.16))
	for sx in [-1.2, 1.2]:
		box(pos + Vector3(sx, 0, -1.0), Vector3(0.12, 2.6, 0.12), Color(0.35, 0.22, 0.1), 0.0, false)
	box(pos + Vector3(0, 2.6, -0.6), Vector3(2.9, 0.12, 1.8), awning, 0.0, false)
