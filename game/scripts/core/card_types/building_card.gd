class_name BuildingCardData
extends CardData

@export var build_cost: Array[Dictionary] = []   # [{item_id, qty}, ...]
@export var power_draw: int = 0
@export var max_unit_slots: int = 1
@export var production: Dictionary = {}          # {input_item_id, input_qty, output_item_id, output_qty, interval_days}
@export var passive_effect: String = ""
@export var max_connections: int = 0
@export var power_generated: int = 0