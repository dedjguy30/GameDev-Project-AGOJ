extends Node

# A15 — Day Cycle. Autoload: DayCycle
# end_day() dipanggil tombol "End Day" di HUD.

const CANISTER_O2_RESTORE := 25.0
const DRONE_POWER_DRAW := 5.0
const BASE_POWER_CAP := 50.0

func end_day() -> void:
	if GameState.is_game_over:
		return
	var board: Board = get_tree().get_first_node_in_group(&"board")
	if board == null:
		return
	GameState.advance_day()
	var day := GameState.day
	# A16
	var consumption_mult: float = 1.0 + 0.02 * day

	# 1. (produksi building kini real-time di board._tick_production — A7)

	# 2. Auto-consume Food dari stock (A11/A14)
	var need_food := 0
	var need_oxygen := 0
	for unit in board.get_units():
		var ud := unit.card_data as UnitCardData
		if ud == null:
			continue
		if ud.needs_food:
			need_food += 1
		if ud.needs_oxygen:
			need_oxygen += 1
	var food_need: float = 4.0 * need_food * consumption_mult
	var eaten: float = _consume_food(board, food_need)
	var food_shortage: float = maxf(food_need - eaten, 0.0)

	# 3. Replenish O2 dari Oxygen Canister stock
	var o2_restore: float = _consume_canisters(board)

	# 4. Update stat utama (A14)
	var o2_consumption: float = 5.0 * need_oxygen * consumption_mult
	var o2_shortage: float = maxf(o2_consumption - o2_restore, 0.0)
	GameState.oxygen = clampf(GameState.oxygen - o2_shortage, 0.0, GameState.O2_MAX)
	GameState.food = clampf(GameState.food - food_shortage, 0.0, GameState.FOOD_MAX)
	if GameState.oxygen <= 0.0:
		GameState.days_without_oxygen += 1
	else:
		GameState.days_without_oxygen = 0
	if GameState.food <= 0.0:
		GameState.days_without_food += 1
	else:
		GameState.days_without_food = 0
	_resolve_power(board)

	# 5. Tether & O2_CUT (A1.2) — sebelum roll kematian
	_resolve_tether(board)

	# 6. Kematian / critical state (A14)
	_resolve_deaths(board)

	# 7. Package yang TRAVELING (A8)
	Packages.resolve_travel()

	# 8. Roll event (A9)
	Events.maybe_spawn_event()

	# 9. Efek sementara berkurang
	for key in GameState.active_effects.keys():
		GameState.active_effects[key] = int(GameState.active_effects[key]) - 1
		if int(GameState.active_effects[key]) <= 0:
			GameState.active_effects.erase(key)

	# 10. Cek Game Over
	_check_game_over()

	# 11. Skor (A16)
	GameState.update_score()
	GameState.stats_changed.emit()

# ---------- 2. Konsumsi food ----------

func _consume_food(board: Board, need: float) -> float:
	var eaten := 0.0
	for card_node in get_tree().get_nodes_in_group(&"cards"):
		if eaten >= need:
			break
		var card := card_node as Card
		if card == null or card.is_queued_for_deletion() or card.card_data == null:
			continue
		if card.card_data.category != Enums.CardCategory.ITEM_FOOD:
			continue
		var fd := card.card_data as ItemCardData
		var restore: float = fd.food_restore if fd != null else 0.0
		if restore <= 0.0:
			continue
		eaten += restore
		card.queue_free()
	return eaten

# ---------- 3. O2 canister ----------

func _consume_canisters(board: Board) -> float:
	var restored := 0.0
	for card in board.get_cards_of_id("item_oxygen_canister"):
		if GameState.oxygen >= GameState.O2_MAX:
			break
		restored += CANISTER_O2_RESTORE
		card.queue_free()
	return restored

# ---------- 4. Power (A11/A14) ----------

