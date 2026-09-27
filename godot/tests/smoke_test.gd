extends Node
## Headless smoke test. Run with:
##   godot --headless --path godot res://tests/smoke_test.tscn
## Builds the world for every faction, exercises combat, dismemberment,
## bleeding, prostheses, corpses, caravans, orders, missions and save/load.

var failures := 0
var main: Node


func _ready() -> void:
	await _run()
	print("SMOKE TEST: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		push_error("FAIL " + what)
		print("  FAIL ", what)


func wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _start(faction: int, save := {}) -> void:
	if main:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	Game.player_faction = faction
	Game.reputation = {0: 0, 1: 0, 2: 0, 3: 0}
	main = Node.new()
	main.set_script(preload("res://scripts/main.gd"))
	main.manual = true
	add_child(main)
	var t0 := Time.get_ticks_msec()
	main.start_game(faction, save)
	print("  world built in %d ms" % (Time.get_ticks_msec() - t0))


func _run() -> void:
	print("== Elves ==")
	await _start(Factions.ELVES)
	var w: World = Game.world
	var p: Player = Game.player
	check(w != null and p != null, "world and player exist")
	check(w.forest.tree_count > 4000, "dense forest: %d trees in %d cells" % [w.forest.tree_count, w.forest.cell_count])
	check(get_tree().get_nodes_in_group("actors").size() > 40, "zones populated: %d actors" % get_tree().get_nodes_in_group("actors").size())
	for key in w.locations:
		check(w.zone_at(w.locations[key]) >= 0, "location %s at height %.1f" % [key, w.locations[key].y])
	await wait(1.5)
	var gh := w.height_at(p.global_position.x, p.global_position.z)
	check(absf(p.global_position.y - gh) < 1.5, "player stands on the ground (y=%.2f ground=%.2f)" % [p.global_position.y, gh])
	check(p.ranged and p.model.bow != null, "elf has a bow")

	# jumping
	p.want_jump = true
	await wait(0.2)
	check(p.global_position.y > gh + 0.5, "player can jump")
	await wait(1.0)

	# dismemberment of an NPC
	var npc: NPC = null
	for a in get_tree().get_nodes_in_group("actors"):
		if a is NPC and a.faction == Factions.ELVES and a.is_soldier:
			npc = a
			break
	npc.max_hp = 10000
	npc.hp = 10000
	var guard := 0
	while npc.parts.arm_l == "ok" and guard < 50:
		npc.take_hit(p, 30.0, "arm_l", true)
		guard += 1
	check(npc.parts.arm_l == "lost", "arm can be cut off")
	check(npc.bleeding > 0.0, "a lost arm bleeds")
	check(w.debris_root.get_child_count() > 0, "severed arm flies off as a 3D object")
	check(npc.apply_bandage() and npc.bleeding == 0.0, "bandage stops bleeding")

	# the player: arm -> bleeding to death unless healed
	p.hp = 5.0
	p.sever("arm_l")
	check(p.parts.arm_l == "lost" and p.bleeding > 0.0, "player loses an arm and bleeds")
	await wait(3.5)
	check(p.dead, "untreated bleeding kills the player")
	check(Game.hud.panel.visible and Game.hud.panel_kind == "death", "death screen shown")
	check(get_tree().get_nodes_in_group("corpses").size() >= 1, "3D corpse left behind")

	print("== Palace guard ==")
	await _start(Factions.EMPIRE)
	w = Game.world
	p = Game.player
	await wait(0.5)
	# eye -> half the screen goes dark
	p.gouge_eye("eye_l")
	await wait(0.1)
	check(Game.hud.blind_l.visible and not Game.hud.blind_r.visible, "lost left eye darkens the left half of the screen")
	p.apply_bandage()
	p.add_item("glass_eye")
	p.use_item("glass_eye")
	await wait(0.1)
	check(p.parts.eye_l == "prosthetic" and not Game.hud.blind_l.visible, "glass eye restores sight")
	# leg -> crawl -> wheelchair -> prosthesis
	p.sever("leg_r")
	p.apply_bandage()
	check(p.mobility() == "crawl", "lost leg: crawling")
	p.add_item("wheelchair")
	p.use_item("wheelchair")
	check(p.mobility() == "wheelchair", "wheelchair")
	p.add_item("prosthetic_leg")
	p.use_item("prosthetic_leg")
	check(p.mobility() == "walk" and p.parts.leg_r == "prosthetic", "prosthetic leg: walking again")
	# commander mission
	var cmd = Game.director.find_commander()
	check(cmd != null, "palace has a commander")
	var talk: String = Game.director.commander_talk()
	check(Game.director.mission.get("state", "") == "active", "commander gives an order: " + talk.substr(0, 50))
	check(cmd.order == "attack_move", "commander leads a raid")
	# shop
	var gold_before: int = p.gold
	var bandages: int = p.count_item("bandage")
	var merchant = null
	for a in get_tree().get_nodes_in_group("actors"):
		if a is NPC and a.role == "merchant" and a.faction == Factions.EMPIRE:
			merchant = a
	Game.hud.open_shop(merchant)
	var buy_btn: Button = null
	for row in Game.hud.panel_body.get_children():
		if row is HBoxContainer and row.get_child(0).text.begins_with("Bandage") and buy_btn == null:
			buy_btn = row.get_child(1)
	buy_btn.pressed.emit()
	check(p.gold == gold_before - ItemDB.price("bandage") and p.count_item("bandage") == bandages + 1, "buying a bandage from the quartermaster")
	Game.hud.close_panel()
	# caravan robbery
	var c: Caravan = Game.director.spawn_caravan(0)
	await wait(0.3)
	var g0: int = p.gold
	c.interact(p)
	check(c.looted and p.gold > g0 and p.count_item("goods") > 0, "caravan robbed")
	check(Game.are_hostile(c.guards[0], p), "caravan guards turn on the robber")
	# save & load
	p.sever("arm_r")
	p.apply_bandage()
	check(Game.save_game(), "game saved")
	var data := Game.read_save()
	check(data.get("npcs", []).size() > 30, "save contains the NPCs")
	await _start(Factions.EMPIRE, data)
	p = Game.player
	await wait(0.3)
	check(p.parts.arm_r == "lost" and p.parts.leg_r == "prosthetic" and p.parts.eye_l == "prosthetic", "injuries survive save/load")
	check(p.model.prosthesis["leg_r"].visible and not p.model.flesh["arm_r"].visible, "loaded body looks right")
	check(get_tree().get_nodes_in_group("caravans").size() >= 1, "caravans restored")

	print("== Villain ==")
	await _start(Factions.VILLAIN)
	p = Game.player
	await wait(0.3)
	var army: Array = Game.director.army()
	check(army.size() >= 8, "the Villain has an army of %d" % army.size())
	Game.director.villain_order(3)
	check(army[0].order == "attack_move", "order 3: the army marches on the palace")
	var before := army.size()
	p.gold = 100
	Game.director.recruit("warrior")
	check(Game.director.army().size() == before + 1, "recruiting soldiers")
	# a fight: the army against a palace patrol
	var foe: NPC = Game.director.spawn_npc(Factions.EMPIRE, "warrior", p.global_position + Vector3(4, 0, 0))
	await wait(4.0)
	check(not is_instance_valid(foe) or foe.dead or foe.hp < foe.max_hp, "NPCs fight hostile factions")
	# melee from the player
	var victim: NPC = Game.director.spawn_npc(Factions.ELVES, "warrior", p.global_position - p.global_basis.z * 1.3)
	victim.max_hp = 500
	victim.hp = 500
	victim.set_physics_process(false)
	p.attack_cd = 0.0
	p.face_yaw = p.rotation.y
	p.try_attack("leg_l")
	await wait(0.5)
	check(victim.hp < 500, "player sword hits (%.0f hp left)" % victim.hp)
	await wait(2.0)

	print("== Soak: the world runs on its own ==")
	for f in [Factions.ELVES, Factions.EMPIRE, Factions.VILLAIN]:
		await _start(f)
		var pl: Player = Game.player
		pl.max_hp = 1e9
		pl.hp = 1e9
		Game.director.caravan_t = 1.0
		Game.director.raid_t = 3.0
		Game.director.intruder_t = 3.0
		if f == Factions.EMPIRE:
			Game.director.commander_talk()
		var palace: Vector3 = Game.world.locations.palace
		var army_d0 := 0.0
		if f == Factions.VILLAIN:
			Game.director.villain_order(3)
			army_d0 = Game.director.army()[0].global_position.distance_to(palace)
		Engine.time_scale = 4.0
		await wait(160.0)  # game seconds (timers follow time_scale)
		Engine.time_scale = 1.0
		if f == Factions.VILLAIN:
			var troops: Array = Game.director.army()
			var closest := 1e9
			for t in troops:
				closest = minf(closest, t.global_position.distance_to(palace))
			check(troops.is_empty() or closest < army_d0 - 200.0, "the army leaves the fort through the gate and marches on the palace (%.0f m -> %.0f m)" % [army_d0, closest])
		var n := get_tree().get_nodes_in_group("actors").size()
		var caravans := get_tree().get_nodes_in_group("caravans").size()
		var corpses := get_tree().get_nodes_in_group("corpses").size()
		check(n > 20 and n <= Director.MAX_NPCS + 20, "%s: %d actors, %d caravans, %d corpses after 160 s of game time" % [Factions.NAMES[f], n, caravans, corpses])
		check(caravans >= 1, "caravans are travelling")
		var stuck := 0
		for a in get_tree().get_nodes_in_group("actors"):
			if a.global_position.y < Game.world.height_at(a.global_position.x, a.global_position.z) - 2.0:
				stuck += 1
		check(stuck == 0, "nobody fell through the ground")

