class_name Director
extends Node
## Runs the living world: populates the 4 zones, spawns caravans, raids,
## spies and partisans, reinforcements, the palace commander's missions,
## the Villain player's army orders, and serializes everything.

const MAX_NPCS := 150
const NAMES := {
	0: ["Ivan", "Petr", "Olga", "Marfa", "Fyodor", "Anna", "Semyon", "Darya", "Gleb", "Vasilisa"],
	1: ["Boris", "Dmitri", "Oleg", "Yaroslav", "Mstislav", "Rurik", "Svyatoslav", "Igor", "Vadim", "Stepan"],
	2: ["Arwel", "Lirael", "Thandor", "Elowen", "Faelar", "Sylvar", "Nimeth", "Aeris", "Caelum", "Ithil"],
	3: ["Grom", "Skarn", "Mordak", "Vrask", "Zagreth", "Krull", "Draven", "Ugluk", "Snaga", "Bolg"],
}
const ROLE_TITLES := {
	"warrior": ["Villager", "Guard", "Elf warrior", "Cutthroat"],
	"archer": ["Hunter", "Crossbowman", "Elf archer", "Raider"],
	"spy": ["Spy", "Spy", "Elf spy", "Villain's spy"],
	"partisan": ["", "", "Elf partisan", ""],
	"merchant": ["Merchant", "Quartermaster", "Elf trader", "Black marketeer"],
	"healer": ["Healer", "Palace medic", "Elf druid", "Shaman"],
	"civilian": ["Villager", "Servant", "Elf", "Slave"],
	"caravan_guard": ["Caravan guard", "", "", ""],
}

var world: World
var uid_counter := 0
var caravan_counter := 0
var caravan_t := 20.0
var raid_t := 110.0
var intruder_t := 80.0
var reinforce_t := 45.0
var rep_t := 30.0
var victory_t := 2.0
var palace_fallen := false
var villain_dead := false
var raid_count := 0
var mission := {}
var mission_counter := 0
var army_order := "guard"


func _ready() -> void:
	world = Game.world
	Game.actor_killed.connect(_on_killed)


# --- setup ----------------------------------------------------------------

func new_game() -> void:
	_populate()
	_spawn_player()
	match Game.player_faction:
		Factions.ELVES:
			Game.post("You are a forest elf. Palace soldiers and the Villain's troops raid your village. Defend it, and rob caravans on the roads!", Color(0.6, 1, 0.6))
		Factions.EMPIRE:
			Game.post("You serve in the palace guard. Obey your commander (E to report). Protect the palace from the Villain, his spies and elven partisans.", Color(1, 0.8, 0.5))
		Factions.VILLAIN:
			Game.post("You are the Villain (the name was never invented). You are your own commander: keys 1-5 give orders to your army. Storm the palace!", Color(0.85, 0.6, 1))
	Game.post("F1 shows the controls.", Color(0.8, 0.8, 0.8))


