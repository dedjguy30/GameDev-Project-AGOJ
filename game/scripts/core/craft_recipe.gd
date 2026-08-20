class_name CraftRecipe
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var inputs: Array[Dictionary] = []   # [{item_id, qty}, ...]
@export var required_building_id: String = ""
@export var required_unit_role: Enums.UnitRole = Enums.UnitRole.ANY
@export var output_id: String = ""
@export var output_qty: int = 1
@export var duration_days: int = 0