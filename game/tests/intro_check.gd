extends Node

# Test intro pilih-pack: overlay muncul dengan 3 pilihan → pilih 1 →
# reveal minis → Ke Board spawn kit pack itu + overlay hilang.
# Board dibuat dengan force_intro agar intro jalan walau headless
# (board normal headless me-skip intro).

var _errors: Array[String] = []
var _board: Board
var _intro: IntroOverlay

func _ready() -> void:
	await get_tree().process_frame
	_board = Board.new()
	_board.force_intro = true
	add_child(_board)
	await get_tree().process_frame
	await get_tree().process_frame
	await _run_intro_tests()
	if _errors.is_empty():
		print("INTRO CHECK: OK")
		get_tree().quit(0)
	else:
		for e in _errors:
			push_error(e)
		print("INTRO CHECK: FAIL - ", _errors.size(), " error(s)")
		get_tree().quit(1)

func _fail(msg: String) -> void:
	_errors.append(msg)

func _count(card_id: String) -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group(&"cards"):
		var card := node as Card
		if card != null and not card.is_queued_for_deletion() \
				and card.card_data != null and card.get_card_id() == card_id:
			total += card.stack_count
	return total

func _buttons_named(text: String) -> Array[Button]:
	var found: Array[Button] = []
	if _intro == null:
		return found
	for node in _intro.find_children("*", "Button", true, false):
		var btn := node as Button
		if btn != null and btn.text == text:
			found.append(btn)
	return found

func _run_intro_tests() -> void:
	_intro = _board.get_node_or_null("IntroOverlay") as IntroOverlay
	# 1. Overlay + 3 tombol Pilih muncul, 4 node dunia ter-spawn.
	if _intro == null:
		_fail("intro 1: IntroOverlay tidak muncul")
		return
	if (_intro as ColorRect).size.x <= 0.0 or (_intro as ColorRect).size.y <= 0.0:
		_fail("intro 1: overlay berukuran nol (dim tidak tampil, klik lolos)")
		return
	if _buttons_named("Choose").size() != IntroOverlay.INTRO_PACKS.size():
		_fail("intro 1: tombol Choose harus %d, ada %d" \
			% [IntroOverlay.INTRO_PACKS.size(), _buttons_named("Choose").size()])
	if _count("node_debris_field") != 1 or _count("node_ice_field") != 1:
		_fail("intro 1: node dunia harus ter-spawn (debris=%d ice=%d)" \
			% [_count("node_debris_field"), _count("node_ice_field")])
	# Kit belum spawn sebelum Ke Board.
	if _count("unit_astronaut") != 0 or _count("item_food") != 0:
		_fail("intro 1: starter kit tidak boleh spawn sebelum Ke Board")

	# 2. Pilih pack pertama → reveal butuh ~1.5 dtk (punch + 6 mini staggered).
	_intro.choose_pack(0)
	await get_tree().create_timer(3.0).timeout
	if _buttons_named("Start").size() != 1:
		_fail("intro 2: tombol Start tidak muncul setelah reveal")
		return
	# Pilih kedua tidak boleh ganti pilihan.
	_intro.choose_pack(1)
	if _count("unit_astronaut") != 0:
		_fail("intro 2: pilih ulang tidak boleh spawn apa pun")

	# 3. Klik Start → kit pack pertama spawn sesuai data, overlay hilang.
	_buttons_named("Start")[0].pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var kit: Array = IntroOverlay.INTRO_PACKS[0]["kit"]
	for entry in kit:
		var want := int(entry[1])
		var got := _count(String(entry[0]))
		if got != want:
			_fail("intro 3: %s harus %d, sekarang %d" % [String(entry[0]), want, got])
	if is_instance_valid(_intro):
		await get_tree().process_frame
		if is_instance_valid(_intro):
			_fail("intro 3: overlay harus hilang setelah Ke Board")