func _populate() -> void:
	var L := world.locations
	var villain_player := Game.player_faction == Factions.VILLAIN
	# Palace
	spawn_npc(Factions.EMPIRE, "commander", L.palace + Vector3(0, 0, 6))
	for i in 9:
		var a := i * TAU / 9.0
		spawn_npc(Factions.EMPIRE, "archer" if i % 4 == 0 else "warrior", L.palace + Vector3(cos(a) * 16, 0, 8 + sin(a) * 12))
	spawn_npc(Factions.EMPIRE, "warrior", L.palace + Vector3(-3, 0, 36))
	spawn_npc(Factions.EMPIRE, "warrior", L.palace + Vector3(3, 0, 36))
	spawn_npc(Factions.EMPIRE, "merchant", L.palace + Vector3(-12, 0, 10.5))
	spawn_npc(Factions.EMPIRE, "healer", L.palace + Vector3(12, 0, 10.5))
	# Elven village
	for i in 8:
		var a := i * TAU / 8.0
		spawn_npc(Factions.ELVES, "archer" if i % 2 == 0 else "warrior", L.elf_village + Vector3(cos(a) * 11, 0, sin(a) * 11))
	spawn_npc(Factions.ELVES, "merchant", L.elf_village + Vector3(-8, 0, 9.5))
	spawn_npc(Factions.ELVES, "healer", L.elf_village + Vector3(8, 0, -6.5))
	for i in 2:
		spawn_npc(Factions.ELVES, "civilian", L.elf_village + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), {"order": "wander"})
	# Old fort
	if not villain_player:
		spawn_npc(Factions.VILLAIN, "boss", L.fort + Vector3(0, 0, 4), {"display_name": "The Villain (name not invented)"})
	for i in 8:
		var a := i * TAU / 8.0
		var n := spawn_npc(Factions.VILLAIN, "archer" if i % 3 == 0 else "warrior", L.fort + Vector3(cos(a) * 12, 0, 6 + sin(a) * 8))
		n.army = villain_player
	spawn_npc(Factions.VILLAIN, "merchant", L.fort + Vector3(-9, 0, 10.5))
	spawn_npc(Factions.VILLAIN, "healer", L.fort + Vector3(9, 0, 10.5))
	if villain_player:
		spawn_npc(Factions.VILLAIN, "recruiter", L.fort + Vector3(0, 0, 14), {"display_name": "Recruiter Skarn"})
	# Human village
	spawn_npc(Factions.HUMANS, "merchant", L.human_village + Vector3(-7, 0, 7.5))
	spawn_npc(Factions.HUMANS, "healer", L.human_village + Vector3(7, 0, 7.5))
	spawn_npc(Factions.HUMANS, "merchant", L.human_village + Vector3(0, 0, 12.5), {"display_name": "Armorer Gleb"})
	for i in 7:
		spawn_npc(Factions.HUMANS, "civilian", L.human_village + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20)), {"order": "wander"})
	for i in 3:
		spawn_npc(Factions.HUMANS, "warrior", L.human_village + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15)), {"display_name": "Militiaman " + NAMES[0].pick_random()})


func _spawn_player() -> void:
	var p := Player.new()
	p.name = "Player"
	p.uid = "player"
	p.faction = Game.player_faction
	p.role = "player"
	p.max_hp = 120.0
	p.base_speed = 4.8
	p.base_damage = 10.0
	p.inventory = {"bandage": 3, "potion": 1}
	var L := world.locations
	var pos: Vector3
	match Game.player_faction:
		Factions.ELVES:
			p.display_name = "You (elf)"
			p.weapon = "elven_blade"
			p.ranged = true
			p.gold = 60
			p.base_speed = 5.2
			pos = L.elf_village + Vector3(0, 0, 6)
			p.face_yaw = PI
		Factions.EMPIRE:
			p.display_name = "You (guard)"
			p.weapon = "iron_sword"
			p.armor_item = "leather_armor"
			p.gold = 40
			pos = L.palace + Vector3(0, 0, 11)
			p.face_yaw = 0.0
		_:
			p.display_name = "You (the Villain)"
			p.weapon = "black_blade"
			p.armor_item = "chainmail"
			p.max_hp = 160.0
			p.gold = 150
			pos = L.fort + Vector3(0, 0, 10)
			p.face_yaw = 0.0
	p.hp = p.max_hp
	p.position = world.ground(pos) + Vector3(0, 0.3, 0)
	world.actors_root.add_child(p)
	Game.player = p


func _new_uid() -> String:
	uid_counter += 1
	return "n%d" % uid_counter


