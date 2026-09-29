class_name HUD
extends CanvasLayer
## In-game interface. Built in code: health, bleeding, body status,
## gold, zone, mission, messages, minimap, the half-screen blindness
## overlay for lost eyes, and all dialog windows.

const CONTROLS := """WASD - move      Shift - sprint      Space - jump
Mouse - look      Wheel - camera distance
LMB - sword (look up = aim at head/eyes, look down = aim at legs)
RMB - bow (elves)      E - interact / trade / rob caravan / search body
B - bandage (stops bleeding)      H - healing potion
I / Tab - inventory      M - big map      F5 - save      F9 - load
1-5 - army orders (Villain): follow / hold / attack palace / raid elves / return
Esc - menu      F1 - hide this help"""

var hp_bar: ProgressBar
var hp_label: Label
var bleed_label: Label
var body_label: Label
var gold_label: Label
var zone_label: Label
var mission_label: Label
var prompt_label: Label
var aim_label: Label
var log_box: VBoxContainer
var blind_l: TextureRect
var blind_r: TextureRect
var flash: ColorRect
var minimap: Minimap
var help: Label
var banner: Label
var panel: PanelContainer
var panel_title: Label
var panel_body: VBoxContainer
var panel_close: Button
var panel_kind := ""
var panel_ctx = null
var _banner_t := 0.0
var _help_t := 25.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# lost-eye overlays (drawn first so the HUD text stays readable)
	blind_l = _blind_half(root, false)
	blind_r = _blind_half(root, true)

	flash = ColorRect.new()
	flash.color = Color(0.8, 0, 0, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

	var top_left := VBoxContainer.new()
	top_left.position = Vector2(16, 16)
	top_left.custom_minimum_size = Vector2(300, 0)
	root.add_child(top_left)
	hp_bar = ProgressBar.new()
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(300, 22)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.1, 0.1)
	hp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	hp_bar.add_theme_stylebox_override("background", bg)
	top_left.add_child(hp_bar)
	hp_label = _label(top_left, 16)
	bleed_label = _label(top_left, 18, Color(1, 0.25, 0.25))
	body_label = _label(top_left, 14, Color(0.9, 0.9, 0.9))
	gold_label = _label(top_left, 16, Color(1, 0.85, 0.35))

	zone_label = _label(root, 22, Color(1, 1, 0.85))
	zone_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_label.offset_left = -300
	zone_label.offset_right = 300
	zone_label.offset_top = 12
	mission_label = _label(root, 16, Color(1, 0.8, 0.5))
	mission_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_label.offset_left = -400
	mission_label.offset_right = 400
	mission_label.offset_top = 44

	var cross := _label(root, 22)
	cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.offset_left = -20
	cross.offset_right = 20
	cross.offset_top = -16
	aim_label = _label(root, 12, Color(1, 1, 1, 0.6))
	aim_label.set_anchors_preset(Control.PRESET_CENTER)
	aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aim_label.offset_left = -100
	aim_label.offset_right = 100
	aim_label.offset_top = 12

	prompt_label = _label(root, 20, Color(1, 1, 0.6))
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.offset_left = -400
	prompt_label.offset_right = 400
	prompt_label.offset_top = -200

	log_box = VBoxContainer.new()
	log_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_box.offset_left = 16
	log_box.offset_top = -220
	log_box.offset_right = 760
	log_box.offset_bottom = -16
	log_box.alignment = BoxContainer.ALIGNMENT_END
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)

	minimap = Minimap.new()
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -216
	minimap.offset_right = -16
	minimap.offset_top = 16
	minimap.offset_bottom = 216
	root.add_child(minimap)

	help = _label(root, 15, Color(0.95, 0.95, 0.95))
	help.text = CONTROLS
	help.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	help.offset_left = -640
	help.offset_right = -16
	help.offset_top = -40
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0, 0, 0, 0.5)
	hb.set_content_margin_all(10)
	help.add_theme_stylebox_override("normal", hb)

	banner = _label(root, 44, Color(1, 0.9, 0.5))
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.offset_left = -600
	banner.offset_right = 600
	banner.offset_top = -200
	banner.visible = false

	_build_panel(root)
	Game.message_posted.connect(_on_message)


