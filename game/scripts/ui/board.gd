class_name Board
extends Control

const CARD_SCENE := preload("res://scenes/card.tscn")

var ship_rect := Rect2()
var open_rect := Rect2()

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	add_to_group(&"board")
	_build_zones()
	_spawn_test_cards()
	_show_data_debug()
	_spawn_hud()

func _process(delta: float) -> void:
	_tick_gather(delta)
	_tick_production(delta)

func _build_zones() -> void:
	var viewport_size := get_viewport_rect().size
	var divider_x: float = viewport_size.x * 0.45
	ship_rect = Rect2(0, 0, divider_x, viewport_size.y)
	open_rect = Rect2(divider_x, 0, viewport_size.x - divider_x, viewport_size.y)

	var ship_bg := ColorRect.new()
	ship_bg.color = Color(0.13, 0.16, 0.2)
	ship_bg.position = ship_rect.position
	ship_bg.size = ship_rect.size
	ship_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ship_bg)

	var open_bg := ColorRect.new()
	open_bg.color = Color(0.07, 0.08, 0.13)
	open_bg.position = open_rect.position
	open_bg.size = open_rect.size
	open_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(open_bg)

	var divider := ColorRect.new()
	divider.color = Color(0.4, 0.5, 0.7, 0.6)
	divider.position = Vector2(divider_x - 2, 0)
	divider.size = Vector2(4, viewport_size.y)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)

	_add_zone_label("ZONA KAPAL  (SHIP INTERIOR)", Vector2(16, 8), Color(0.7, 0.85, 1))
	_add_zone_label("ZONA ANGKASA  (OPEN SPACE)", Vector2(divider_x + 16, 8), Color(1, 0.8, 0.6))

