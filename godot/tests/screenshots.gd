extends Node
## Renders a few screenshots into user://screenshots (needs a display,
## e.g. `xvfb-run godot --path godot res://tests/screenshots.tscn`).

var main: Node
var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_user_data_dir() + "/screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _shots()
	print("screenshots written to ", out_dir)
	get_tree().quit()


func _start(faction: int) -> void:
	if main:
		main.queue_free()
		await get_tree().process_frame
	Game.player_faction = faction
	main = Node.new()
	main.set_script(preload("res://scripts/main.gd"))
	main.manual = true
	add_child(main)
	main.start_game(faction, {})
	Game.hud.help.visible = false


func _snap(file: String, frames := 30) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir + "/" + file)
	print("saved ", file)


func _place(pos: Vector3, yaw: float, pitch: float, zoom := 3.4) -> void:
	var p: Player = Game.player
	p.global_position = Game.world.ground(pos) + Vector3(0, 0.1, 0)
	p.velocity = Vector3.ZERO
	p.yaw = yaw
	p.face_yaw = yaw
	p.rotation.y = yaw
	p.pitch = pitch
	p.zoom = zoom


func _shots() -> void:
	await _start(Factions.ELVES)
	var w: World = Game.world
	var ev: Vector3 = w.locations.elf_village
	_place(ev + Vector3(0, 0, 30), 0.0, -0.12, 4.0)
	await _snap("01_elf_village.png", 60)
	# forest: pictures far away, 3D trees close up
	_place(Vector3(60, 0, 40), deg_to_rad(-135), -0.05, 3.0)
	await _snap("02_forest.png", 60)
	# injuries: an elf with a cut-off arm and leg crawling, and a ragdoll corpse
	var d = Game.director
	var a: NPC = d.spawn_npc(Factions.EMPIRE, "warrior", ev + Vector3(3, 0, 38), {"order": "hold"})
	var b: NPC = d.spawn_npc(Factions.VILLAIN, "warrior", ev + Vector3(-2, 0, 38), {"order": "hold"})
	var c: NPC = d.spawn_npc(Factions.EMPIRE, "warrior", ev + Vector3(0.5, 0, 36), {"order": "hold"})
	for n in [a, b, c]:
		n.is_soldier = false
	await get_tree().process_frame
	a.sever("arm_l")
	a.sever("leg_r")
	a.face_yaw = PI * 0.5
	b.sever("arm_r")
	b.gouge_eye("eye_l")
	b.has_wheelchair = true
	b.sever("leg_l")
	b.face_yaw = -PI * 0.5
	c.die(null)
	_place(ev + Vector3(0, 0, 43), 0.0, -0.35, 3.0)
	await _snap("03_injuries.png", 90)

	await _start(Factions.EMPIRE)
	w = Game.world
	_place(w.locations.palace + Vector3(0, 0, 75), 0.0, 0.05, 4.0)
	await _snap("04_palace.png", 60)
	var p: Player = Game.player
	p.gouge_eye("eye_l")
	p.sever("arm_l")
	_place(w.locations.palace + Vector3(0, 0, 20), 0.0, -0.1, 3.0)
	await _snap("05_lost_eye_hud.png", 30)

	await _start(Factions.VILLAIN)
	w = Game.world
	_place(w.locations.fort + Vector3(-10, 0, 60), deg_to_rad(-10), 0.1, 4.0)
	await _snap("06_fort.png", 60)
	Game.hud._toggle_big_map()
	await _snap("07_map.png", 10)
