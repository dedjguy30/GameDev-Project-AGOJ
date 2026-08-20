class_name CardData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var category: Enums.CardCategory = Enums.CardCategory.NODE
@export var rarity: Enums.Rarity = Enums.Rarity.COMMON
@export var icon: Texture2D
@export var description: String = ""
@export var stack_max: int = 99
@export var sell_value: int = 0

func get_placeholder_color() -> Color:
	match category:
		Enums.CardCategory.NODE:
			return Color(0.45, 0.55, 0.65)
		Enums.CardCategory.ITEM_RAW:
			return Color(0.6, 0.6, 0.65)
		Enums.CardCategory.ITEM_PROCESSED:
			return Color(0.55, 0.75, 0.9)
		Enums.CardCategory.ITEM_FOOD:
			return Color(0.95, 0.75, 0.35)
		Enums.CardCategory.TOOL:
			return Color(0.5, 0.65, 0.95)
		Enums.CardCategory.BUILDING:
			return Color(0.75, 0.55, 0.9)
		Enums.CardCategory.UNIT:
			return Color(0.55, 0.9, 0.55)
		Enums.CardCategory.PACKAGE:
			return Color(0.95, 0.6, 0.55)
		Enums.CardCategory.EVENT:
			return Color(0.9, 0.4, 0.4)
		Enums.CardCategory.CURRENCY_LOOT:
			return Color(0.95, 0.85, 0.4)
		_:
			return Color(0.8, 0.8, 0.8)