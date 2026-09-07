class_name RecipeResolver
extends RefCounted

# A13 — manual combine instan (duration_days == 0).
# Mendukung 3 pola combine sesuai GDD & Combining Recipe:
#   1) 2-input langsung (item + item, urutan bebas)                  → Water+Water=Oxygen Tank, dst.
#   2) 1-input ke target (Unit dgn role tertentu, ATAU Structure      → Iron Ore ke Furnace/Little Furnace
#      spesifik lewat structure_target_ids)
#   3) 3-input "pool": dua kartu yg di-drag/drop harus masing2 cocok  → Energy Cell+Space Rock+Iron
#      dgn salah satu input resep, sisanya dicari di kartu longgar     = Little Helper
#      di sekitar titik drop (POOL_RADIUS)
#
# Syarat tambahan (butuh Building/Worker tertentu di board, tapi tidak
# harus jadi target drop-nya) dicek terpisah lewat check_blocked().

const POOL_RADIUS := 90.0

static func find_recipe(card_a: Card, card_b: Card, board: Board = null) -> CraftRecipe:
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
			var source: Card = null
			var target: Card = null
			if _matches(card_a, inputs[0]):
				source = card_a
				target = card_b
			elif _matches(card_b, inputs[0]):
				source = card_b
				target = card_a
			if source == null:
				continue
			if not recipe.structure_target_ids.is_empty():
				# combine ke Structure: target harus salah satu id di list,
				# dan kalau Building harus sudah is_built.
				if target.card_data != null and recipe.structure_target_ids.has(target.card_data.id) \
						and (not target.is_building() or target.is_built):
					return recipe
			elif _is_unit(target):
				# resep 1-input lama: material di-drag ke atas Unit (mis. Mining Drill)
				if recipe.required_unit_role == Enums.UnitRole.ANY \
						or _unit_role(target) == recipe.required_unit_role:
					return recipe
		elif inputs.size() >= 3:
			if _matches_pool(recipe, card_a, card_b, board):
				return recipe
	return null

static func check_blocked(recipe: CraftRecipe, board: Board) -> String:
	if recipe.required_building_id != "" and not board.has_building(recipe.required_building_id):
		var building: CardData = CardDB.get_card(recipe.required_building_id)
		var name: String = building.display_name if building != null else recipe.required_building_id
		return "Butuh building: " + name
	if not recipe.required_any_structure_ids.is_empty() \
			and not _has_any(board, recipe.required_any_structure_ids):
		return "Butuh: " + _names_join(recipe.required_any_structure_ids)
	if recipe.required_unit_role != Enums.UnitRole.ANY and not board.has_unit_role(recipe.required_unit_role):
		return "Butuh Unit role: " + role_name(recipe.required_unit_role)
	if not recipe.required_any_worker_ids.is_empty() \
			and not _has_any(board, recipe.required_any_worker_ids):
		return "Butuh: " + _names_join(recipe.required_any_worker_ids)
	return ""

static func execute(recipe: CraftRecipe, card_a: Card, card_b: Card, board: Board, drop_position: Vector2) -> void:
	var candidates: Array[Card] = _gather_candidates(recipe, card_a, card_b, board)

	# Tentukan titik spawn SEBELUM konsumsi (anchor bisa saja habis/queue_free).
	var spawn_position := drop_position
	if not recipe.pool_anchor_ids.is_empty():
		for c in candidates:
			if c != null and c.card_data != null and recipe.pool_anchor_ids.has(c.card_data.id):
				spawn_position = c.global_position
				break

	for req in recipe.inputs:
		var item_id: String = req.get("item_id", "")
		var qty: int = int(req.get("qty", 1))
		var remaining := qty
		for source in candidates:
			if remaining <= 0:
				break
			if source == null or source.is_queued_for_deletion() or source.card_data == null:
				continue
			if source.card_data.id != item_id:
				continue
			var take: int = mini(remaining, source.stack_count)
			source.set_stack_count(source.stack_count - take)
			remaining -= take
			if source.stack_count <= 0:
				source.queue_free()

	board.spawn_card_at(recipe.output_id, spawn_position, recipe.output_qty)

static func role_name(role: int) -> String:
	for key: String in Enums.UnitRole.keys():
		if Enums.UnitRole[key] == role:
			return key
	return str(role)

# ---------- internal ----------

static func _matches(card: Card, req: Dictionary) -> bool:
	return card.card_data != null \
		and card.card_data.id == req.get("item_id", "") \
		and card.stack_count >= int(req.get("qty", 1))

static func _is_unit(card: Card) -> bool:
	return card.card_data != null and card.card_data.category == Enums.CardCategory.UNIT

static func _unit_role(card: Card) -> int:
	var unit_data := card.card_data as UnitCardData
	return unit_data.role if unit_data != null else Enums.UnitRole.ANY

static func _has_any(board: Board, ids: Array) -> bool:
	for id in ids:
		if board.has_card_id(String(id), true):
			return true
	return false

static func _names_join(ids: Array) -> String:
	var names: Array[String] = []
	for id in ids:
		var data: CardData = CardDB.get_card(String(id))
		names.append(data.display_name if data != null else String(id))
	return " / ".join(names)

# Kumpulkan kandidat kartu untuk resep 3+ input: kartu yg lagi di-drag/drop
# ditambah kartu longgar lain yang overlap di sekitarnya (POOL_RADIUS).
static func _gather_candidates(recipe: CraftRecipe, card_a: Card, card_b: Card, board: Board) -> Array[Card]:
	var candidates: Array[Card] = [card_a, card_b]
	if recipe.inputs.size() >= 3 and board != null:
		for c in board.get_cards_near(card_a.global_position, POOL_RADIUS):
			if not candidates.has(c):
				candidates.append(c)
		for c in board.get_cards_near(card_b.global_position, POOL_RADIUS):
			if not candidates.has(c):
				candidates.append(c)
	return candidates

# card_a dan card_b (kartu yg benar2 di-drag/drop) masing2 WAJIB cocok dengan
# salah satu input resep (biar combine tidak ke-trigger cuma krn kartu numpuk
# di dekat situ). Sisa kebutuhan qty dicari di seluruh pool kandidat.
static func _matches_pool(recipe: CraftRecipe, card_a: Card, card_b: Card, board: Board) -> bool:
	if board == null:
		return false
	var a_matches := false
	var b_matches := false
	for req in recipe.inputs:
		var item_id: String = req.get("item_id", "")
		if card_a.card_data != null and card_a.card_data.id == item_id:
			a_matches = true
		if card_b.card_data != null and card_b.card_data.id == item_id:
			b_matches = true
	if not (a_matches and b_matches):
		return false

	var candidates := _gather_candidates(recipe, card_a, card_b, board)
	for req in recipe.inputs:
		var item_id: String = req.get("item_id", "")
		var qty: int = int(req.get("qty", 1))
		var total := 0
		for c in candidates:
			if c != null and not c.is_queued_for_deletion() and c.card_data != null and c.card_data.id == item_id:
				total += c.stack_count
		if total < qty:
			return false
	return true
