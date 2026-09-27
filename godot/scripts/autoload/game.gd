extends Node
## Global game state: chosen faction, references to the running world,
## reputation, hostility rules, input map and save/load.

signal message_posted(text: String, color: Color)
signal actor_killed(victim, killer)

const SAVE_PATH := "user://savegame.json"
const MAIN_SCENE := "res://main.tscn"
const AGGRO_MS := 45000

var player_faction: int = -1
var pending_save: Dictionary = {}
var reputation := {0: 0, 1: 0, 2: 0, 3: 0}
var ui_open := false

var world = null
var player = null
var hud = null
var director = null


func _ready() -> void:
	_setup_input()


# --- messages -------------------------------------------------------------

func post(text: String, color: Color = Color.WHITE) -> void:
	message_posted.emit(text, color)


# --- hostility & reputation ------------------------------------------------

func are_hostile(a, b) -> bool:
	if a == null or b == null or a == b:
		return false
	if _has_aggro(a, b) or _has_aggro(b, a):
		return true
	if a.is_player:
		return is_hostile_to_player(b)
	if b.is_player:
		return is_hostile_to_player(a)
	return Factions.hostile(a.faction, b.faction)


func _has_aggro(a, b) -> bool:
	var id: int = b.get_instance_id()
	if not a.aggro.has(id):
		return false
	if Time.get_ticks_msec() - int(a.aggro[id]) > AGGRO_MS:
		a.aggro.erase(id)
		return false
	return true


func is_hostile_to_player(npc) -> bool:
	if Factions.hostile(npc.faction, player_faction):
		return true
	return int(reputation.get(npc.faction, 0)) <= -30


func change_reputation(faction: int, delta: int, reason: String = "") -> void:
	var before: int = reputation.get(faction, 0)
	reputation[faction] = clampi(before + delta, -100, 100)
	if before > -30 and reputation[faction] <= -30:
		post("%s now consider you an enemy!%s" % [Factions.NAMES[faction], "" if reason == "" else " (" + reason + ")"], Color(1, 0.35, 0.35))


func on_player_hit(victim) -> void:
	if not Factions.hostile(victim.faction, player_faction):
		change_reputation(victim.faction, -6, "you attacked " + victim.display_name)


# --- game flow ------------------------------------------------------------

func new_game(faction: int) -> void:
	player_faction = faction
	pending_save = {}
	reputation = {0: 0, 1: 0, 2: 0, 3: 0}
	_change_to_main()


func quit_to_menu() -> void:
	player_faction = -1
	pending_save = {}
	_change_to_main()


func _change_to_main() -> void:
	ui_open = false
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", MAIN_SCENE)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	if director == null or player == null or player.dead:
		post("You can't save right now.", Color(1, 0.6, 0.3))
		return false
	var data: Dictionary = director.serialize()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		post("Saving failed: %s" % error_string(FileAccess.get_open_error()), Color(1, 0.3, 0.3))
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	post("Game saved.", Color(0.6, 1, 0.6))
	return true


func read_save() -> Dictionary:
	if not has_save():
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func load_game() -> bool:
	var data := read_save()
	if data.is_empty():
		post("No saved game found.", Color(1, 0.6, 0.3))
		return false
	player_faction = int(data.get("faction", 0))
	pending_save = data
	_change_to_main()
	return true


# --- input ----------------------------------------------------------------

func _setup_input() -> void:
	# Physical keys, so WASD works on any keyboard layout (e.g. Russian).
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("sprint", [KEY_SHIFT])
	_key("interact", [KEY_E])
	_key("bandage", [KEY_B])
	_key("potion", [KEY_H])
	_key("inventory", [KEY_I, KEY_TAB])
	_key("map", [KEY_M])
	_key("help", [KEY_F1])
	_key("quicksave", [KEY_F5])
	_key("quickload", [KEY_F9])
	_key("pause", [KEY_ESCAPE])
	for i in range(1, 6):
		_key("order_%d" % i, [KEY_0 + i])
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_mouse("shoot", MOUSE_BUTTON_RIGHT)


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
