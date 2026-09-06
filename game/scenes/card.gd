class_name Card
extends Panel

signal clicked(card: Card)
signal dropped(card: Card, position: Vector2)

const DRAG_THRESHOLD := 6.0
const DRAG_SCALE := 1.1
const DRAG_Z_INDEX := 100

var card_data: CardData
var stack_count := 1

# A3 — runtime state gather (bukan data, tidak menyentuh resource bersama)
var assigned_node: Card = null        # Unit → Node yang sedang dikerjai
var node_durability_left: int = -1    # Node: sisa durability (is_limited)
var _gather_timer := 0.0

# A4 — state machine unit
var unit_state: int = Enums.UnitState.IDLE
var assigned_building: Card = null    # Unit → Building tempat WORKING
var equipped_tool_ids: Array[String] = []

# A1.2 — O2 tether
var is_tethered := false
var tether_status: int = Enums.TetherStatus.NORMAL
var tank_days_left := 0

# A7 — building runtime
var is_built := false                 # sudah dibayar build_cost & terpasang
var is_off := false                   # auto-shutdown kekurangan power
var production_timer := 0.0           # progress produksi real-time (dipakai unit WORKING)

# A8 — package runtime
var assembled_items: Dictionary = {}  # item_id -> qty sudah dikunci
var is_departing := false             # sedang TRAVELING (kartu dikeluarkan dari board)

var _dragging := false
var _was_dragging := false
var _drag_offset := Vector2.ZERO
var _press_position := Vector2.ZERO
var _pre_drag_position := Vector2.ZERO

@onready var _title_label: Label = %TitleLabel
@onready var _color_rect: ColorRect = %ColorRect
@onready var _count_label: Label = %CountLabel
@onready var _category_label: Label = %CategoryLabel
@onready var _status_label: Label = %StatusLabel
@onready var _progress_track: ColorRect = %ProgressTrack
@onready var _progress_fill: ColorRect = %ProgressFill

func _ready() -> void:
	add_to_group(&"cards")
	_update_visuals()

func setup_card(data: CardData, count := 1, built := false) -> void:
	card_data = data
	stack_count = count
	is_built = built
	if is_building() and not built:
		# Bangunan belum dibangun: tampil sebagai kartu (tidak bisa dipakai sampai build_cost dibayar)
		is_off = false
	var node_data := data as NodeCardData
	if node_data != null and node_data.is_limited:
		node_durability_left = node_data.durability
	if is_inside_tree():
		_update_visuals()

func is_unit() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.UNIT

func is_node() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.NODE

func is_building() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.BUILDING

func is_package() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.PACKAGE

func is_tool() -> bool:
	return card_data != null and card_data.category == Enums.CardCategory.TOOL

func get_card_id() -> String:
	return card_data.id

func _update_visuals() -> void:
	if card_data == null:
		return
	_title_label.text = card_data.display_name
	_color_rect.color = card_data.get_placeholder_color()
	_category_label.text = _category_short()
	_count_label.text = "x%d" % stack_count if stack_count > 1 else ""
	_count_label.visible = stack_count > 1
	_update_status_visual()

func _update_status_visual() -> void:
	if card_data == null:
		return
	if is_unit():
		match unit_state:
			Enums.UnitState.DEAD:
				_status_label.text = "DEAD"
				return
			Enums.UnitState.TRAVELING:
				_status_label.text = "TRAVELING"
				return
	if tether_status == Enums.TetherStatus.O2_CUT:
		_status_label.text = "O2 CUT!"
		return
	if is_tethered:
		_status_label.text = "TETHERED"
		return
	if assigned_node != null or assigned_building != null:
		_status_label.text = "WORKING"
		return
	if is_package():
		_status_label.text = _package_progress_text()
		return
	if is_node() and node_durability_left >= 0:
		_status_label.text = "DUR %d" % node_durability_left
		return
	if is_unit() and not equipped_tool_ids.is_empty():
		var names: Array[String] = []
		for tool_id in equipped_tool_ids:
			var tool: CardData = CardDB.get_card(tool_id)
			names.append(tool.display_name if tool != null else tool_id)
		_status_label.text = "EQ: " + ", ".join(names)
		return
	_status_label.text = ""

func refresh() -> void:
	_update_visuals()

# ---------- A3: assign unit ke node ----------

func assign_to_node(node: Card) -> void:
	assigned_node = node
	_gather_timer = 0.0
	set_gather_progress(0.0)
	set_unit_state(Enums.UnitState.WORKING)
	z_index = 2
	global_position = node.global_position + Vector2(6.0, 23.0)
	_update_status_visual()

func unassign() -> void:
	assigned_node = null
	_gather_timer = 0.0
	set_gather_progress(-1.0)
	if assigned_building == null:
		set_unit_state(Enums.UnitState.IDLE)
	else:
		_update_status_visual()
	z_index = 0

func set_gather_progress(p: float) -> void:
	if _progress_track == null or _progress_fill == null:
		return
	var show_bar: bool = (assigned_node != null or assigned_building != null) and p >= 0.0
	_progress_track.visible = show_bar
	_progress_fill.visible = show_bar
	if show_bar:
		_progress_fill.size.x = _progress_track.size.x * clampf(p, 0.0, 1.0)

# ---------- A7: assign unit ke building ----------

func assign_to_building(building: Card) -> void:
	assigned_building = building
	set_unit_state(Enums.UnitState.WORKING)
	z_index = 2
	global_position = building.global_position + Vector2(6.0, 23.0)
	_update_status_visual()

