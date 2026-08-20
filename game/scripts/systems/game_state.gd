extends Node

signal day_changed(day: int)
signal stats_changed
signal credits_changed(credits: int)
signal reputation_changed(reputation: int)
signal game_over(reason: String)

const O2_MAX := 100.0
const FOOD_MAX := 100.0
const HULL_MAX := 100.0
const MORALE_MAX := 100.0

# --- Stat kapal (A11) ---
var oxygen: float = O2_MAX
var food: float = FOOD_MAX
var hull: float = HULL_MAX
var power: float = 50.0
var power_cap: float = 50.0
var morale: float = MORALE_MAX

# --- Ekonomi (A10, A12) ---
var credits: int = 50
var reputation: int = 0

# --- Waktu (A15) ---
var day: int = 0
var days_without_food: int = 0
var days_without_oxygen: int = 0
var is_game_over: bool = false
var game_over_reason: String = ""

# --- Efek aktif sementara (A9: durasi event) ---
var active_effects: Dictionary = {}   # key -> sisa hari; dipakai DayCycle & EventManager

# --- Skor (A16) ---
var total_credits_earned: int = 0
var total_packages_delivered: int = 0
var score: int = 0

# --- Pembelian pack (A12) ---
var pack_purchase_counts: Dictionary = {}

func reset() -> void:
	oxygen = O2_MAX
	food = FOOD_MAX
	hull = HULL_MAX
	power = 50.0
	power_cap = 50.0
	morale = MORALE_MAX
	credits = 50
	reputation = 0
	day = 0
	days_without_food = 0
	days_without_oxygen = 0
	is_game_over = false
	game_over_reason = ""
	active_effects.clear()
	total_credits_earned = 0
	total_packages_delivered = 0
	score = 0
	pack_purchase_counts.clear()
	stats_changed.emit()
	credits_changed.emit(credits)
	reputation_changed.emit(reputation)
	day_changed.emit(day)

func add_credits(amount: int) -> void:
	credits += amount
	if amount > 0:
		total_credits_earned += amount
	credits_changed.emit(credits)

func can_afford(cost: int) -> bool:
	return credits >= cost

func spend_credits(amount: int) -> bool:
	if credits < amount:
		return false
	credits -= amount
	credits_changed.emit(credits)
	return true

func add_reputation(amount: int) -> void:
	reputation += amount
	reputation_changed.emit(reputation)

func advance_day() -> void:
	day += 1
	day_changed.emit(day)

func update_score() -> void:
	score = (day * 100) + (total_credits_earned * 1) + (total_packages_delivered * 50)

func end_game(reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	game_over_reason = reason
	game_over.emit(reason)