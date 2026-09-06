class_name UnitCardData
extends CardData

@export var role: Enums.UnitRole = Enums.UnitRole.GENERALIST
@export var role_efficiency_map: Dictionary = {}
@export var needs_food: bool = true
@export var needs_oxygen: bool = true
@export var needs_power_to_work: bool = false