func spawn_npc(faction: int, role: String, pos: Vector3, opts := {}) -> NPC:
	var n := NPC.new()
	n.uid = _new_uid()
	n.faction = faction
	n.role = role
	var titles: Array = ROLE_TITLES.get(role, ["", "", "", ""])
	var title: String = titles[faction]
	if title == "":
		title = ROLE_TITLES["warrior"][faction]
	n.display_name = "%s %s" % [title, NAMES[faction].pick_random()]
	match role:
		"warrior", "caravan_guard", "partisan":
			n.max_hp = 70.0
			n.base_damage = 10.0
			n.weapon = ["iron_sword", "iron_sword", "elven_blade", "steel_sword"][faction]
			n.armor = 1.0
		"archer":
			n.max_hp = 55.0
			n.ranged = true
			n.base_damage = 8.0
		"spy":
			n.max_hp = 50.0
			n.base_speed = 4.8
			n.base_damage = 9.0
		"commander":
			n.max_hp = 150.0
			n.weapon = "steel_sword"
			n.armor = 3.0
			n.display_name = "Commander " + NAMES[1].pick_random()
		"boss":
			n.max_hp = 280.0
			n.weapon = "black_blade"
			n.armor = 5.0
			n.model_scale = 1.25
		_:
			n.max_hp = 50.0
			n.is_soldier = false
			n.order = "hold"
			n.gold = randi_range(20, 80)
	match faction:
		Factions.EMPIRE:
			n.armor += 2.0
		Factions.ELVES:
			n.base_speed += 0.4
		Factions.VILLAIN:
			n.base_damage += 2.0
	n.gold += randi_range(3, 25)
	if randf() < 0.4:
		n.inventory = {"bandage": 1}
	for k in opts:
		n.set(k, opts[k])
	n.hp = n.max_hp
	n.position = world.ground(pos) + Vector3(0, 0.3, 0)
	n.home = n.position
	n.face_yaw = randf() * TAU
	world.actors_root.add_child(n)
	return n


func npc_count() -> int:
	return get_tree().get_nodes_in_group("actors").size()


# --- the living world -----------------------------------------------------

func _process(delta: float) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p) or p.dead:
		return
	caravan_t -= delta
	if caravan_t <= 0.0:
		caravan_t = randf_range(90.0, 130.0)
		if get_tree().get_nodes_in_group("caravans").size() < 3:
			spawn_caravan()
	reinforce_t -= delta
	if reinforce_t <= 0.0:
		reinforce_t = 45.0
		_reinforce()
	rep_t -= delta
	if rep_t <= 0.0:
		rep_t = 30.0
		for f in Game.reputation:
			if Game.reputation[f] < 0 and Game.reputation[f] > -60:
				Game.reputation[f] = mini(0, Game.reputation[f] + 2)
		_cleanup_caravans()
	match Game.player_faction:
		Factions.ELVES:
			raid_t -= delta
			if raid_t <= 0.0:
				raid_t = randf_range(120.0, 160.0)
				_raid_on("elf_village", Factions.EMPIRE if raid_count % 2 == 0 else Factions.VILLAIN, 5)
		Factions.EMPIRE:
			intruder_t -= delta
			if intruder_t <= 0.0:
				intruder_t = randf_range(110.0, 150.0)
				_intruders_at("palace")
			_update_mission(delta)
		Factions.VILLAIN:
			intruder_t -= delta
			if intruder_t <= 0.0:
				intruder_t = randf_range(120.0, 160.0)
				_intruders_at("fort")
			raid_t -= delta
			if raid_t <= 0.0:
				raid_t = randf_range(260.0, 320.0)
				if not palace_fallen:
					_raid_on("fort", Factions.EMPIRE, 5)
	victory_t -= delta
	if victory_t <= 0.0:
		victory_t = 2.0
		_check_victory()


func spawn_caravan(route_idx := -1) -> Caravan:
	caravan_counter += 1
	var routes := [
		[["village_palace"], false], [["village_palace"], true],
		[["village_cross", "cross_fort"], false], [["village_cross", "cross_elves"], false],
	]
	var r: Array = routes[route_idx if route_idx >= 0 else caravan_counter % routes.size()]
	var pts := world.route(r[0], r[1])
	var c := Caravan.new()
	c.setup(caravan_counter, pts)
	c.position = pts[0]
	world.actors_root.add_child(c)
	var offsets := [Vector3(-2.2, 0, -1.5), Vector3(2.2, 0, -1.5), Vector3(0, 0, 4.5)]
	for o in offsets:
		var g := spawn_npc(Factions.HUMANS, "caravan_guard", pts[0] + o, {"order": "escort", "escort": c, "escort_offset": o})
		g.escort_cid = c.cid
		c.guards.append(g)
	return c