func _blind_half(root: Control, right: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 1))
	g.set_color(1, Color(0, 0, 0, 0))
	g.add_point(0.8, Color(0, 0, 0, 1))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.flip_h = right
	tr.anchor_top = 0.0
	tr.anchor_bottom = 1.0
	tr.anchor_left = 0.48 if right else 0.0
	tr.anchor_right = 1.0 if right else 0.52
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.visible = false
	root.add_child(tr)
	return tr


func _label(parent: Control, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# --- per frame ------------------------------------------------------------

func _process(delta: float) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	hp_bar.max_value = p.max_hp
	hp_bar.value = maxf(p.hp, 0.0)
	hp_label.text = "Health %d / %d" % [ceili(maxf(p.hp, 0.0)), p.max_hp]
	if p.bleeding > 0.0 and not p.dead:
		var secs := int(p.hp / p.bleeding)
		bleed_label.text = "BLEEDING! Death in ~%d s. Bandage: B (%d left)" % [secs, p.count_item("bandage")]
		bleed_label.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01)
	else:
		bleed_label.text = ""
	body_label.text = _body_text(p)
	gold_label.text = "Gold: %d" % p.gold
	if Game.world:
		zone_label.text = Factions.ZONE_NAMES[Game.world.zone_at(p.global_position)]
	var m := ""
	if Game.director:
		m = Game.director.mission_text()
		if Game.player_faction == Factions.VILLAIN:
			m = "Your army: %d soldiers, order: %s  (keys 1-5)" % [Game.director.army().size(), Game.director.army_order]
	mission_label.text = m
	aim_label.text = "aim: " + p.aim_name() if not p.dead else ""
	blind_l.visible = p.parts.eye_l == "lost"
	blind_r.visible = p.parts.eye_r == "lost"
	flash.color.a = maxf(0.0, flash.color.a - delta * 1.5)
	_help_t -= delta
	if _help_t <= 0.0 and help.visible and _help_t > -1.0:
		help.visible = false
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.visible = _banner_t > 0.0
	var now := Time.get_ticks_msec()
	for l in log_box.get_children():
		var age: int = now - int(l.get_meta("t", now))
		if age > 12000:
			l.queue_free()
		elif age > 9000:
			l.modulate.a = 1.0 - (age - 9000) / 3000.0


func _body_text(p) -> String:
	var lines: Array = []
	for part in ["arm_l", "arm_r", "leg_l", "leg_r", "eye_l", "eye_r"]:
		var st: String = p.parts[part]
		var word: String = {"ok": "ok", "lost": "LOST", "prosthetic": "prosthesis"}[st]
		lines.append("%s: %s" % [Actor.PART_NAMES[part].capitalize(), word])
	var mob: String = {"walk": "walking", "crawl": "CRAWLING (buy a wheelchair or a prosthetic leg)", "wheelchair": "in a wheelchair"}[p.mobility()]
	return "  ".join(lines.slice(0, 2)) + "\n" + "  ".join(lines.slice(2, 4)) + "\n" + "  ".join(lines.slice(4, 6)) + "\nMovement: " + mob


func set_prompt(text: String) -> void:
	prompt_label.text = text


func flash_damage() -> void:
	flash.color.a = 0.35


func show_banner(text: String, secs := 6.0) -> void:
	banner.text = text
	banner.visible = true
	_banner_t = secs


func _on_message(text: String, color: Color) -> void:
	var l := _label(log_box, 16, color)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(740, 0)
	l.set_meta("t", Time.get_ticks_msec())
	while log_box.get_child_count() > 7:
		var old := log_box.get_child(0)
		log_box.remove_child(old)
		old.queue_free()


# --- input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	if event.is_action_pressed("pause"):
		if panel.visible and panel_kind != "death":
			close_panel()
		elif not panel.visible:
			open_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("help"):
		help.visible = not help.visible
		_help_t = -2.0
	elif event.is_action_pressed("map"):
		_toggle_big_map()
	elif event.is_action_pressed("quicksave"):
		Game.save_game()
	elif event.is_action_pressed("quickload"):
		Game.load_game()
	elif event.is_action_pressed("inventory") and not p.dead:
		if panel.visible and panel_kind == "inventory":
			close_panel()
		elif not panel.visible:
			open_inventory()
	elif not panel.visible and not p.dead:
		for i in range(1, 6):
			if event.is_action_pressed("order_%d" % i):
				Game.director.villain_order(i)


