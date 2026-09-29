class_name MainMenu
extends CanvasLayer
## Title screen: choose who to play.

const CHOICES := [
	[Factions.ELVES, "Forest Elves",
		"Live in wooden houses deep in the dense forest. Palace soldiers and the Villain's troops raid your village. Rob caravans on the roads!"],
	[Factions.EMPIRE, "Palace Guard",
		"Obey your commander. Defend the palace from the Villain, his spies and elven partisans. Go on raids against the elves and the Villain."],
	[Factions.VILLAIN, "The Villain",
		"(The name was never invented.) You are your own commander. Lead your army from the old fort in the mountains and storm the palace."],
]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.1, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(760, 0)
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	_label(v, "KOROVANY", 72, Color(1, 0.85, 0.45))
	_label(v, "A 3D action RPG in a world of four zones: humans, the Emperor, the elves and the Villain.", 18, Color(0.85, 0.85, 0.8))
	_label(v, "\"I've wanted a game like this for two years.\"", 16, Color(0.6, 0.7, 0.6))
	for c in CHOICES:
		var b := Button.new()
		b.text = "Play as: %s" % c[1]
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(Game.new_game.bind(c[0]))
		v.add_child(b)
		_label(v, c[2], 15, Color(0.75, 0.8, 0.75))
	if Game.has_save():
		var l := Button.new()
		l.text = "Continue (load saved game)"
		l.custom_minimum_size = Vector2(0, 40)
		l.pressed.connect(func(): Game.load_game())
		v.add_child(l)
	var q := Button.new()
	q.text = "Quit"
	q.custom_minimum_size = Vector2(0, 36)
	q.pressed.connect(func(): get_tree().quit())
	v.add_child(q)


func _label(parent: Control, text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