func on_caravan_robbed(_c: Caravan, _robber) -> void:
	pass


func _cleanup_caravans() -> void:
	var p = Game.player
	for c in get_tree().get_nodes_in_group("caravans"):
		if c.looted and c.global_position.distance_to(p.global_position) > 150.0:
			for g in c.guards:
				if is_instance_valid(g):
					g.queue_free()
			c.queue_free()


func _raid_on(loc: String, attacker_faction: int, count: int) -> void:
	if npc_count() > MAX_NPCS:
		return
	raid_count += 1
	var target: Vector3 = world.locations[loc]
	var origin_key := "palace" if attacker_faction == Factions.EMPIRE else ("fort" if attacker_faction == Factions.VILLAIN else "elf_village")
	var origin: Vector3 = world.locations[origin_key]
	var start := target + (origin - target).normalized() * 110.0
	for i in count:
		var n := spawn_npc(attacker_faction, "archer" if i == 0 else "warrior", start + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)),
				{"order": "attack_move", "order_target": target, "transient": true, "perception": 30.0})
		n.order_target = target
	var who := "Palace soldiers" if attacker_faction == Factions.EMPIRE else "The Villain's troops"
	Game.post("%s are raiding the %s!" % [who, World.LOCATION_NAMES[loc].to_lower()], Color(1, 0.35, 0.35))


func _intruders_at(loc: String) -> void:
	if npc_count() > MAX_NPCS:
		return
	var target: Vector3 = world.locations[loc]
	var elves := randf() < 0.6 or loc == "fort"
	var a := randf() * TAU
	var start := target + Vector3(cos(a), 0, sin(a)) * 90.0
	start.x = clampf(start.x, -370, 370)
	start.z = clampf(start.z, -370, 370)
	var n := 3 if elves else 2
	for i in n:
		var f := Factions.ELVES if elves else Factions.VILLAIN
		spawn_npc(f, "partisan" if elves else "spy", start + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)),
				{"order": "attack_move", "order_target": target, "transient": true})
	if elves:
		Game.post("Elven partisans are sneaking up on the %s!" % World.LOCATION_NAMES[loc].to_lower(), Color(1, 0.45, 0.35))
	else:
		Game.post("The Villain's spies have been seen near the palace!", Color(1, 0.45, 0.35))
	if loc == "palace" and mission.is_empty():
		var cmd = find_commander()
		if cmd:
			Game.post("%s: Guards, intruders near the palace! Kill them!" % cmd.display_name, Color(1, 0.8, 0.5))
			start_mission("defend")


func _reinforce() -> void:
	if npc_count() > MAX_NPCS:
		return
	var garrisons := [["palace", Factions.EMPIRE, 10], ["elf_village", Factions.ELVES, 8], ["human_village", Factions.HUMANS, 3]]
	if Game.player_faction != Factions.VILLAIN:
		garrisons.append(["fort", Factions.VILLAIN, 8])
	for g in garrisons:
		var loc: Vector3 = world.locations[g[0]]
		if g[0] == "palace" and palace_fallen:
			continue
		var have := 0
		for a in get_tree().get_nodes_in_group("actors"):
			if a is NPC and a.faction == g[1] and a.is_soldier and not a.transient and a.global_position.distance_to(loc) < 90.0:
				have += 1
		if have < g[2]:
			var a := randf() * TAU
			spawn_npc(g[1], "warrior", loc + Vector3(cos(a) * 20, 0, sin(a) * 20))
	if Game.player_faction == Factions.EMPIRE and find_commander() == null and not palace_fallen:
		var c := spawn_npc(Factions.EMPIRE, "commander", world.locations.palace + Vector3(0, 0, 6))
		Game.post("A new commander has arrived at the palace: %s." % c.display_name, Color(1, 0.8, 0.5))