func _resolve_power(board: Board) -> void:
	var generated := 0.0
	var cap := BASE_POWER_CAP
	for building in board.get_built_buildings():
		var bd := building.card_data as BuildingCardData
		if bd == null:
			continue
		cap += bd.power_generated
		generated += bd.power_generated
	if int(GameState.active_effects.get("power_debuff", 0)) > 0:
		generated *= 0.5
	var consumption := 0.0
	for building in board.get_built_buildings():
		var bd := building.card_data as BuildingCardData
		if bd != null and not building.is_off:
			consumption += bd.power_draw
	for unit in board.get_units():
		var ud := unit.card_data as UnitCardData
		if ud != null and ud.role == Enums.UnitRole.ROBOT_DRONE \
				and (unit.assigned_node != null or unit.assigned_building != null):
			consumption += DRONE_POWER_DRAW
	GameState.power_cap = cap
	var net: float = GameState.power + generated - consumption
	if net < 0.0:
		var shutdown: Array[Card] = []
		for building in board.get_built_buildings():
			if building.is_off:
				continue
			var bd := building.card_data as BuildingCardData
			if bd == null or bd.passive_effect == "prevent_death" \
					or building.get_card_id() == "building_oxygen_generator":
				continue
			shutdown.append(building)
		shutdown.sort_custom(func(a: Card, b: Card) -> bool:
			var ad := a.card_data as BuildingCardData
			var bd2 := b.card_data as BuildingCardData
			return (ad.power_draw if ad != null else 0) > (bd2.power_draw if bd2 != null else 0))
		for building in shutdown:
			if net >= 0.0:
				break
			var bd := building.card_data as BuildingCardData
			building.is_off = true
			building.refresh()
			net += bd.power_draw if bd != null else 0.0
	# coba nyalakan lagi yang mati jika cukup power
	var reenable: Array[Card] = []
	for building in board.get_built_buildings():
		if building.is_off:
			reenable.append(building)
	reenable.sort_custom(func(a: Card, b: Card) -> bool:
		var ad := a.card_data as BuildingCardData
		var bd2 := b.card_data as BuildingCardData
		return (ad.power_draw if ad != null else 0) < (bd2.power_draw if bd2 != null else 0))
	for building in reenable:
		var bd := building.card_data as BuildingCardData
		var draw: float = bd.power_draw if bd != null else 0.0
		if net - draw >= 0.0:
			building.is_off = false
			building.refresh()
			net -= draw
	GameState.power = clampf(net, 0.0, GameState.power_cap)

# ---------- 5. Tether (A1.2) ----------

func _resolve_tether(board: Board) -> void:
	var station := board._find_tether_station()
	var station_powered: bool = station != null and not station.is_off
	for unit in board.get_units():
		var in_open: bool = board.open_rect.has_point(unit.global_position + unit.size * 0.5)
		if not in_open:
			unit.set_tether_status(Enums.TetherStatus.NORMAL)
			continue
		if unit.tank_days_left > 0:
			unit.tank_days_left -= 1
			unit.set_tether_status(Enums.TetherStatus.NORMAL if unit.tank_days_left > 0 else Enums.TetherStatus.O2_CUT)
			unit.refresh()
		elif unit.is_tethered:
			unit.set_tether_status(Enums.TetherStatus.NORMAL if station_powered else Enums.TetherStatus.O2_CUT)
		else:
			unit.set_tether_status(Enums.TetherStatus.O2_CUT)

# ---------- 6. Kematian (A14) ----------

func _resolve_deaths(board: Board) -> void:
	var med_bay_active := false
	for building in board.get_built_buildings():
		if building.get_card_id() == "building_med_bay" and not building.is_off:
			med_bay_active = true
			break
	var prevented := false
	for unit in board.get_units().duplicate():
		var roll := randf()
		var should_die := false
		if unit.tether_status == Enums.TetherStatus.O2_CUT:
			should_die = roll < 0.25
		elif GameState.oxygen <= 0.0:
			should_die = roll < 0.25
		if should_die:
			if med_bay_active and not prevented:
				prevented = true
				board._show_toast("Med Bay menyelamatkan 1 Unit", unit.global_position, Color(0.6, 0.9, 1))
				continue
			_kill_unit(board, unit, "O2 kritis")
	# Food nol 3 hari → 1 unit mati
	if GameState.days_without_food >= 3:
		var alive := board.get_units()
		if not alive.is_empty():
			var victim: Card = alive[randi() % alive.size()]
			if med_bay_active and not prevented:
				prevented = true
				board._show_toast("Med Bay menyelamatkan 1 Unit", victim.global_position, Color(0.6, 0.9, 1))
			else:
				_kill_unit(board, victim, "Kelaparan")

func _kill_unit(board: Board, unit: Card, reason: String) -> void:
	if unit == null or not is_instance_valid(unit) or unit.is_queued_for_deletion():
		return
	board._show_toast("%s meninggal (%s)" % [unit.card_data.display_name, reason],
		unit.global_position, Color(1, 0.45, 0.45))
	unit.set_unit_state(Enums.UnitState.DEAD)
	unit.set_gather_progress(-1.0)
	unit.queue_free()

# ---------- 10. Game over ----------

func _check_game_over() -> void:
	var board: Board = get_tree().get_first_node_in_group(&"board")
	if GameState.hull <= 0.0:
		GameState.end_game("Lambung kapal hancur")
	elif board != null and board.get_units().is_empty():
		GameState.end_game("Semua Unit meninggal")
	elif GameState.days_without_oxygen >= 5:
		GameState.end_game("O2 habis berkepanjangan")