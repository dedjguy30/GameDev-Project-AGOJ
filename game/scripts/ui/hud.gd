class_name HUD
extends Control

var _board: Board
var _stats_label: Label
var _event_popup: Panel
var _event_card_ref: Card
var _game_over_panel: Panel
var _choice_buttons: Array[Button] = []

func setup(board: Board) -> void:
	_board = board
	name = "HUD"
	z_index = 500
	_build_stats_bar()
	_build_buttons()
	_build_event_popup()
	_build_game_over_panel()
	_refresh_stats()
	GameState.stats_changed.connect(_refresh_stats)
	GameState.credits_changed.connect(func(_c: int) -> void: _refresh_stats())
	GameState.reputation_changed.connect(func(_r: int) -> void: _refresh_stats())
	GameState.day_changed.connect(func(_d: int) -> void: _refresh_stats())
	GameState.game_over.connect(_on_game_over)

func _build_stats_bar() -> void:
	_stats_label = Label.new()
	_stats_label.position = Vector2(500, 8)
	_stats_label.add_theme_font_size_override("font_size", 18)
	_stats_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stats_label)

func _refresh_stats() -> void:
	_stats_label.text = "Hari %d   O2 %.0f   Food %.0f   Hull %.0f   Power %.0f/%d   Cr %d   Rep %d   Skor %d" % [
		GameState.day, GameState.oxygen, GameState.food, GameState.hull,
		GameState.power, int(GameState.power_cap), GameState.credits,
		GameState.reputation, GameState.score]

func _build_buttons() -> void:
	var end_day := Button.new()
	end_day.text = "End Day"
	end_day.position = Vector2(1100, 8)
	end_day.size = Vector2(140, 42)
	end_day.pressed.connect(DayCycle.end_day)
	add_child(end_day)

	var pack_ids: Array[String] = []
	for pack in RecipeDB.all_packs():
		pack_ids.append(pack.id)
	var x := 1100.0
	for pack_id in pack_ids:
		var pack := RecipeDB.get_pack(pack_id)
		var btn := Button.new()
		btn.text = "%s (%d cr)" % [pack.display_name, Economy.pack_cost(pack_id)]
		btn.position = Vector2(x, 60)
		btn.size = Vector2(200, 42)
		btn.pressed.connect(_buy_pack.bind(pack_id))
		add_child(btn)
		x += 210.0
	_update_pack_button_labels(pack_ids)

func _update_pack_button_labels(pack_ids: Array[String]) -> void:
	for child in get_children():
		var btn := child as Button
		if btn == null or not btn.pressed.is_connected(_buy_pack):
			continue
		# simpel: cari pack id dari posisi — label di-refresh penuh di sini
		var pack := RecipeDB.get_pack(pack_ids[0])
		if pack != null:
			btn.text = "%s (%d cr)" % [pack.display_name, Economy.pack_cost(pack_ids[0])]

func _buy_pack(pack_id: String) -> void:
	if Economy.buy_pack(pack_id):
		_refresh_pack_buttons()

func _refresh_pack_buttons() -> void:
	var pack_ids: Array[String] = []
	for pack in RecipeDB.all_packs():
		pack_ids.append(pack.id)
	for child in get_children():
		var btn := child as Button
		if btn == null or not btn.pressed.is_connected(_buy_pack):
			continue
		btn.text = "Pack (%d cr)" % 0
	var x := 1100.0
	for pack_id in pack_ids:
		var pack := RecipeDB.get_pack(pack_id)
		for child in get_children():
			var btn := child as Button
			if btn == null:
				continue
			if btn.position.x == x and btn.position.y == 60.0:
				btn.text = "%s (%d cr)" % [pack.display_name, Economy.pack_cost(pack_id)]
		x += 210.0

# ---------- Event choice popup (A9 PLAYER_CHOICE) ----------

func _build_event_popup() -> void:
	_event_popup = Panel.new()
	_event_popup.position = Vector2(760, 300)
	_event_popup.size = Vector2(440, 300)
	_event_popup.visible = false
	_event_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_event_popup)

func show_event_choices(card: Card, event_data: EventCardData) -> void:
	if _event_card_ref != null and is_instance_valid(_event_card_ref) \
			and _event_card_ref != card:
		return
	_event_card_ref = card
	for btn in _choice_buttons:
		btn.queue_free()
	_choice_buttons.clear()
	var title := Label.new()
	title.text = event_data.display_name
	title.position = Vector2(16, 12)
	title.add_theme_font_size_override("font_size", 20)
	title.size = Vector2(400, 30)
	_event_popup.add_child(title)
	var desc := Label.new()
	desc.text = event_data.description
	desc.position = Vector2(16, 48)
	desc.size = Vector2(400, 60)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_popup.add_child(desc)
	var y := 120.0
	for i in event_data.choices.size():
		var choice: Dictionary = event_data.choices[i]
		var btn := Button.new()
		btn.text = choice.get("label", "Pilih")
		btn.position = Vector2(16, y)
		btn.size = Vector2(408, 40)
		btn.pressed.connect(_resolve_choice.bind(i))
		_event_popup.add_child(btn)
		_choice_buttons.append(btn)
		y += 50.0
	_event_popup.visible = true

func _resolve_choice(index: int) -> void:
	if _event_card_ref == null:
		return
	var board: Board = get_tree().get_first_node_in_group(&"board")
	Events.apply_event(board, _event_card_ref.get_card_id(), index)
	if is_instance_valid(_event_card_ref):
		_event_card_ref.queue_free()
	_event_card_ref = null
	_event_popup.visible = false

# ---------- Game over (A16) ----------

func _build_game_over_panel() -> void:
	_game_over_panel = Panel.new()
	_game_over_panel.position = Vector2(660, 320)
	_game_over_panel.size = Vector2(640, 340)
	_game_over_panel.visible = false
	_game_over_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_game_over_panel)

func _on_game_over(reason: String) -> void:
	_game_over_panel.visible = true
	var title := Label.new()
	title.text = "GAME OVER"
	title.position = Vector2(0, 24)
	title.size = Vector2(640, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	_game_over_panel.add_child(title)
	var reason_label := Label.new()
	reason_label.text = reason
	reason_label.position = Vector2(0, 90)
	reason_label.size = Vector2(640, 40)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_panel.add_child(reason_label)
	var score_label := Label.new()
	score_label.text = "Skor Akhir: %d  (Hari %d, %d paket terkirim)" % [
		GameState.score, GameState.day, GameState.total_packages_delivered]
	score_label.position = Vector2(0, 150)
	score_label.size = Vector2(640, 40)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 22)
	_game_over_panel.add_child(score_label)
	var restart := Button.new()
	restart.text = "Main Lagi"
	restart.position = Vector2(240, 240)
	restart.size = Vector2(160, 48)
	restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	_game_over_panel.add_child(restart)