func _check_victory() -> void:
	var p = Game.player
	if Game.player_faction == Factions.VILLAIN and not palace_fallen:
		var palace: Vector3 = world.locations.palace
		if p.global_position.distance_to(palace) < 60.0:
			var defenders := 0
			for a in get_tree().get_nodes_in_group("actors"):
				if a is NPC and a.faction == Factions.EMPIRE and a.is_soldier and a.global_position.distance_to(palace) < 70.0:
					defenders += 1
			if defenders == 0:
				palace_fallen = true
				Game.hud.show_banner("THE PALACE HAS FALLEN!\nThe Emperor's lands are yours.")
				Game.post("The palace has fallen! You rule the Emperor's lands now.", Color(0.85, 0.6, 1))


func _on_killed(victim, killer) -> void:
	var by_player: bool = killer != null and is_instance_valid(killer) and killer.is_player
	if victim.role == "boss" and not villain_dead:
		villain_dead = true
		if by_player:
			killer.gold += 300
			Game.hud.show_banner("THE VILLAIN IS DEAD!\n+300 gold")
		Game.post("The Villain has been slain!", Color(1, 0.9, 0.4))
	if victim.role == "commander" and mission.get("state", "") == "active" and mission.type != "defend":
		mission.state = "failed"
		Game.post("The commander has fallen! Return to the palace.", Color(1, 0.4, 0.4))
	if by_player and not victim.is_player:
		if Factions.hostile(victim.faction, Game.player_faction):
			Game.change_reputation(Game.player_faction, 2)
		else:
			Game.change_reputation(victim.faction, -15, "murder")
		if mission.get("state", "") == "active":
			var counts := false
			match mission.type:
				"defend":
					counts = Factions.hostile(victim.faction, Factions.EMPIRE) and victim.global_position.distance_to(world.locations.palace) < 160.0
				"raid_elves":
					counts = victim.faction == Factions.ELVES
				"raid_fort":
					counts = victim.faction == Factions.VILLAIN
			if counts:
				mission.kills += 1
				if mission.kills >= mission.need:
					_mission_done()


# --- palace guard: the commander's missions -------------------------------

func find_commander():
	for a in get_tree().get_nodes_in_group("actors"):
		if a is NPC and a.role == "commander" and a.faction == Factions.EMPIRE:
			return a
	return null


func mission_text() -> String:
	if mission.is_empty():
		if Game.player_faction == Factions.EMPIRE:
			return "No orders. Report to the commander (E)."
		return ""
	var names := {"defend": "Defend the palace", "raid_elves": "Raid on the elven village", "raid_fort": "Raid on the Villain's fort"}
	match mission.state:
		"active":
			var extra := ""
			if mission.type != "defend":
				extra = "  -  stay close to the commander!"
			return "%s: %d/%d enemies%s" % [names[mission.type], mission.kills, mission.need, extra]
		"done":
			return "%s: done. Report to the commander for your pay." % names[mission.type]
		"failed":
			return "%s: failed. Report to the commander." % names[mission.type]
	return ""


## Called by the commander dialog. Returns what the commander says.
func commander_talk() -> String:
	var p = Game.player
	if mission.is_empty():
		var kinds := ["raid_elves", "defend", "raid_fort"]
		var kind: String = kinds[mission_counter % kinds.size()]
		start_mission(kind)
		match kind:
			"raid_elves":
				return "Soldier! We ride against the elves. Follow me and do not fall behind: deserters get nothing. Kill 5 elves."
			"raid_fort":
				return "Soldier! We raid the Villain's old fort. Stay at my side and kill 5 of his cutthroats."
			_:
				return "Patrol the palace grounds. Spies and partisans are about. Kill 3 intruders."
	match mission.state:
		"done":
			var pay := 80 if mission.type == "defend" else 150
			p.gold += pay
			Game.change_reputation(Factions.EMPIRE, 10)
			mission = {}
			return "Good work, soldier. Here is your pay: %d gold. Rest, then report for new orders." % pay
		"failed":
			mission = {}
			return "You failed the mission. No pay this time. Report again when you are ready to obey."
	return "You have your orders, soldier! " + mission_text()


