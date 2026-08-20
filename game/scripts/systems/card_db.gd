extends Node

const CARD_DIRS := [
	"res://data/cards",
	"res://data/packages",
	"res://data/events",
]

var _cards_by_id: Dictionary = {}

func _ready() -> void:
	for dir_path in CARD_DIRS:
		_scan_dir(dir_path)

func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("CardDB: folder tidak ditemukan: " + path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full_path := path + "/" + entry
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				_scan_dir(full_path)
		elif entry.ends_with(".tres"):
			var res: Resource = load(full_path)
			if res is CardData:
				_cards_by_id[res.id] = res
			else:
				push_warning("CardDB: bukan CardData: " + full_path)
		entry = dir.get_next()
	dir.list_dir_end()

func get_card(id: String) -> CardData:
	return _cards_by_id.get(id)

func has_card(id: String) -> bool:
	return _cards_by_id.has(id)

func get_all() -> Array[CardData]:
	var cards: Array[CardData] = []
	for card in _cards_by_id.values():
		cards.append(card)
	return cards

func get_count() -> int:
	return _cards_by_id.size()

func get_cards_of_category(category: Enums.CardCategory) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in _cards_by_id.values():
		if card.category == category:
			result.append(card)
	return result

func get_nodes() -> Array[CardData]:
	return get_cards_of_category(Enums.CardCategory.NODE)

func get_items() -> Array[CardData]:
	return get_cards_of_category(Enums.CardCategory.ITEM_RAW) \
		+ get_cards_of_category(Enums.CardCategory.ITEM_PROCESSED) \
		+ get_cards_of_category(Enums.CardCategory.ITEM_FOOD)

func get_tools() -> Array[CardData]:
	return get_cards_of_category(Enums.CardCategory.TOOL)

func get_buildings() -> Array[CardData]:
	return get_cards_of_category(Enums.CardCategory.BUILDING)

func get_units() -> Array[CardData]:
	return get_cards_of_category(Enums.CardCategory.UNIT)

func get_packages() -> Array[CardData]:
	return get_cards_of_category(Enums.CardCategory.PACKAGE)

func get_events() -> Array[CardData]:
	return get_cards_of_category(Enums.CardCategory.EVENT)

func get_loot() -> Array[CardData]:
	return get_cards_of_category(Enums.CardCategory.CURRENCY_LOOT)