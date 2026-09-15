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

# --- Combine ke Structure (mis. Iron Ore → drop ke Furnace / Little Furnace) ---
# Kalau tidak kosong, resep 1-input hanya berlaku jika kartu satunya (target)
# id-nya ada di list ini (Building harus is_built, Unit selalu boleh).
@export var structure_target_ids: Array[String] = []

# --- Syarat kehadiran (dicek terpisah di RecipeResolver.check_blocked) ---
# Minimal salah satu Building di list ini harus sudah dibangun di board.
@export var required_any_structure_ids: Array[String] = []
# Minimal salah satu Unit (by id) di list ini harus ada di board.
@export var required_any_worker_ids: Array[String] = []

# --- Combine 3+ input (pool kartu longgar di sekitar titik drop) ---
# Item id yang jadi "jangkar" posisi spawn hasil combine (opsional).
@export var pool_anchor_ids: Array[String] = []