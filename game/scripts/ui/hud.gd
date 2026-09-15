class_name HUD
extends Control

var _board: Board
var _stats_label: Label
var _event_popup: Panel
var _event_card_ref: Card
var _game_over_panel: Panel
var _choice_buttons: Array[Button] = []
var _recipe_panel: Panel
var _pack_info_label: Label
var _hovered_pack_id := ""

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
	_stats_label.position = Vector2(16, 34)
	_stats_label.add_theme_font_size_override("font_size", 18)
	_stats_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stats_label)

func _refresh_stats() -> void:
	_stats_label.text = "Hari %d   O2 %.0f   Food %.0f   Hull %.0f   Power %.0f/%d   Cr %d   Rep %d   Skor %d" % [
		GameState.day, GameState.oxygen, GameState.food, GameState.hull,
		GameState.power, int(GameState.power_cap), GameState.credits,
		GameState.reputation, GameState.score]

func _shop_pack_ids() -> Array[String]:
	var pack_ids: Array[String] = []
	for pack in RecipeDB.all_packs():
		if pack.shop_visible:
			pack_ids.append(pack.id)
	pack_ids.sort()
	return pack_ids

func _build_buttons() -> void:
	var view := _board.get_viewport_rect().size
	var end_day := Button.new()
	end_day.name = "EndDayButton"
	end_day.text = "End Day"
	end_day.size = Vector2(140, 48)
	end_day.position = Vector2(view.x - 156.0, view.y - 60.0)
	end_day.pressed.connect(DayCycle.end_day)
	add_child(end_day)

	# Tombol pack dijejer horizontal di kiri tombol End Day (kanan-bawah).
	# Teks tombol cuma nama pack; rincian biaya tampil saat hover (tooltip).
	var x := view.x - 156.0 - 10.0 - 300.0
	for pack_id in _shop_pack_ids():
		var pack := RecipeDB.get_pack(pack_id)
		var btn := Button.new()
		btn.name = "PackBtn_" + pack_id
		btn.text = pack.display_name
		btn.tooltip_text = Economy.pack_label(pack_id)
		btn.position = Vector2(x, view.y - 60.0)
		btn.size = Vector2(300, 48)
		btn.pressed.connect(_buy_pack.bind(pack_id))
		btn.mouse_entered.connect(_show_pack_info.bind(pack_id))
		btn.mouse_exited.connect(_hide_pack_info)
		add_child(btn)
		x -= 310.0

	_pack_info_label = Label.new()
	_pack_info_label.position = Vector2(view.x - 796.0, view.y - 100.0)
	_pack_info_label.size = Vector2(780, 30)
	_pack_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pack_info_label.add_theme_font_size_override("font_size", 16)
	_pack_info_label.add_theme_color_override("font_color", Color(0.7, 0.95, 1))
	_pack_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pack_info_label)

	var recipe_button := Button.new()
	recipe_button.name = "RecipeButton"
	recipe_button.text = "Resep"
	recipe_button.position = Vector2(8, view.y - 60.0)
	recipe_button.size = Vector2(140, 48)
	recipe_button.pressed.connect(_toggle_recipe_book)
	add_child(recipe_button)
	_build_recipe_book()

func _refresh_pack_buttons() -> void:
	for pack_id in _shop_pack_ids():
		var btn := get_node_or_null("PackBtn_" + pack_id) as Button
		if btn != null:
			btn.tooltip_text = Economy.pack_label(pack_id)
	if _hovered_pack_id != "" and _pack_info_label != null:
		_pack_info_label.text = Economy.pack_label(_hovered_pack_id)

func _buy_pack(pack_id: String) -> void:
	if Economy.buy_pack(pack_id):
		_refresh_pack_buttons()

# Info biaya pack: tampil di label di atas tombol saat cursor hover.
func _show_pack_info(pack_id: String) -> void:
	_hovered_pack_id = pack_id
	if _pack_info_label != null:
		_pack_info_label.text = Economy.pack_label(pack_id)

func _hide_pack_info() -> void:
	_hovered_pack_id = ""
	if _pack_info_label != null:
		_pack_info_label.text = ""

# ---------- Buku resep combo (tombol "Resep" kiri-bawah) ----------

func _toggle_recipe_book() -> void:
	if _recipe_panel != null:
		_recipe_panel.visible = not _recipe_panel.visible

func _build_recipe_book() -> void:
	var view := _board.get_viewport_rect().size
	_recipe_panel = UIFactory.panel(Vector2(minf(480.0, view.x * 0.4), view.y - 170.0),
		Color(0.09, 0.1, 0.15))
	_recipe_panel.name = "RecipeBook"
	_recipe_panel.position = Vector2(8, 90)
	_recipe_panel.visible = false
	add_child(_recipe_panel)

	var title := UIFactory.label("BUKU RESEP COMBO", 20, Color(0.9, 0.95, 1), HORIZONTAL_ALIGNMENT_LEFT)
	title.position = Vector2(16, 10)
	title.size = Vector2(300, 30)
	_recipe_panel.add_child(title)

	var close_button := UIFactory.button("Tutup", Vector2(100, 34))
	close_button.position = Vector2(_recipe_panel.size.x - 116.0, 8)
	close_button.pressed.connect(_toggle_recipe_book)
	_recipe_panel.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 52)
	scroll.size = Vector2(_recipe_panel.size.x - 16.0, _recipe_panel.size.y - 60.0)
	_recipe_panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	for line in _recipe_lines():
		var entry := UIFactory.label(line, 15, Color(0.9, 0.95, 1), HORIZONTAL_ALIGNMENT_LEFT)
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(entry)

func _card_short(card_id: String) -> String:
	var data: CardData = CardDB.get_card(card_id)
	return data.display_name if data != null else card_id

func _recipe_lines() -> Array[String]:
	var lines: Array[String] = []
	var recipes: Array = RecipeDB.all_recipes()
	recipes.sort_custom(func(a, b): return a.id < b.id)
	for recipe in recipes:
		var ins: Array[String] = []
		for req in recipe.inputs:
			ins.append("%s x%d" % [_card_short(String(req.get("item_id", "?"))), int(req.get("qty", 1))])
		var line := " + ".join(ins) + "  =  " + _card_short(recipe.output_id)
		if int(recipe.output_qty) > 1:
			line += " x%d" % int(recipe.output_qty)
		var gates: Array[String] = []
		if String(recipe.required_building_id) != "":
			gates.append("Gedung: " + _card_short(String(recipe.required_building_id)))
		if not recipe.required_any_structure_ids.is_empty():
			var names: Array[String] = []
			for id in recipe.required_any_structure_ids:
				names.append(_card_short(String(id)))
			gates.append("Perlu: " + " / ".join(names))
		if not recipe.required_any_worker_ids.is_empty():
			var names: Array[String] = []
			for id in recipe.required_any_worker_ids:
				names.append(_card_short(String(id)))
			gates.append("Pekerja: " + " / ".join(names))
		if not recipe.structure_target_ids.is_empty():
			var names: Array[String] = []
			for id in recipe.structure_target_ids:
				names.append(_card_short(String(id)))
			gates.append("Ke: " + " / ".join(names))
		if int(recipe.duration_days) > 0:
			gates.append("Produksi %d hari" % int(recipe.duration_days))
		if not gates.is_empty():
			line += "\n    " + ", ".join(gates)
		lines.append(line)
	return lines

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