func unassign_from_building() -> void:
	assigned_building = null
	set_gather_progress(-1.0)
	if assigned_node == null:
		set_unit_state(Enums.UnitState.IDLE)
	else:
		_update_status_visual()
	z_index = 0

# ---------- A4: unit state machine ----------

func set_unit_state(state: int) -> void:
	unit_state = state
	_update_status_visual()

# ---------- A5: tool equip ----------

func equip_tool(tool_id: String) -> void:
	if equipped_tool_ids.has(tool_id):
		return
	equipped_tool_ids.append(tool_id)
	_update_status_visual()

func has_equipped_tool(tool_id: String) -> bool:
	return equipped_tool_ids.has(tool_id)

# ---------- A1.2: tether ----------

func set_tethered(tethered: bool) -> void:
	is_tethered = tethered
	_update_status_visual()

func set_tether_status(status: int) -> void:
	tether_status = status
	_update_status_visual()

# ---------- A8: package assembly ----------

func get_package_requirement_count() -> int:
	var pkg_data := card_data as PackageCardData
	if pkg_data == null:
		return 0
	return pkg_data.required_items.size()

func is_package_complete() -> bool:
	var required: Array = card_data.required_items if card_data != null else []
	for req in required:
		var item_id: String = req.get("item_id", "")
		var qty: int = int(req.get("qty", 1))
		if int(assembled_items.get(item_id, 0)) < qty:
			return false
	return required.size() > 0

func _package_progress_text() -> String:
	var required: Array = card_data.required_items if card_data != null else []
	var done := 0
	var total := 0
	for req in required:
		var item_id: String = req.get("item_id", "")
		var qty: int = int(req.get("qty", 1))
		total += qty
		done += mini(qty, int(assembled_items.get(item_id, 0)))
	if total == 0:
		return ""
	if is_package_complete():
		return "READY"
	return "%d/%d" % [done, total]

func set_stack_count(n: int) -> void:
	stack_count = n
	_update_visuals()

func _category_short() -> String:
	match card_data.category:
		Enums.CardCategory.NODE:
			return "NODE"
		Enums.CardCategory.ITEM_RAW:
			return "RAW"
		Enums.CardCategory.ITEM_PROCESSED:
			return "PROC"
		Enums.CardCategory.ITEM_FOOD:
			return "FOOD"
		Enums.CardCategory.TOOL:
			return "TOOL"
		Enums.CardCategory.BUILDING:
			return "BUILD"
		Enums.CardCategory.UNIT:
			return "UNIT"
		Enums.CardCategory.PACKAGE:
			return "PKG"
		Enums.CardCategory.EVENT:
			return "EVENT"
		Enums.CardCategory.CURRENCY_LOOT:
			return "LOOT"
	return ""

func is_draggable() -> bool:
	if card_data == null:
		return false
	if card_data.category == Enums.CardCategory.NODE or card_data.category == Enums.CardCategory.EVENT:
		return false
	if is_building() and is_built:
		return false
	if is_unit() and (unit_state == Enums.UnitState.TRAVELING or unit_state == Enums.UnitState.DEAD):
		return false
	return true

func _gui_input(event: InputEvent) -> void:
	if not is_draggable():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag()
		else:
			_end_drag()

func _process(_delta: float) -> void:
	if not _dragging:
		return
	global_position = get_global_mouse_position() - _drag_offset
	if not _was_dragging and global_position.distance_to(_press_position) > DRAG_THRESHOLD:
		_was_dragging = true

func _begin_drag() -> void:
	_dragging = true
	_was_dragging = false
	_press_position = get_global_mouse_position()
	_pre_drag_position = global_position
	_drag_offset = _press_position - global_position
	z_index = DRAG_Z_INDEX
	pivot_offset = size * 0.5
	scale = Vector2(DRAG_SCALE, DRAG_SCALE)

func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	z_index = 0
	pivot_offset = Vector2.ZERO
	scale = Vector2.ONE
	if _was_dragging:
		var board: Node = get_tree().get_first_node_in_group(&"board")
		if board == null or not board.validate_drop(self):
			_revert_drop()
			return
		if _try_merge_stack():
			return
		dropped.emit(self, get_global_mouse_position())
	else:
		clicked.emit(self)

func _revert_drop() -> void:
	global_position = _pre_drag_position
	var tween := create_tween()
	tween.tween_property(self, "self_modulate", Color(1, 0.35, 0.35, 1), 0.12)
	tween.tween_property(self, "self_modulate", Color.WHITE, 0.3)

func _is_stackable_item() -> bool:
	return card_data != null \
		and card_data.stack_max > 0 \
		and (card_data.category == Enums.CardCategory.ITEM_RAW \
			or card_data.category == Enums.CardCategory.ITEM_PROCESSED \
			or card_data.category == Enums.CardCategory.ITEM_FOOD)

func _try_merge_stack() -> bool:
	if not _is_stackable_item():
		return false
	var mouse_position := get_global_mouse_position()
	for node in get_tree().get_nodes_in_group(&"cards"):
		var other: Card = node as Card
		if other == self or other.is_queued_for_deletion():
			continue
		if other.card_data == null or other.card_data.id != card_data.id:
			continue
		if other.stack_count >= other.card_data.stack_max:
			continue
		if not other.get_global_rect().grow(4.0).has_point(mouse_position):
			continue
		var space: int = other.card_data.stack_max - other.stack_count
		var moved: int = mini(space, stack_count)
		other.stack_count += moved
		other._update_visuals()
		stack_count -= moved
		if stack_count <= 0:
			queue_free()
		else:
			_update_visuals()
			global_position = other.global_position + Vector2(12, 12)
		return true
	return false