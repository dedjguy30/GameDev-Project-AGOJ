class_name PackageCardData
extends CardData

@export var destination_sector_id: String = ""
@export var required_items: Array[Dictionary] = []   # [{item_id, qty}, ...]
@export var reward_credits: int = 0
@export var reward_rep: int = 0
@export var deadline_days: int = 5
@export var tier: int = 1