class_name EventCardData
extends CardData

@export var effect_type: Enums.EventEffect = Enums.EventEffect.DAMAGE_HULL
@export var effect_value: float = 0.0
@export var duration_days: int = 0
@export var choices: Array[Dictionary] = []          # [{label, description, effect_code, effect_value}, ...]
@export var spawn_weight: int = 100