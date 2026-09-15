class_name IntroOverlay
extends ColorRect

# Intro: pemain pilih 1 dari 3 pack (data-driven, GDD S3.3).
# Board memanggil setup() lalu menunggu signal finished(kit).

signal finished(kit: Array)

const INTRO_PACKS: Array = [
	{
		"name": "Survivor Pack",
		"color": Color(0.55, 0.9, 0.55),
		"kit": [["unit_astronaut", 1], ["item_water", 2], ["item_food", 2], ["item_mushroom", 1], ["item_space_rock", 2], ["item_scrap_metal", 1]],
	},
	{
		"name": "Miner Pack",
		"color": Color(0.6, 0.6, 0.65),
		"kit": [["unit_astronaut", 1], ["item_iron", 2], ["item_space_rock", 2], ["item_scrap_metal", 2], ["item_water", 1], ["item_food", 1]],
	},
	{
		"name": "Technician Pack",
		"color": Color(0.5, 0.65, 0.95),
		"kit": [["unit_astronaut", 1], ["item_energy_cell", 1], ["item_component", 1], ["item_iron", 2], ["item_water", 1], ["item_mushroom", 1]],
	},
]

var _chosen := -1
var _view := Vector2.ZERO
var _packs_y := 170.0

func setup(board: Board) -> void:
	_view = board.get_viewport_rect().size
	color = Color(0, 0, 0, 0.78)
	# Ukuran eksplisit (jangan andalkan anchor: parent bisa berukuran 0
	# saat setup sehingga fill gelap tidak tampil + klik lolos).
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2.ZERO
	size = _view
	var title := UIFactory.label("Day 0 - The Accident", 28)
	title.position = Vector2(0, 60.0)
	title.size = Vector2(_view.x, 40)
	add_child(title)
	var sub := UIFactory.label("Oh no! you're stranded.. you need to choose one of your package to stay alive.", 16, Color(0.7, 0.8, 0.9))
	sub.position = Vector2(0, 108.0)
	sub.size = Vector2(_view.x, 30)
	add_child(sub)
	# Baris pack tepat di tengah vertikal & horizontal.
	_packs_y = _view.y * 0.5 - 125.0
	var total_w := INTRO_PACKS.size() * 180.0 + (INTRO_PACKS.size() - 1) * 20.0
	var x := _view.x * 0.5 - total_w * 0.5
	for i in INTRO_PACKS.size():
		_add_pack_panel(INTRO_PACKS[i], i, Vector2(x, _packs_y))
		x += 200.0

func _add_pack_panel(pack: Dictionary, index: int, pos: Vector2) -> void:
	var panel := UIFactory.panel(Vector2(180, 250), pack["color"])
	panel.position = pos
	add_child(panel)
	var name_label := UIFactory.label(String(pack["name"]), 17, Color(0.1, 0.1, 0.12))
	name_label.position = Vector2(6, 8)
	name_label.size = Vector2(168, 30)
	panel.add_child(name_label)
	var y := 44.0
	for entry in pack["kit"]:
		var data: CardData = CardDB.get_card(String(entry[0]))
		var item_name: String = data.display_name if data != null else String(entry[0])
		if int(entry[1]) > 1:
			item_name += " x%d" % int(entry[1])
		var line := UIFactory.label(item_name, 13, Color(0.1, 0.1, 0.12), HORIZONTAL_ALIGNMENT_LEFT)
		line.position = Vector2(12, y)
		line.size = Vector2(160, 20)
		panel.add_child(line)
		y += 22.0
	var pick := UIFactory.button("Choose", Vector2(140, 40))
	pick.position = Vector2(20, 202)
	pick.pressed.connect(choose_pack.bind(index))
	panel.add_child(pick)

func choose_pack(index: int) -> void:
	if _chosen >= 0 or index < 0 or index >= INTRO_PACKS.size():
		return
	_chosen = index
	for node in find_children("*", "Button", true, false):
		(node as Button).disabled = true
	var panels: Array[Control] = []
	for node in get_children():
		if node is Panel:
			panels.append(node)
	var punch := create_tween()
	punch.tween_property(panels[index], "scale", Vector2(1.08, 1.08), 0.12)
	punch.tween_property(panels[index], "scale", Vector2.ONE, 0.18)
	await punch.finished
	await _reveal_minis(INTRO_PACKS[index]["kit"])
	var start := UIFactory.button("Start", Vector2(180, 48))
	start.position = Vector2(_view.x * 0.5 - 90.0, _packs_y + 376.0)
	start.pressed.connect(_on_start)
	add_child(start)

func _reveal_minis(kit: Array) -> void:
	var y := _packs_y + 280.0
	var x := _view.x * 0.5 - (kit.size() * 88.0 + (kit.size() - 1) * 8.0) * 0.5
	for entry in kit:
		var data: CardData = CardDB.get_card(String(entry[0]))
		var mini := UIFactory.panel(Vector2(88, 72),
			data.get_placeholder_color() if data != null else Color(0.5, 0.5, 0.5), 6.0)
		mini.position = Vector2(x, y)
		mini.scale = Vector2.ZERO
		var mini_name: String = data.display_name if data != null else String(entry[0])
		if int(entry[1]) > 1:
			mini_name += " x%d" % int(entry[1])
		var mini_label := UIFactory.label(mini_name, 13, Color(0.1, 0.1, 0.12))
		mini_label.set_anchors_preset(Control.PRESET_FULL_RECT, false)
		mini_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mini.add_child(mini_label)
		add_child(mini)
		var pop := create_tween()
		pop.tween_property(mini, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(0.12).timeout
		x += 96.0

func _on_start() -> void:
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.4)
	fade.tween_callback(queue_free)
	finished.emit(INTRO_PACKS[_chosen]["kit"])
