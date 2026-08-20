class_name RecipeResolver
extends RefCounted

# A13 — manual combine instan (duration_days == 0).
# Cek dua arah; urutan kartu tidak penting.

static func find_recipe(card_a: Card, card_b: Card) -> CraftRecipe:
	if card_a == null or card_b == null or card_a.card_data == null or card_b.card_data == null:
		return null
	for recipe: CraftRecipe in RecipeDB.all_recipes():
		if recipe.duration_days > 0:
			continue
		var inputs: Array = recipe.inputs
		if inputs.size() == 2:
			if _matches(card_a, inputs[0]) and _matches(card_b, inputs[1]):
				return recipe
			if _matches(card_a, inputs[1]) and _matches(card_b, inputs[0]):
				return recipe
		elif inputs.size() == 1:
			# resep 1-input: material di-drag ke atas Unit (mis. Mining Drill: Scrap ×3 ke Engineer)
			var unit_card: Card = null
			if _matches(card_b, inputs[0]):
				unit_card = card_a
			elif _matches(card_a, inputs[0]):
				unit_card = card_b
			if unit_card != null and _is_unit(unit_card):
				if recipe.required_unit_role == Enums.UnitRole.ANY \
						or _unit_role(unit_card) == recipe.required_unit_role:
					return recipe
	return null

static func check_blocked(recipe: CraftRecipe, board: Board) -> String:
	if recipe.required_building_id != "" and not board.has_building(recipe.required_building_id):
		var building: CardData = CardDB.get_card(recipe.required_building_id)
		var name: String = building.display_name if building != null else recipe.required_building_id
		return "Butuh building: " + name
	if recipe.required_unit_role != Enums.UnitRole.ANY and not board.has_unit_role(recipe.required_unit_role):
		return "Butuh Unit role: " + role_name(recipe.required_unit_role)
	return ""

static func execute(recipe: CraftRecipe, card_a: Card, card_b: Card, board: Board, drop_position: Vector2) -> void:
	for req in recipe.inputs:
		var item_id: String = req.get("item_id", "")
		var qty: int = int(req.get("qty", 1))
		var source: Card = null
		if card_a.card_data != null and card_a.card_data.id == item_id:
			source = card_a
		elif card_b.card_data != null and card_b.card_data.id == item_id:
			source = card_b
		if source == null:
			continue
		source.set_stack_count(source.stack_count - qty)
		if source.stack_count <= 0:
			source.queue_free()
	board.spawn_card_at(recipe.output_id, drop_position, recipe.output_qty)

static func role_name(role: int) -> String:
	for key: String in Enums.UnitRole.keys():
		if Enums.UnitRole[key] == role:
			return key
	return str(role)

static func _matches(card: Card, req: Dictionary) -> bool:
	return card.card_data != null \
		and card.card_data.id == req.get("item_id", "") \
		and card.stack_count >= int(req.get("qty", 1))

static func _is_unit(card: Card) -> bool:
	return card.card_data != null and card.card_data.category == Enums.CardCategory.UNIT

static func _unit_role(card: Card) -> int:
	var unit_data := card.card_data as UnitCardData
	return unit_data.role if unit_data != null else Enums.UnitRole.ANY