func _toggle_big_map() -> void:
	minimap.big = not minimap.big
	if minimap.big:
		minimap.set_anchors_preset(Control.PRESET_CENTER)
		minimap.offset_left = -330
		minimap.offset_right = 330
		minimap.offset_top = -330
		minimap.offset_bottom = 330
	else:
		minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		minimap.offset_left = -216
		minimap.offset_right = -16
		minimap.offset_top = 16
		minimap.offset_bottom = 216


# --- dialog windows -------------------------------------------------------

func _build_panel(root: Control) -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -270
	panel.offset_bottom = 270
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.09, 0.08, 0.94)
	sb.border_color = Color(0.7, 0.55, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	panel_title = _label(v, 24, Color(1, 0.85, 0.5))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	panel_body = VBoxContainer.new()
	panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_body)
	panel_close = Button.new()
	panel_close.text = "Close (Esc)"
	panel_close.pressed.connect(close_panel)
	v.add_child(panel_close)
	panel.visible = false


func _open(title: String, kind: String, ctx = null) -> void:
	panel_kind = kind
	panel_ctx = ctx
	panel_title.text = title
	for c in panel_body.get_children():
		panel_body.remove_child(c)
		c.queue_free()
	panel.visible = true
	panel_close.visible = kind != "death"
	Game.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_panel() -> void:
	panel.visible = false
	panel_kind = ""
	Game.ui_open = false
	get_tree().paused = false
	var p = Game.player
	if p != null and is_instance_valid(p) and not p.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _text(t: String, color := Color(0.92, 0.92, 0.88), size := 16) -> Label:
	var l := _label(panel_body, size, color)
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	return l


func _row(t: String, button: String, cb: Callable, enabled := true) -> void:
	var h := HBoxContainer.new()
	panel_body.add_child(h)
	var l := _label(h, 15, Color(0.92, 0.92, 0.88))
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Button.new()
	b.text = button
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(130, 0)
	b.pressed.connect(cb)
	h.add_child(b)


func _price_mult(npc) -> float:
	return 1.5 if int(Game.reputation.get(npc.faction, 0)) < -10 else 1.0


func open_shop(npc) -> void:
	var p = Game.player
	_open("Trade: %s" % npc.display_name, "shop", npc)
	_text("Your gold: %d" % p.gold, Color(1, 0.85, 0.35), 18)
	var mult := _price_mult(npc)
	if mult > 1.0:
		_text("They don't like you. Prices are higher.", Color(1, 0.5, 0.4))
	_text("Buy", Color(1, 0.85, 0.5), 20)
	for id in ItemDB.stock_for(npc.faction):
		var price := int(ItemDB.price(id) * mult)
		var buy := func():
			if p.gold >= price:
				p.gold -= price
				p.add_item(id)
				Game.post("Bought: %s" % ItemDB.name_of(id), Color(0.6, 1, 0.6))
			open_shop(npc)
		_row("%s - %d gold. %s" % [ItemDB.name_of(id), price, ItemDB.ITEMS[id].desc], "Buy", buy, p.gold >= price)
	_text("Sell", Color(1, 0.85, 0.5), 20)
	if p.inventory.is_empty():
		_text("You have nothing to sell.")
	for id in p.inventory.keys():
		var price := ItemDB.sell_price(id)
		var sell := func():
			p.add_item(id, -1)
			p.gold += price
			open_shop(npc)
		_row("%s x%d - %d gold each" % [ItemDB.name_of(id), p.inventory[id], price], "Sell", sell)


