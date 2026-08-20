extends Node

# A10/A12 — Ekonomi. Autoload: Economy

const RARITY_MULTIPLIER: Dictionary = {
	Enums.Rarity.COMMON: 1.0,
	Enums.Rarity.UNCOMMON: 1.5,
	Enums.Rarity.RARE: 2.5,
	Enums.Rarity.EPIC: 4.0,
}

func try_sell(board: Board, card: Card) -> void:
	if card == null or card.card_data == null:
		return
	var value := int(round(float(card.card_data.sell_value) * float(RARITY_MULTIPLIER.get(card.card_data.rarity, 1.0))))
	if value <= 0:
		board._show_toast("Tidak bisa dijual", card.global_position, Color(1, 0.8, 0.5))
		return
	GameState.add_credits(value)
	board._show_toast("Dijual +%d cr" % value, card.global_position, Color(0.55, 1, 0.6))
	board.remove_card(card)

# A12 — harga progresif: base_cost × (1 + 5% × jumlah sudah dibeli)
func pack_cost(pack_id: String) -> int:
	var pack := RecipeDB.get_pack(pack_id)
	if pack == null:
		return 0
	var n: int = int(GameState.pack_purchase_counts.get(pack_id, 0))
	return pack.base_cost + int(round(pack.base_cost * 0.05 * n))

func buy_pack(pack_id: String) -> bool:
	if GameState.is_game_over:
		return false
	var cost := pack_cost(pack_id)
	if not GameState.spend_credits(cost):
		var board: Board = get_tree().get_first_node_in_group(&"board")
		if board != null:
			board._show_toast("Credits tidak cukup (%d cr)" % cost,
				board.ship_rect.position + Vector2(200, 300), Color(1, 0.6, 0.55))
		return false
	GameState.pack_purchase_counts[pack_id] = int(GameState.pack_purchase_counts.get(pack_id, 0)) + 1
	open_pack(pack_id)
	return true

func open_pack(pack_id: String) -> void:
	var board: Board = get_tree().get_first_node_in_group(&"board")
	if board == null:
		return
	var pack := RecipeDB.get_pack(pack_id)
	if pack == null:
		push_warning("Economy: pack tidak ada: " + pack_id)
		return
	var total_weight := 0
	for entry in pack.drop_table:
		total_weight += int(entry.get("weight", 0))
	for i in pack.card_count:
		if total_weight <= 0:
			break
		var roll := randf() * total_weight
		var acc := 0
		var picked := ""
		for entry in pack.drop_table:
			acc += int(entry.get("weight", 0))
			if roll < acc:
				picked = entry.get("card_id", "")
				break
		if picked == "":
			continue
		var card_data: CardData = CardDB.get_card(picked)
		var zone: Enums.BoardZone = Enums.BoardZone.OPEN_SPACE
		if card_data != null and card_data.category != Enums.CardCategory.NODE:
			zone = Enums.BoardZone.SHIP_INTERIOR
		board.spawn_card_at(picked, board.random_free_spot(zone))
	board._show_toast("Pack dibuka: " + pack.display_name,
		board.ship_rect.position + Vector2(240, 320), Color(0.7, 0.95, 1))

# A6 — efek tool consumable
func apply_tool_effect(tool_id: String, board: Board) -> void:
	match tool_id:
		"tool_repair_kit":
			GameState.hull = clampf(GameState.hull + 20.0, 0.0, GameState.HULL_MAX)
			board._show_toast("Hull +20", board.ship_rect.position + Vector2(240, 320), Color(0.55, 1, 0.6))
			GameState.stats_changed.emit()
		_:
			pass