class_name PackDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var base_cost: int = 10
@export var card_count: int = 3
@export var drop_table: Array[Dictionary] = []
# false = reward-only, tidak dijual di toko (mis. Mystery Pack, GDD A12).
@export var shop_visible: bool = true
# Reputasi minimum untuk membeli (GDD S4.2: Rep membuka pack tier tinggi).
@export var rep_required: int = 0
# Biaya resource dasar di board (Stacklands-style): harus ada sebelum pack
# bisa dibuka, dikonsumsi saat beli. Contoh: [{"item_id": "item_scrap_metal", "qty": 2}]
@export var resource_cost: Array[Dictionary] = []