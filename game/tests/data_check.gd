extends SceneTree

var _checked := false

func _process(_delta: float) -> bool:
	if _checked:
		return true
	_checked = true
	var errors := _run_checks()
	for e in errors:
		push_error(e)
	if errors.is_empty():
		print("DATA CHECK: OK")
		quit(0)
	else:
		print("DATA CHECK: FAIL - ", errors.size(), " error(s)")
		quit(1)
	return true

func _run_checks() -> Array[String]:
	var errors: Array[String] = []

	var card_db_script: Script = load("res://scripts/systems/card_db.gd")
	var recipe_db_script: Script = load("res://scripts/systems/recipe_db.gd")
	if card_db_script == null or recipe_db_script == null:
		return ["Gagal load script sistem (card_db / recipe_db)"]

	var card_db: Node = card_db_script.new()
	card_db.name = "CardDB"
	root.add_child(card_db)
	var recipe_db: Node = recipe_db_script.new()
	recipe_db.name = "RecipeDB"
	root.add_child(recipe_db)

	var card_count: int = card_db.get_count()
	if card_count <= 0:
		errors.append("CardDB kosong (0 kartu dimuat)")
		return errors

	var recipe_count: int = recipe_db.recipe_count()
	var sector_count: int = recipe_db.sector_count()
	var pack_count: int = recipe_db.pack_count()
	print("  kartu: ", card_count, " | resep: ", recipe_count, " | sektor: ", sector_count, " | pack: ", pack_count)

	# 1. Cek referensi kartu: semua id unik & terdaftar
	for card in card_db.get_all():
		var card_id: String = card.id
		if card_id == "":
			errors.append("Ada kartu tanpa id di CardDB")
		if card_db.get_card(card_id) != card:
			errors.append("Duplikat id kartu: " + card_id)

	# 2. Cek Node
	for node in card_db.get_nodes():
		if not card_db.has_card(node.output_item_id):
			errors.append("Node " + node.id + " → output tidak ada: " + node.output_item_id)
		if node.secondary_output_item_id != "" and not card_db.has_card(node.secondary_output_item_id):
			errors.append("Node " + node.id + " → secondary output tidak ada: " + node.secondary_output_item_id)
		if node.required_tool_id != "" and not card_db.has_card(node.required_tool_id):
			errors.append("Node " + node.id + " → required tool tidak ada: " + node.required_tool_id)

	# 3. Cek Item (output node harus item)
	for item in card_db.get_items():
		if item.item_type == null:
			errors.append("Item " + item.id + " tanpa item_type")

	# 4. Cek Building
	for building in card_db.get_buildings():
		for req in building.build_cost:
			if not card_db.has_card(req.get("item_id", "")):
				errors.append("Building " + building.id + " → build_cost item tidak ada: " + req.get("item_id", ""))
		var prod: Dictionary = building.production
		if not prod.is_empty():
			if prod.get("input_item_id", "") != "" and not card_db.has_card(prod.get("input_item_id", "")):
				errors.append("Building " + building.id + " → production input tidak ada: " + prod.get("input_item_id", ""))
			if not card_db.has_card(prod.get("output_item_id", "")):
				errors.append("Building " + building.id + " → production output tidak ada: " + prod.get("output_item_id", ""))

	# 5. Cek Recipe
	for recipe in recipe_db.all_recipes():
		if recipe.id == "":
			errors.append("Ada resep tanpa id")
		for req in recipe.inputs:
			if not card_db.has_card(req.get("item_id", "")):
				errors.append("Resep " + recipe.id + " → input tidak ada: " + req.get("item_id", ""))
		if not card_db.has_card(recipe.output_id):
			errors.append("Resep " + recipe.id + " → output tidak ada: " + recipe.output_id)
		if recipe.required_building_id != "" and not card_db.has_card(recipe.required_building_id):
			errors.append("Resep " + recipe.id + " → building prasyarat tidak ada: " + recipe.required_building_id)
		if recipe.required_unit_role < Enums.UnitRole.ANY or recipe.required_unit_role > Enums.UnitRole.ROBOT_DRONE:
			errors.append("Resep " + recipe.id + " → required_unit_role di luar enum: " + str(recipe.required_unit_role))
		var has_unit_input := false
		for req in recipe.inputs:
			var input_card: CardData = card_db.get_card(req.get("item_id", ""))
			if input_card != null and input_card.category == Enums.CardCategory.UNIT:
				has_unit_input = true
		if has_unit_input:
			var output_card: CardData = card_db.get_card(recipe.output_id)
			if output_card == null or output_card.category != Enums.CardCategory.UNIT:
				errors.append("Resep " + recipe.id + " → input Unit harus menghasilkan Unit (promosi role)")

	# 6. Cek Unit
	for unit in card_db.get_units():
		if unit.role < Enums.UnitRole.ANY or unit.role > Enums.UnitRole.ROBOT_DRONE:
			errors.append("Unit " + unit.id + " → role di luar enum: " + str(unit.role))
		for key in unit.role_efficiency_map:
			if not card_db.has_card(key):
				errors.append("Unit " + unit.id + " → efficiency map key tidak ada: " + key)

	# 7. Cek Package
	for pkg in card_db.get_packages():
		if recipe_db.get_sector(pkg.destination_sector_id) == null:
			errors.append("Package " + pkg.id + " → sektor tujuan tidak ada: " + pkg.destination_sector_id)
		for req in pkg.required_items:
			if not card_db.has_card(req.get("item_id", "")):
				errors.append("Package " + pkg.id + " → requirement item tidak ada: " + req.get("item_id", ""))

	# 8. Cek Event
	for event in card_db.get_events():
		for choice in event.choices:
			if choice.get("effect_code", "") == "grant_pack" and recipe_db.get_pack(choice.get("effect_value", "")) == null:
				errors.append("Event " + event.id + " → choice grant_pack tidak ada: " + choice.get("effect_value", ""))

	# 9. Cek Pack
	for pack in recipe_db.all_packs():
		if pack.drop_table.is_empty():
			errors.append("Pack " + pack.id + " → drop_table kosong")
		for entry in pack.drop_table:
			if not card_db.has_card(entry.card_id):
				errors.append("Pack " + pack.id + " → drop entry tidak ada: " + entry.card_id)

	# 10. Cek Sektor
	for sector in recipe_db.all_sectors():
		if sector.id == "":
			errors.append("Ada sektor tanpa id")

	return errors