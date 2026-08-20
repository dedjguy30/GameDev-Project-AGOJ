class_name CardStack
extends Panel

signal changed(stack: CardStack)

@export var capacity := 0

var cards: Array[Card] = []

@onready var _count_label: Label = %CountLabel

func _ready() -> void:
	add_to_group(&"drop_zones")
	_update_label()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pop_card()

func is_available() -> bool:
	return capacity == 0 or cards.size() < capacity

func add_card(card: Card) -> void:
	if card in cards:
		return
	cards.append(card)
	card.is_stacked = true
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = cards.size()
	card.pivot_offset = Vector2.ZERO
	card.scale = Vector2.ONE
	card.global_position = global_position + Vector2(cards.size() % 3, cards.size() / 3) * 3.0
	_update_label()
	changed.emit(self)

func pop_card() -> void:
	if cards.is_empty():
		return
	var card: Card = cards.pop_back()
	card.is_stacked = false
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.z_index = 0
	card.global_position = global_position + Vector2(0, 240)
	_update_label()
	changed.emit(self)

func _update_label() -> void:
	if _count_label:
		_count_label.text = str(cards.size())