func open_healer(npc) -> void:
	var p = Game.player
	_open("Healer: %s" % npc.display_name, "healer", npc)
	_text("Your gold: %d" % p.gold, Color(1, 0.85, 0.35), 18)
	var mult := _price_mult(npc)
	var cost := int(25 * mult)
	var needs: bool = p.bleeding > 0.0 or p.hp < p.max_hp
	var treat := func():
		if p.gold >= cost:
			p.gold -= cost
			p.apply_bandage()
			p.heal(p.max_hp)
			Game.post("%s treats your wounds." % npc.display_name, Color(0.6, 1, 0.6))
		open_healer(npc)
	_row("Treat wounds: stop the bleeding and restore health - %d gold" % cost, "Treat", treat, needs and p.gold >= cost)
	var kinds := {"arm": "prosthetic_arm", "leg": "prosthetic_leg", "eye": "glass_eye"}
	for kind in kinds:
		var item: String = kinds[kind]
		if not p.has_lost(kind):
			continue
		var owned: bool = p.count_item(item) > 0
		var fit_cost := int((15 if owned else ItemDB.price(item) + 15) * mult)
		var fit := func():
			if p.gold >= fit_cost:
				p.gold -= fit_cost
				if owned:
					p.add_item(item, -1)
				p.install_prosthesis(kind)
				Game.post("%s fits you with a %s." % [npc.display_name, ItemDB.name_of(item).to_lower()], Color(0.6, 1, 0.6))
			open_healer(npc)
		_row("Fit a %s%s - %d gold" % [ItemDB.name_of(item).to_lower(), " (you have one)" if owned else "", fit_cost], "Fit", fit, p.gold >= fit_cost)
	if p.legs_lost() > 0 and not p.has_wheelchair:
		var wc := int(ItemDB.price("wheelchair") * mult)
		var buy_wc := func():
			if p.gold >= wc:
				p.gold -= wc
				p.has_wheelchair = true
				Game.post("You got a wheelchair.", Color(0.6, 1, 0.6))
			open_healer(npc)
		_row("Buy a wheelchair (instead of crawling) - %d gold" % wc, "Buy", buy_wc, p.gold >= wc)
	var bcost := int(ItemDB.price("bandage") * mult)
	var buy_bandage := func():
		if p.gold >= bcost:
			p.gold -= bcost
			p.add_item("bandage")
		open_healer(npc)
	_row("Bandage - %d gold" % bcost, "Buy", buy_bandage, p.gold >= bcost)


func open_commander(npc) -> void:
	_open(npc.display_name, "commander", npc)
	_text(Game.director.commander_talk(), Color(1, 0.9, 0.7), 18)
	var b := Button.new()
	b.text = "Yes, sir!"
	b.pressed.connect(close_panel)
	panel_body.add_child(b)


func open_recruit(npc) -> void:
	var p = Game.player
	_open("%s - your army" % npc.display_name, "recruit", npc)
	_text("Your gold: %d.  Army: %d soldiers." % [p.gold, Game.director.army().size()], Color(1, 0.85, 0.35), 18)
	var sword := func():
		Game.director.recruit("warrior")
		open_recruit(npc)
	var bow := func():
		Game.director.recruit("archer")
		open_recruit(npc)
	_row("Recruit a cutthroat (sword) - 40 gold", "Recruit", sword, p.gold >= 40)
	_row("Recruit a raider (bow) - 60 gold", "Recruit", bow, p.gold >= 60)
	_text("\nOrders: 1 follow me, 2 hold position, 3 attack the palace, 4 raid the elves, 5 return to the fort.")


func open_inventory() -> void:
	var p = Game.player
	_open("Inventory", "inventory")
	_text("Gold: %d    Weapon: %s    Armor: %s" % [p.gold, ItemDB.name_of(p.weapon) if p.weapon != "" else "fists",
			ItemDB.name_of(p.armor_item) if p.armor_item != "" else "none"], Color(1, 0.85, 0.35), 18)
	if p.has_wheelchair:
		var toggle := func():
			p.use_wheelchair = not p.use_wheelchair
			open_inventory()
		_row("Wheelchair: %s" % ("used when a leg is missing" if p.use_wheelchair else "not used"), "Toggle", toggle)
	if p.inventory.is_empty():
		_text("Your bag is empty.")
	for id in p.inventory.keys():
		var use := func():
			p.use_item(id)
			if panel_kind == "inventory":
				open_inventory()
		_row("%s x%d - %s" % [ItemDB.name_of(id), p.inventory[id], ItemDB.ITEMS.get(id, {}).get("desc", "")], "Use", use)


func open_pause() -> void:
	_open("Paused", "pause")
	get_tree().paused = true
	var save := func():
		Game.save_game()
		close_panel()
	var controls := func():
		help.visible = true
		_help_t = -2.0
		close_panel()
	_button("Resume", close_panel)
	_button("Save game (F5)", save)
	_button("Load game (F9)", func(): Game.load_game())
	_button("Controls (F1)", controls)
	_button("Quit to main menu", func(): Game.quit_to_menu())
	_button("Quit game", func(): get_tree().quit())


func show_death() -> void:
	_open("You died", "death")
	_text("Your story ends here... unless you load a saved game.", Color(1, 0.6, 0.6), 18)
	_button("Load last save", func(): Game.load_game(), Game.has_save())
	_button("New game (main menu)", func(): Game.quit_to_menu())


func _button(text: String, cb: Callable, enabled := true) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(0, 36)
	panel_body.add_child(b)
