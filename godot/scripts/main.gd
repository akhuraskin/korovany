extends Node
## Entry point: shows the main menu, or builds the world for a new or
## loaded game.

var world: World
var director: Director
var hud: HUD
var manual := false  # tests call start_game() themselves


func _ready() -> void:
	if manual:
		return
	if Game.player_faction < 0:
		add_child(MainMenu.new())
		return
	var loading := Label.new()
	loading.text = "Building the world..."
	loading.add_theme_font_size_override("font_size", 32)
	loading.set_anchors_preset(Control.PRESET_CENTER)
	var layer := CanvasLayer.new()
	layer.add_child(loading)
	add_child(layer)
	await get_tree().process_frame
	await get_tree().process_frame
	start_game(Game.player_faction, Game.pending_save)
	layer.queue_free()


func start_game(faction: int, save: Dictionary) -> void:
	Game.player_faction = faction
	world = World.new()
	world.name = "World"
	add_child(world)
	Game.world = world
	world.build()
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	Game.hud = hud
	director = Director.new()
	director.name = "Director"
	add_child(director)
	Game.director = director
	if save.is_empty():
		director.new_game()
	else:
		director.restore(save)
	Game.pending_save = {}


func _exit_tree() -> void:
	if Game.world == world:
		Game.world = null
		Game.player = null
		Game.hud = null
		Game.director = null
