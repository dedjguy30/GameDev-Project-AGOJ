class_name UIFactory
extends RefCounted

# Pabrik kecil untuk UI kode: satu baris per kontrol, tanpa duplikasi
# StyleBox/tema berulang di board.gd, hud.gd, menu.gd, intro.gd.

static func panel(size: Vector2, color: Color, radius := 8.0) -> Panel:
	var p := Panel.new()
	p.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.pivot_offset = size * 0.5
	return p

static func label(text: String, font_size := 15, color := Color(0.9, 0.95, 1),
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func button(text: String, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.size = size
	return b