func _add_zone_label(text: String, position: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

func get_zone(pos: Vector2) -> Enums.BoardZone:
	if ship_rect.has_point(pos):
		return Enums.BoardZone.SHIP_INTERIOR
	return Enums.BoardZone.OPEN_SPACE

# ---------- Validasi drop (A1.2, A2) ----------

func validate_drop(card: Card) -> bool:
	var zone := get_zone(card.global_position + card.size * 0.5)
	match card.card_data.category:
		Enums.CardCategory.BUILDING:
			return zone == Enums.BoardZone.SHIP_INTERIOR
		Enums.CardCategory.NODE:
			return zone == Enums.BoardZone.OPEN_SPACE
		Enums.CardCategory.PACKAGE:
			return zone == Enums.BoardZone.SHIP_INTERIOR
		Enums.CardCategory.UNIT:
			if zone == Enums.BoardZone.SHIP_INTERIOR:
				# kembali ke kapal → lepas tether
				if card.is_tethered or card.tether_status != Enums.TetherStatus.NORMAL:
					card.set_tethered(false)
					card.set_tether_status(Enums.TetherStatus.NORMAL)
				return true
			# drop ke Zona Angkasa → butuh slot tether atau portable tank (A1.2)
			if card.tank_days_left > 0:
				return true
			var station := _find_tether_station()
			if station == null:
				_show_toast("Butuh O2 Umbilical Station atau Portable O2 Tank",
					card.global_position, Color(1, 0.6, 0.55))
				return false
			var tethered_count := 0
			for card_node in get_tree().get_nodes_in_group(&"cards"):
				var other := card_node as Card
				if other != null and other.is_unit() and other.is_tethered:
					tethered_count += 1
			var station_data := station.card_data as BuildingCardData
			var max_connections: int = station_data.max_connections if station_data != null else 2
			if tethered_count >= max_connections:
				_show_toast("Slot tether penuh (%d)" % max_connections,
					card.global_position, Color(1, 0.6, 0.55))
				return false
			return true
		_:
			return true

func _find_tether_station() -> Card:
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.is_building() and card.is_built and card.get_card_id() == "building_o2_umbilical_station":
			return card
	return null

# ---------- Routing drop (A5/A6/A7/A8/A10/A13) ----------

func _on_card_dropped(card: Card, position: Vector2) -> void:
	var target: Card = _card_at(position, card)

	# A7: Building → bayar build_cost (A5)
	if card.is_building():
		if card.is_built:
			return
		if not _try_build(card):
			card.global_position = card._pre_drag_position
		return

	# A6: Tool → Unit (equip / consumable)
	if card.is_tool() and target != null and target.is_unit():
		_try_equip_tool(card, target)
		return

	# A7: Unit → Building (assign kerja)
	if card.is_unit() and target != null and target.is_building():
		_try_assign_building(card, target)
		return

	# A3: Unit → Node
	if card.is_unit() and target != null and target.is_node():
		_try_assign(card, target)
		return

	# A8: Unit → Package (depart jika lengkap)
	if card.is_unit() and target != null and target.is_package():
		Packages.try_depart(self, card, target)
		return

	# A8: Item → Package (assembly)
	if card.card_data.category == Enums.CardCategory.ITEM_RAW \
			or card.card_data.category == Enums.CardCategory.ITEM_PROCESSED:
		if target != null and target.is_package():
			Packages.try_assemble(self, card, target)
			return

	# A10: Item → Trade Post (jual)
	if card.card_data.category == Enums.CardCategory.ITEM_RAW \
			or card.card_data.category == Enums.CardCategory.ITEM_PROCESSED \
			or card.card_data.category == Enums.CardCategory.ITEM_FOOD \
			or card.card_data.category == Enums.CardCategory.TOOL:
		if target != null and target.is_building() and target.is_built \
				and target.get_card_id() == "building_trade_post":
			Economy.try_sell(self, card)
			return

	if card.is_unit():
		card.unassign()
		card.unassign_from_building()
		# A1.2: unit di Zona Angkasa harus ter-tether (sudah divalidasi validate_drop)
		if get_zone(card.global_position + card.size * 0.5) == Enums.BoardZone.OPEN_SPACE:
			card.set_tethered(card.tank_days_left <= 0)

	# A13: combine manual
	var recipe := RecipeResolver.find_recipe(card, target)
	if recipe == null:
		return
	var blocked: String = RecipeResolver.check_blocked(recipe, self)
	if blocked != "":
		_show_toast(blocked, position, Color(1, 0.6, 0.55))
		return
	RecipeResolver.execute(recipe, card, target, self, position)
	var output: CardData = CardDB.get_card(recipe.output_id)
	var output_name: String = output.display_name if output != null else recipe.output_id
	_show_toast("+ " + output_name, position, Color(0.55, 1, 0.6))

# ---------- A6: equip tool ----------

func _try_equip_tool(tool_card: Card, unit: Card) -> void:
	var tool_data := tool_card.card_data as ToolCardData
	if tool_data == null:
		return
	if tool_data.is_consumable:
		# consumable: langsung pakai efeknya, kartu tool hilang
		Economy.apply_tool_effect(tool_card.get_card_id(), self)
		tool_card.queue_free()
		return
	if unit.has_equipped_tool(tool_card.get_card_id()):
		_show_toast("Sudah ter-equip", tool_card.global_position, Color(1, 0.8, 0.5))
		return
	unit.equip_tool(tool_card.get_card_id())
	if tool_data.tank_duration_days > 0:
		unit.tank_days_left = tool_data.tank_duration_days
	tool_card.queue_free()
	var tool_name: String = tool_data.display_name
	_show_toast("Equip: " + tool_name, unit.global_position, Color(0.55, 1, 0.6))

# ---------- A7: assign unit ke building ----------

func _try_assign_building(unit_card: Card, building_card: Card) -> void:
	if not building_card.is_built:
		_show_toast("Bangunan belum dibangun!", unit_card.global_position, Color(1, 0.6, 0.55))
		return
	if building_card.is_off:
		_show_toast("Bangunan mati (kurang power)", unit_card.global_position, Color(1, 0.6, 0.55))
		return
	var building_data := building_card.card_data as BuildingCardData
	if building_data != null and building_data.max_unit_slots > 0:
		var used := 0
		for card_node in get_tree().get_nodes_in_group(&"cards"):
			var other := card_node as Card
			if other != null and other.is_unit() and other.assigned_building == building_card:
				used += 1
		if used >= building_data.max_unit_slots:
			_show_toast("Slot unit building penuh", unit_card.global_position, Color(1, 0.6, 0.55))
			return
	if unit_card.assigned_node != null:
		unit_card.unassign()
	unit_card.assign_to_building(building_card)
	_show_toast("WORKING: " + building_card.card_data.display_name,
		unit_card.global_position, Color(0.55, 1, 0.6))

# ---------- A3: gather ----------

func _try_assign(unit_card: Card, node_card: Card) -> void:
	var node_data := node_card.card_data as NodeCardData
	if node_data == null:
		return
	if node_data.required_tool_id != "" and not unit_card.has_equipped_tool(node_data.required_tool_id):
		var tool: CardData = CardDB.get_card(node_data.required_tool_id)
		var tool_name: String = tool.display_name if tool != null else node_data.required_tool_id
		_show_toast("Butuh tool: " + tool_name, unit_card.global_position, Color(1, 0.6, 0.55))
		return
	if unit_card.assigned_building != null:
		unit_card.unassign_from_building()
	unit_card.assign_to_node(node_card)
	if node_card.is_tethered == false and unit_card.is_tethered == false and unit_card.tank_days_left <= 0 \
			and get_zone(node_card.global_position + node_card.size * 0.5) == Enums.BoardZone.OPEN_SPACE:
		unit_card.set_tethered(true)
	_show_toast("Gathering: " + node_card.card_data.display_name,
		unit_card.global_position, Color(0.55, 1, 0.6))

func has_tool(tool_id: String) -> bool:
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.card_data.category == Enums.CardCategory.TOOL and card.get_card_id() == tool_id:
			return true
	return false

func _tick_gather(delta: float) -> void:
	for node in get_tree().get_nodes_in_group(&"cards"):
		var unit := node as Card
		if unit == null or unit.is_queued_for_deletion():
			continue
		if unit.assigned_node == null:
			continue
		if unit.assigned_node.is_queued_for_deletion():
			unit.unassign()
			continue
		var node_data := unit.assigned_node.card_data as NodeCardData
		if node_data == null:
			unit.unassign()
			continue
		var interval: float = node_data.gather_interval_sec / _unit_efficiency(unit, unit.assigned_node)
		unit._gather_timer += delta
		unit.set_gather_progress(unit._gather_timer / interval)
		if unit._gather_timer >= interval:
			unit._gather_timer = 0.0
			_harvest(unit, unit.assigned_node, node_data)
			unit.set_gather_progress(0.0)

func _unit_efficiency(unit: Card, node: Card) -> float:
	var unit_data := unit.card_data as UnitCardData
	if unit_data == null:
		return 1.0
	var eff: float = float(unit_data.role_efficiency_map.get(node.get_card_id(), 1.0))
	# A6: Mining Drill → gather di Asteroid Field 2× lebih cepat
	var drill := CardDB.get_card("tool_mining_drill") as ToolCardData
	if unit.has_equipped_tool("tool_mining_drill") and node.get_card_id() == "node_asteroid_field" \
			and drill != null:
		eff *= drill.effect_value
	return eff

# ---------- A7: produksi building real-time ----------

const PRODUCTION_SECONDS_PER_DAY := 10.0

func _tick_production(delta: float) -> void:
	for building in get_built_buildings():
		var bd := building.card_data as BuildingCardData
		if bd == null or bd.production.is_empty():
			continue
		if building.is_off:
			continue
		var prod: Dictionary = bd.production
		var in_id: String = prod.get("input_item_id", "")
		var in_qty: int = int(prod.get("input_qty", 1))
		if in_id != "" and count_item(in_id) < in_qty:
			continue
		var workers: Array[Card] = []
		for unit in get_units():
			if unit.assigned_building == building:
				workers.append(unit)
		if workers.is_empty():
			continue
		var interval: float = float(int(prod.get("interval_days", 1))) * PRODUCTION_SECONDS_PER_DAY
		building.production_timer += delta
		var progress: float = building.production_timer / interval
		for worker in workers:
			worker.set_gather_progress(progress)
		if building.production_timer < interval:
			continue
		building.production_timer = 0.0
		if in_id != "":
			consume_item(in_id, in_qty)
		var out_id: String = prod.get("output_item_id", "")
		var out_qty: int = int(prod.get("output_qty", 1))
		if out_id != "":
			spawn_card_at(out_id, building.global_position + Vector2(0.0, building.size.y + 30.0), out_qty)
			var out_data: CardData = CardDB.get_card(out_id)
			_show_toast("+ %s x%d" % [out_data.display_name if out_data != null else out_id, out_qty],
				building.global_position + Vector2(0.0, 30.0), Color(0.55, 1, 0.6))
		for worker in workers:
			worker.set_gather_progress(0.0)

func _harvest(unit: Card, node: Card, node_data: NodeCardData) -> void:
	var item_id: String = node_data.output_item_id
	if node_data.secondary_output_item_id != "" \
			and _rng.randf() < node_data.secondary_chance:
		item_id = node_data.secondary_output_item_id
	_spawn_nearby(item_id, node, node_data.output_qty)
	if node_data.is_limited:
		node.node_durability_left -= 1
		node.refresh()
		if node.node_durability_left <= 0:
			_deplete_node(node)

func _deplete_node(node: Card) -> void:
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and card.assigned_node == node:
			card.unassign()
	node.queue_free()

func _spawn_nearby(item_id: String, node: Card, count: int) -> void:
	var candidate_positions: Array[Vector2] = [
		node.global_position + Vector2(-98.0, 15.0),
		node.global_position + Vector2(node.size.x + 8.0, 15.0),
		node.global_position + Vector2(15.0, -143.0),
		node.global_position + Vector2(15.0, node.size.y + 8.0),
		node.global_position + Vector2(-98.0, node.size.y + 8.0),
		node.global_position + Vector2(node.size.x + 8.0, node.size.y + 8.0),
		node.global_position + Vector2(-98.0, -143.0),
		node.global_position + Vector2(node.size.x + 8.0, -143.0),
	]
	for pos in candidate_positions:
		if _is_slot_free(pos):
			spawn_card_at(item_id, pos + Vector2(45.0, 64.0), count)
			return
	spawn_card_at(item_id, node.global_position + Vector2(node.size.x * 0.5, -45.0), count)

func _is_slot_free(position: Vector2) -> bool:
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.get_global_rect().grow(10.0).has_point(position):
			return false
	return true

func _card_at(position: Vector2, exclude: Card) -> Card:
	var best: Card = null
	for node in get_tree().get_nodes_in_group(&"cards"):
		var candidate: Card = node as Card
		if candidate == null or candidate == exclude or candidate.is_queued_for_deletion():
			continue
		if candidate.card_data == null:
			continue
		if not candidate.get_global_rect().grow(6.0).has_point(position):
			continue
		if best == null or candidate.z_index >= best.z_index:
			best = candidate
	return best

func has_building(building_id: String) -> bool:
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.card_data.category == Enums.CardCategory.BUILDING and card.get_card_id() == building_id:
			return true
	return false

func has_unit_role(role: int) -> bool:
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.card_data.category != Enums.CardCategory.UNIT:
			continue
		var unit_data := card.card_data as UnitCardData
		if unit_data != null and unit_data.role == role:
			return true
	return false

func _show_toast(text: String, position: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", position.y - 44.0, 1.1)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.1)
	tween.tween_callback(label.queue_free)

# ---------- A7: build cost ----------

func _try_build(building_card: Card) -> bool:
	var building_data := building_card.card_data as BuildingCardData
	if building_data == null:
		return false
	var missing: Array[String] = []
	var cost: Array = building_data.build_cost
	for req in cost:
		var item_id: String = req.get("item_id", "")
		var qty: int = int(req.get("qty", 1))
		var have: int = count_item(item_id)
		if have < qty:
			var item: CardData = CardDB.get_card(item_id)
			missing.append("%s x%d" % [item.display_name if item != null else item_id, qty - have])
	if not missing.is_empty():
		_show_toast("Butuh: " + ", ".join(missing), building_card.global_position, Color(1, 0.6, 0.55))
		return false
	for req in cost:
		consume_item(req.get("item_id", ""), int(req.get("qty", 1)))
	building_card.is_built = true
	building_card.is_off = false
	building_card.refresh()
	_show_toast("Dibangun: " + building_card.card_data.display_name,
		building_card.global_position, Color(0.55, 1, 0.6))
	return true

# ---------- Helper untuk sistem lain (DayCycle/Economy/Packages) ----------

func count_item(item_id: String) -> int:
	var total := 0
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.get_card_id() == item_id:
			total += card.stack_count
	return total

func consume_item(item_id: String, qty: int) -> int:
	var remaining := qty
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if remaining <= 0:
			break
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.get_card_id() != item_id:
			continue
		var take: int = mini(remaining, card.stack_count)
		card.set_stack_count(card.stack_count - take)
		remaining -= take
		if card.stack_count <= 0:
			card.queue_free()
	return qty - remaining

func get_units() -> Array[Card]:
	var result: Array[Card] = []
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and not card.is_queued_for_deletion() and card.is_unit():
			result.append(card)
	return result

func get_built_buildings() -> Array[Card]:
	var result: Array[Card] = []
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.is_building() and card.is_built:
			result.append(card)
	return result

func get_cards_of_id(card_id: String) -> Array[Card]:
	var result: Array[Card] = []
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		var card := card_node as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			result.append(card)
	return result

func find_first(card_id: String) -> Card:
	var cards := get_cards_of_id(card_id)
	return cards[0] if not cards.is_empty() else null

func random_free_spot(zone: Enums.BoardZone) -> Vector2:
	for i in 40:
		var rect := ship_rect if zone == Enums.BoardZone.SHIP_INTERIOR else open_rect
		var pos := Vector2(
			rect.position.x + _rng.randf_range(20.0, rect.size.x - 180.0),
			rect.position.y + _rng.randf_range(40.0, rect.size.y - 240.0))
		if _is_slot_free(pos):
			return pos + Vector2(60.0, 85.0)
	return ship_rect.position + Vector2(200, 400)

func remove_card(card: Card) -> void:
	card.queue_free()

# ---------- Spawn ----------

func spawn_card_at(card_id: String, position: Vector2, count := 1, built := false) -> Card:
	var card := _instantiate_card(card_id, count, built)
	if card == null:
		return null
	add_child(card)
	card.global_position = position - card.size * 0.5
	return card

func _instantiate_card(card_id: String, count := 1, built := false) -> Card:
	var card_data: CardData = CardDB.get_card(card_id)
	if card_data == null:
		push_warning("Board: spawn gagal, id tidak ada di CardDB: " + card_id)
		return null
	var card: Card = CARD_SCENE.instantiate()
	card.setup_card(card_data, count, built)
	card.dropped.connect(_on_card_dropped)
	card.clicked.connect(_on_card_clicked)
	return card

func _spawn_card(card_id: String, position: Vector2, count := 1, built := false) -> Card:
	var card := _instantiate_card(card_id, count, built)
	if card == null:
		return null
	add_child(card)
	card.global_position = position
	return card

func _on_card_clicked(card: Card) -> void:
	Events.on_card_clicked(self, card)

func _spawn_test_cards() -> void:
	_spawn_card("node_asteroid_field", open_rect.position + Vector2(80, 160))
	_spawn_card("node_debris_field", open_rect.position + Vector2(300, 340))
	_spawn_card("node_ice_field", open_rect.position + Vector2(80, 460))
	_spawn_card("node_gas_cloud", open_rect.position + Vector2(300, 120))
	_spawn_card("tool_cutting_laser", open_rect.position + Vector2(520, 160))

	# Kolom 1: unit & building
	_spawn_card("unit_astronaut", Vector2(60, 120))
	_spawn_card("unit_astronaut", Vector2(60, 290))
	_spawn_card("unit_engineer", Vector2(60, 460))
	_spawn_card("building_workshop", Vector2(60, 630), 1, true)
	_spawn_card("building_solar_panel", Vector2(60, 800), 1, true)

	# Kolom 2: material combine
	_spawn_card("item_ice_chunk", Vector2(230, 120))
	_spawn_card("tool_heat_source", Vector2(230, 290))
	_spawn_card("item_scrap_metal", Vector2(230, 460), 3)
	_spawn_card("item_crystal_ore", Vector2(230, 630))
	_spawn_card("item_circuit_board", Vector2(230, 800), 2)

	# Kolom 3: material combine lanjutan
	_spawn_card("item_alien_flora", Vector2(400, 120))
	_spawn_card("item_fuel_cell", Vector2(400, 290), 2)
	_spawn_card("item_scrap_metal", Vector2(400, 460), 2)
	_spawn_card("tool_welding_torch", Vector2(400, 630))
	_spawn_card("item_fuel_cell", Vector2(400, 800))

	# Kolom 4: material combine + demo stacking
	_spawn_card("item_scrap_metal", Vector2(570, 120), 3)
	_spawn_card("item_metal_ingot", Vector2(570, 290))
	_spawn_card("item_water", Vector2(570, 460), 2)
	_spawn_card("item_water", Vector2(570, 630))
	_spawn_card("tool_processor", Vector2(570, 800))

	# Kolom 5: sistem baru (Phase 5-12)
	_spawn_card("building_hydroponics_bay", Vector2(740, 120), 1, false)
	_spawn_card("building_o2_umbilical_station", Vector2(740, 290), 1, true)
	_spawn_card("pkg_scrap_run", Vector2(740, 460))
	_spawn_card("tool_repair_kit", Vector2(740, 630))
	_spawn_card("item_metal_ingot", Vector2(740, 800), 3)
	_spawn_card("building_trade_post", Vector2(740, 950), 1, true)

	# Zona angkasa: pendukung sistem
	_spawn_card("item_protein_paste", open_rect.position + Vector2(440, 620), 2)
	_spawn_card("item_oxygen_canister", open_rect.position + Vector2(440, 800), 2)

func _show_data_debug() -> void:
	var label := Label.new()
	label.name = "DataDebugLabel"
	label.position = Vector2(8, 1045)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	label.text = "CardDB: %d kartu | %d resep | %d sektor | %d pack" % [
		CardDB.get_count(),
		RecipeDB.recipe_count(),
		RecipeDB.sector_count(),
		RecipeDB.pack_count(),
	]
	add_child(label)

func _spawn_hud() -> void:
	var hud: HUD = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.setup(self)