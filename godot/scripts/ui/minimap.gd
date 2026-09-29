class_name Minimap
extends Control
## Map of the 4 zones with roads, settlements, caravans, nearby
## characters and the player. M toggles the big map.

var big := false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.1
		queue_redraw()


func _to_map(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) + Vector2(World.HALF, World.HALF)) / World.SIZE * size


func _draw() -> void:
	var w = Game.world
	var p = Game.player
	if w == null or p == null or not is_instance_valid(p):
		return
	var s := size
	var half := s * 0.5
	var a := 0.75
	draw_rect(Rect2(Vector2.ZERO, half), Color(0.55, 0.5, 0.3, a))                  # Emperor (NW)
	draw_rect(Rect2(Vector2(half.x, 0), half), Color(0.35, 0.33, 0.35, a))          # Villain (NE)
	draw_rect(Rect2(Vector2(0, half.y), half), Color(0.45, 0.58, 0.3, a))           # Humans (SW)
	draw_rect(Rect2(half, half), Color(0.12, 0.3, 0.12, a))                         # Elves (SE)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0), false, 2.0)
	for seg in w.road_segments:
		draw_line(_to_map(Vector3(seg[0].x, 0, seg[0].y)), _to_map(Vector3(seg[1].x, 0, seg[1].y)), Color(0.6, 0.45, 0.25), 2.0)
	var font := ThemeDB.fallback_font
	for key in w.locations:
		var mp := _to_map(w.locations[key])
		draw_circle(mp, 5.0 if big else 3.5, Color(1, 1, 1))
		if big:
			draw_string(font, mp + Vector2(8, 5), World.LOCATION_NAMES[key], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if big:
		for i in 4:
			var corner: Vector2 = [Vector2(0.25, 0.04), Vector2(0.75, 0.04), Vector2(0.25, 0.54), Vector2(0.75, 0.54)][i]
			var zone: int = [Factions.EMPIRE, Factions.VILLAIN, Factions.HUMANS, Factions.ELVES][i]
			draw_string(font, Vector2(corner.x * s.x - 90, corner.y * s.y + 14), Factions.ZONE_NAMES[zone], HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color(1, 1, 0.8))
	for c in get_tree().get_nodes_in_group("caravans"):
		draw_rect(Rect2(_to_map(c.global_position) - Vector2(3, 3), Vector2(6, 6)), Color(1, 0.85, 0.2) if not c.looted else Color(0.5, 0.5, 0.5))
	for n in get_tree().get_nodes_in_group("actors"):
		if n == p or n.global_position.distance_to(p.global_position) > (400.0 if big else 120.0):
			continue
		var col: Color = Color(1, 0.2, 0.2) if Game.are_hostile(n, p) else Factions.COLORS[n.faction]
		draw_circle(_to_map(n.global_position), 2.0, col)
	var pp := _to_map(p.global_position)
	var fwd := Vector2(-sin(p.yaw), -cos(p.yaw))
	var right := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([pp + fwd * 8, pp - fwd * 5 + right * 5, pp - fwd * 5 - right * 5]), Color(1, 1, 1))
