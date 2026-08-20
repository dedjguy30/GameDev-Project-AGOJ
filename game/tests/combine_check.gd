extends Node

const CARD_SCENE := preload("res://scenes/card.tscn")
const MAIN_SCENE := preload("res://main.tscn")

var _errors: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run_find_recipe_tests()
	await _run_combine_flow_tests()
	if _errors.is_empty():
		print("COMBINE CHECK: OK")
		get_tree().quit(0)
	else:
		for e in _errors:
			push_error(e)
		print("COMBINE CHECK: FAIL - ", _errors.size(), " error(s)")
		get_tree().quit(1)

func _fail(msg: String) -> void:
	_errors.append(msg)

func _make_card(card_id: String, count := 1) -> Card:
	var card: Card = CARD_SCENE.instantiate()
	add_child(card)
	card.setup_card(CardDB.get_card(card_id), count)
	card.global_position = Vector2(-500, -500)
	return card

func _expect_recipe(card_a: Card, card_b: Card, expected: String, label: String) -> void:
	var recipe := RecipeResolver.find_recipe(card_a, card_b)
	var got: String = recipe.id if recipe != null else "null"
	if got != expected:
		_fail("%s: expected %s, got %s" % [label, expected, got])

func _run_find_recipe_tests() -> void:
	_expect_recipe(_make_card("item_scrap_metal", 2), _make_card("item_crystal_ore", 1),
		"recipe_circuit_board", "scrap2+crystal1")
	_expect_recipe(_make_card("item_crystal_ore", 1), _make_card("item_scrap_metal", 2),
		"recipe_circuit_board", "crystal1+scrap2 (dibalik)")
	_expect_recipe(_make_card("item_ice_chunk", 1), _make_card("tool_heat_source", 1),
		"recipe_water_melt", "ice+heat_source")
	_expect_recipe(_make_card("item_scrap_metal", 3), _make_card("unit_engineer", 1),
		"recipe_mining_drill", "scrap3+engineer")
	_expect_recipe(_make_card("item_scrap_metal", 2), _make_card("unit_engineer", 1),
		"null", "scrap2+engineer (qty kurang)")
	_expect_recipe(_make_card("item_scrap_metal", 3), _make_card("unit_astronaut", 1),
		"null", "scrap3+astronaut (role salah)")
	_expect_recipe(_make_card("unit_astronaut", 1), _make_card("item_circuit_board", 2),
		"recipe_promote_engineer", "astronaut+circuit2")
	_expect_recipe(_make_card("unit_astronaut", 1), _make_card("item_alien_flora", 1),
		"recipe_promote_scientist", "astronaut+alien_flora")
	_expect_recipe(_make_card("unit_astronaut", 1), _make_card("item_fuel_cell", 2),
		"recipe_promote_pilot", "astronaut+fuel_cell2")
	_expect_recipe(_make_card("unit_astronaut", 1), _make_card("item_fuel_cell", 1),
		"null", "astronaut+fuel_cell1 (qty kurang)")
	_expect_recipe(_make_card("item_water", 1), _make_card("item_water", 1),
		"null", "water+water (bukan resep)")
	_expect_recipe(_make_card("item_metal_ingot", 1), _make_card("item_circuit_board", 1),
		"null", "metal1+circuit1 (qty kurang utk cutting laser)")

# --- Helper khusus kartu di BOARD (bukan kartu test _make_card) ---

func _find_on_board(board: Board, card_id: String) -> Card:
	for child in board.get_children():
		var card := child as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			return card
	return null

func _count_on_board(board: Board, card_id: String) -> int:
	var total := 0
	for child in board.get_children():
		var card := child as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			total += card.stack_count
	return total

func _run_combine_flow_tests() -> void:
	var board: Board = MAIN_SCENE.instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	# A. scrap(x2) di-drop ke crystal → Circuit Board baru spawn, scrap habis
	var scrap := _find_on_board(board, "item_scrap_metal")
	var crystal := _find_on_board(board, "item_crystal_ore")
	var circuit_before: int = _count_on_board(board, "item_circuit_board")
	board._on_card_dropped(scrap, crystal.global_position + crystal.size * 0.5)
	await get_tree().process_frame
	if _count_on_board(board, "item_circuit_board") != circuit_before + 1:
		_fail("flow A: circuit board tidak bertambah (sebelum %d, sesudah %d)" \
			% [circuit_before, _count_on_board(board, "item_circuit_board")])
	var scrap_left := _count_on_board(board, "item_scrap_metal")
	if scrap_left != 6:
		_fail("flow A: scrap seharusnya 6 (8-2), sekarang %d" % scrap_left)

	# B. astronaut + circuit(x2) → Engineer (promosi, workshop ada)
	var astronaut := _find_on_board(board, "unit_astronaut")
	var circuit := _find_on_board(board, "item_circuit_board")
	board._on_card_dropped(astronaut, circuit.global_position + circuit.size * 0.5)
	await get_tree().process_frame
	if _count_on_board(board, "unit_engineer") != 2:
		_fail("flow B: unit_engineer seharusnya 2 (1 spawn + 1 promosi), sekarang %d"
			% _count_on_board(board, "unit_engineer"))
	if _count_on_board(board, "unit_astronaut") != 1:
		_fail("flow B: unit_astronaut seharusnya 1 (1 dikonsumsi), sekarang %d"
			% _count_on_board(board, "unit_astronaut"))

	# C. workshop dihapus → promosi harus DIBLOKIR (tidak konsumsi, tidak spawn)
	var workshop := _find_on_board(board, "building_workshop")
	workshop.queue_free()
	await get_tree().process_frame
	var astronaut2 := _find_on_board(board, "unit_astronaut")
	var flora := _find_on_board(board, "item_alien_flora")
	board._on_card_dropped(astronaut2, flora.global_position + flora.size * 0.5)
	await get_tree().process_frame
	if _count_on_board(board, "unit_scientist") != 0:
		_fail("flow C: scientist tidak boleh spawn saat workshop hilang")
	if _count_on_board(board, "unit_astronaut") != 1 or _count_on_board(board, "item_alien_flora") != 1:
		_fail("flow C: input tidak boleh terkonsumsi saat diblokir")