extends Node

# A8 — Package & Sektor. Autoload: Packages

var traveling: Array[Dictionary] = []

# Drag item ke package → kunci requirement (konsumsi item, progres "x/y")
func try_assemble(board: Board, item_card: Card, package_card: Card) -> void:
	var pkg_data := package_card.card_data as PackageCardData
	if pkg_data == null:
		return
	var matched: Dictionary = {}
	for req in pkg_data.required_items:
		if req.get("item_id", "") == item_card.get_card_id() \
				and int(package_card.assembled_items.get(req.get("item_id"), 0)) < int(req.get("qty", 1)):
			matched = req
			break
	if matched.is_empty():
		board._show_toast("Barang tidak dibutuhkan", item_card.global_position, Color(1, 0.8, 0.5))
		return
	var need: int = int(matched.get("qty", 1)) - int(package_card.assembled_items.get(matched.get("item_id", ""), 0))
	var take: int = mini(need, item_card.stack_count)
	package_card.assembled_items[matched.get("item_id", "")] = int(package_card.assembled_items.get(matched.get("item_id", ""), 0)) + take
	item_card.set_stack_count(item_card.stack_count - take)
	if item_card.stack_count <= 0:
		item_card.queue_free()
	package_card.refresh()
	if package_card.is_package_complete():
		board._show_toast("Package lengkap! Drop Unit untuk berangkat",
			package_card.global_position, Color(0.55, 1, 0.6))

# Drop unit ke package lengkap → berangkat (TRAVELING)
func try_depart(board: Board, unit: Card, package_card: Card) -> void:
	if not package_card.is_package_complete():
		board._show_toast("Package belum lengkap", unit.global_position, Color(1, 0.8, 0.5))
		return
	if unit.assigned_node != null or unit.assigned_building != null:
		board._show_toast("Unit sedang bekerja", unit.global_position, Color(1, 0.8, 0.5))
		return
	var pkg_data := package_card.card_data as PackageCardData
	var sector := RecipeDB.get_sector(pkg_data.destination_sector_id)
	if sector == null:
		push_warning("Packages: sektor tidak ada: " + pkg_data.destination_sector_id)
		return
	if GameState.reputation < sector.rep_required:
		board._show_toast("Sektor terkunci (butuh Rep %d)" % sector.rep_required,
			unit.global_position, Color(1, 0.6, 0.55))
		return
	var travel_days := sector.base_distance_days
	if unit.card_data is UnitCardData:
		var ud := unit.card_data as UnitCardData
		if ud.role == Enums.UnitRole.PILOT:
			travel_days = maxi(1, travel_days - 1)
	traveling.append({
		"unit": unit,
		"package": package_card,
		"days_left": travel_days,
		"reward_credits": pkg_data.reward_credits,
		"reward_rep": pkg_data.reward_rep,
	})
	unit.set_unit_state(Enums.UnitState.TRAVELING)
	unit.visible = false
	package_card.queue_free()
	board._show_toast("Paket berangkat! (%d hari)" % travel_days,
		unit.global_position, Color(0.7, 0.95, 1))

# End Day: kurangi sisa hari; selesai → reward (A8 formula + A16 multiplier)
func resolve_travel() -> void:
	var done: Array[Dictionary] = []
	for entry in traveling:
		entry["days_left"] = int(entry["days_left"]) - 1
		if int(entry["days_left"]) > 0:
			continue
		done.append(entry)
	for entry in done:
		traveling.erase(entry)
		var unit: Card = entry.get("unit")
		var mult: float = 1.0 + 0.01 * GameState.day
		var credits: int = int(round(float(entry.get("reward_credits", 0)) * mult))
		var rep: int = int(round(float(entry.get("reward_rep", 0)) * mult))
		GameState.add_credits(credits)
		GameState.add_reputation(rep)
		GameState.total_packages_delivered += 1
		GameState.update_score()
		var board: Board = get_tree().get_first_node_in_group(&"board")
		if is_instance_valid(unit) and board != null:
			unit.set_unit_state(Enums.UnitState.IDLE)
			unit.visible = true
			unit.global_position = board.random_free_spot(Enums.BoardZone.SHIP_INTERIOR) - unit.size * 0.5
			board._show_toast("Paket terkirim! +%d cr +%d rep" % [credits, rep],
				unit.global_position, Color(0.55, 1, 0.6))