func start_mission(kind: String) -> void:
	mission_counter += 1
	mission = {"type": kind, "kills": 0, "need": 3 if kind == "defend" else 5, "state": "active", "away": 0.0, "warned": 0.0}
	if kind == "defend":
		intruder_t = minf(intruder_t, 8.0)
		return
	var cmd = find_commander()
	if cmd == null:
		return
	var target: Vector3 = world.locations["elf_village" if kind == "raid_elves" else "fort"]
	cmd.order = "attack_move"
	cmd.order_target = target
	cmd.perception = 30.0
	var squad := 0
	for a in get_tree().get_nodes_in_group("actors"):
		if squad >= 6:
			break
		if a is NPC and a != cmd and a.faction == Factions.EMPIRE and a.is_soldier and a.global_position.distance_to(cmd.global_position) < 60.0:
			a.order = "follow"
			a.leader = cmd
			squad += 1
	Game.post("%s: Squad, follow me! Forward!" % cmd.display_name, Color(1, 0.8, 0.5))


func _update_mission(delta: float) -> void:
	if mission.get("state", "") != "active" or mission.type == "defend":
		return
	var cmd = find_commander()
	var p = Game.player
	if cmd == null:
		return
	if p.global_position.distance_to(cmd.global_position) > 60.0:
		mission.away += delta
		mission.warned -= delta
		if mission.warned <= 0.0:
			mission.warned = 6.0
			Game.post("%s: Get back in formation, soldier! That's an order!" % cmd.display_name, Color(1, 0.6, 0.3))
		if mission.away > 30.0:
			mission.state = "failed"
			Game.change_reputation(Factions.EMPIRE, -15, "desertion")
			Game.post("You disobeyed the commander. Deserters get no pay!", Color(1, 0.3, 0.3))
			_squad_return(cmd)
	else:
		mission.away = maxf(0.0, mission.away - delta * 0.5)


func _mission_done() -> void:
	mission.state = "done"
	Game.post("Mission complete! Report to the commander for your pay.", Color(0.6, 1, 0.6))
	var cmd = find_commander()
	if cmd != null and mission.type != "defend":
		Game.post("%s: Well fought! Back to the palace!" % cmd.display_name, Color(1, 0.8, 0.5))
		_squad_return(cmd)


func _squad_return(cmd) -> void:
	var palace: Vector3 = world.locations.palace
	cmd.order = "move"
	cmd.order_target = palace + Vector3(0, 0, 6)
	for a in get_tree().get_nodes_in_group("actors"):
		if a is NPC and a.leader == cmd:
			a.order = "move"
			a.order_target = palace + Vector3(randf_range(-12, 12), 0, randf_range(0, 14))
			a.leader = null


# --- the Villain: the player's own army ------------------------------------

func army() -> Array:
	var out: Array = []
	for a in get_tree().get_nodes_in_group("actors"):
		if a is NPC and a.army:
			out.append(a)
	return out


func villain_order(n: int) -> void:
	if Game.player_faction != Factions.VILLAIN:
		return
	var troops := army()
	if troops.is_empty():
		Game.post("You have no army. Recruit soldiers at the fort.", Color(1, 0.6, 0.3))
		return
	var p = Game.player
	for t in troops:
		t.target = null
		t.leader = null
		match n:
			1:
				t.order = "follow"
				t.leader = p
			2:
				t.order = "hold"
			3:
				t.order = "attack_move"
				t.order_target = world.locations.palace + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
			4:
				t.order = "attack_move"
				t.order_target = world.locations.elf_village + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
			5:
				t.order = "move"
				t.order_target = world.locations.fort + Vector3(randf_range(-10, 10), 0, randf_range(0, 12))
	var texts := {
		1: ["follow", "Follow me!"], 2: ["hold", "Hold this position!"],
		3: ["attack the palace", "To the palace! Attack!"], 4: ["raid the elves", "Burn the elven village!"],
		5: ["return to the fort", "Back to the fort!"],
	}
	army_order = texts[n][0]
	Game.post("You shout: \"%s\" (%d soldiers)" % [texts[n][1], troops.size()], Color(0.85, 0.6, 1))


func recruit(kind: String) -> bool:
	var p = Game.player
	var cost := 40 if kind == "warrior" else 60
	if p.gold < cost:
		Game.post("Not enough gold.", Color(1, 0.6, 0.3))
		return false
	p.gold -= cost
	var n := spawn_npc(Factions.VILLAIN, kind, world.locations.fort + Vector3(randf_range(-4, 4), 0, 16))
	n.army = true
	if army_order == "follow":
		n.order = "follow"
		n.leader = p
	Game.post("%s joins your army." % n.display_name, Color(0.85, 0.6, 1))
	return true


# --- save / load ----------------------------------------------------------

func serialize() -> Dictionary:
	var npcs: Array = []
	for a in get_tree().get_nodes_in_group("actors"):
		if a is NPC:
			npcs.append(a.to_dict())
	var caravans: Array = []
	for c in get_tree().get_nodes_in_group("caravans"):
		caravans.append(c.to_dict())
	var corpses: Array = []
	for c in get_tree().get_nodes_in_group("corpses"):
		if not c.is_queued_for_deletion():
			corpses.append(c.to_dict())
	return {
		"version": 1,
		"faction": Game.player_faction,
		"reputation": Game.reputation,
		"player": Game.player.to_dict(),
		"npcs": npcs,
		"caravans": caravans,
		"corpses": corpses,
		"director": {
			"uid_counter": uid_counter, "caravan_counter": caravan_counter, "caravan_t": caravan_t,
			"raid_t": raid_t, "intruder_t": intruder_t, "palace_fallen": palace_fallen,
			"villain_dead": villain_dead, "raid_count": raid_count, "mission": mission,
			"mission_counter": mission_counter, "army_order": army_order,
		},
	}


func restore(data: Dictionary) -> void:
	var d: Dictionary = data.get("director", {})
	uid_counter = int(d.get("uid_counter", 0))
	caravan_counter = int(d.get("caravan_counter", 0))
	caravan_t = float(d.get("caravan_t", 30))
	raid_t = float(d.get("raid_t", 110))
	intruder_t = float(d.get("intruder_t", 80))
	palace_fallen = bool(d.get("palace_fallen", false))
	villain_dead = bool(d.get("villain_dead", false))
	raid_count = int(d.get("raid_count", 0))
	mission = d.get("mission", {})
	if mission.has("kills"):
		mission.kills = int(mission.kills)
		mission.need = int(mission.need)
	mission_counter = int(d.get("mission_counter", 0))
	army_order = str(d.get("army_order", "guard"))
	var rep: Dictionary = data.get("reputation", {})
	Game.reputation = {0: 0, 1: 0, 2: 0, 3: 0}
	for k in rep:
		Game.reputation[int(k)] = int(rep[k])

	var p := Player.new()
	p.name = "Player"
	p.from_dict(data.get("player", {}))
	p.is_player = true
	world.actors_root.add_child(p)
	Game.player = p

	var by_uid := {"player": p}
	var npcs: Array = []
	for nd in data.get("npcs", []):
		var n := NPC.new()
		n.from_dict(nd)
		world.actors_root.add_child(n)
		by_uid[n.uid] = n
		npcs.append(n)
	var caravans := {}
	for cd in data.get("caravans", []):
		var c := Caravan.new()
		c.from_dict(cd)
		world.actors_root.add_child(c)
		caravans[c.cid] = c
	for n in npcs:
		if n.leader_uid != "" and by_uid.has(n.leader_uid):
			n.leader = by_uid[n.leader_uid]
		if n.escort_cid >= 0 and caravans.has(n.escort_cid):
			n.escort = caravans[n.escort_cid]
			caravans[n.escort_cid].guards.append(n)
	for cd in data.get("corpses", []):
		var corpse := Corpse.new()
		world.add_corpse(corpse)
		corpse.restore(cd)
	Game.post("Game loaded.", Color(0.6, 1, 0.6))
