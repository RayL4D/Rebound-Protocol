# =============================================================
# DashButton.gd — Bouton dash cyberpunk (Control)
# Rebound Protocol
# =============================================================
extends Control

# --- Palette ---
const C_BG       := Color(0.016, 0.055, 0.135, 0.88)
const C_BG_PRESS := Color(0.00,  0.56,  0.84,  0.97)
const C_RING     := Color(0.00,  0.80,  1.00,  1.00)
const C_RING_P   := Color(0.88,  0.98,  1.00,  1.00)
const C_ICON     := Color(0.55,  0.97,  1.00,  1.00)
const C_ICON_P   := Color(1.00,  1.00,  1.00,  1.00)
const C_SEP      := Color(0.00,  0.80,  1.00,  0.55)
const C_SEP_P    := Color(1.00,  1.00,  1.00,  0.80)
const C_TAG      := Color(0.88,  0.98,  1.00,  0.90)
const C_TAG_P    := Color(1.00,  1.00,  1.00,  1.00)

var _held           : bool   = false
var _player         : Player = null
var _dash_unlocked  : bool   = false

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_dash_unlocked = _check_dash_unlocked()

func _process(_delta: float) -> void:
	# Re-vérifier chaque frame : le skill peut être obtenu en cours de partie
	var unlocked := _check_dash_unlocked()
	if unlocked != _dash_unlocked:
		_dash_unlocked = unlocked
		queue_redraw()

func _check_dash_unlocked() -> bool:
	if not get_tree().root.has_node("XpManager"):
		return false
	return XpManager.has_skill("dash_unlock")

func _gui_input(event: InputEvent) -> void:
	if not _dash_unlocked:
		return   # Dash pas encore débloqué — bloquer toute interaction
	if event is InputEventScreenTouch:
		if event.pressed:
			_held = true
			queue_redraw()
			Input.action_press("dash")
		else:
			_held = false
			queue_redraw()
			Input.action_release("dash")

func _draw() -> void:
	var c : Vector2 = size / 2.0
	var r : float   = min(size.x, size.y) * 0.45
	var p : bool    = _held
	var font : Font = ThemeDB.fallback_font

	# ── État verrouillé ───────────────────────────────────────────
	if not _dash_unlocked:
		draw_circle(c, r, Color(0.06, 0.06, 0.10, 0.75))
		draw_arc(c, r, 0.0, TAU, 64, Color(0.35, 0.35, 0.40, 0.5), 2.5, true)
		# Cadenas dessiné (compatible vieux PC — pas d'emoji)
		var s   : float = r * 0.42
		var col : Color = Color(0.55, 0.55, 0.60, 0.85)
		# Corps du cadenas
		draw_polygon(PackedVector2Array([
			c + Vector2(-s * 0.72,  s * 0.08),
			c + Vector2( s * 0.72,  s * 0.08),
			c + Vector2( s * 0.72,  s * 0.95),
			c + Vector2(-s * 0.72,  s * 0.95),
		]), PackedColorArray([col, col, col, col]))
		# Anse (arc épais au-dessus du corps)
		draw_arc(c + Vector2(0.0, s * 0.12), s * 0.52, PI, TAU, 20, col, s * 0.28)
		# Trou de serrure
		draw_circle(c + Vector2(0.0, s * 0.48), s * 0.20, Color(0.04, 0.04, 0.08))
		return

	# ── État normal ────────────────────────────────────────────────
	# 1. Anneaux externes animés
	var gc := C_RING_P if p else C_RING
	for i in 6:
		var alpha : float = (0.18 if p else 0.12) - i * 0.02
		if alpha <= 0.0:
			break
		draw_arc(c, r + 5.0 + i * 4.0, 0.0, TAU, 64,
				 Color(gc.r, gc.g, gc.b, alpha), 2.5, true)

	# 2. Disque de fond
	draw_circle(c, r, C_BG_PRESS if p else C_BG)

	# 3. Anneau intérieur subtil
	draw_arc(c, r - 6.0, 0.0, TAU, 64,
			 Color(0.0, 0.8, 1.0, 0.20 if p else 0.08), 5.0, true)

	# 4. Bordure principale
	draw_arc(c, r, 0.0, TAU, 64, C_RING_P if p else C_RING, 3.0, true)

	# 5. Icône flèche dash
	var ic := C_ICON_P if p else C_ICON
	var hw : float = r * 0.22
	var hh : float = r * 0.18
	var offset_y : float = r * 0.10

	draw_line(Vector2(c.x - hw * 1.8, c.y - offset_y),
			  Vector2(c.x + hw * 0.2, c.y - offset_y), ic, 3.0, true)
	draw_line(Vector2(c.x - hw * 1.2, c.y - offset_y - hh * 0.6),
			  Vector2(c.x - hw * 0.2, c.y - offset_y - hh * 0.6), ic, 2.0, true)
	draw_line(Vector2(c.x - hw * 1.5, c.y - offset_y + hh * 0.6),
			  Vector2(c.x - hw * 0.5, c.y - offset_y + hh * 0.6), ic, 2.0, true)

	var ghost_pts = PackedVector2Array([
		Vector2(c.x - hw * 0.4, c.y - offset_y - hh * 0.75),
		Vector2(c.x + hw * 0.6, c.y - offset_y),
		Vector2(c.x - hw * 0.4, c.y - offset_y + hh * 0.75)
	])
	draw_polyline(ghost_pts, Color(ic.r, ic.g, ic.b, 0.4 if p else 0.15), 2.5, true)

	var arrow_pts = PackedVector2Array([
		Vector2(c.x + hw * 0.2, c.y - offset_y - hh),
		Vector2(c.x + hw * 1.4, c.y - offset_y),
		Vector2(c.x + hw * 0.2, c.y - offset_y + hh)
	])
	draw_polyline(arrow_pts, ic, 3.0, true)

	# 6. Séparateur
	var sy : float = c.y + r * 0.38
	draw_line(Vector2(c.x - r * 0.42, sy), Vector2(c.x + r * 0.42, sy),
			  C_SEP_P if p else C_SEP, 1.5, true)

	# 7. Label localisé — auto-fit pour que ça rentre quelle que soit la langue
	var text := tr("BTN_DASH")
	var font_size := maxi(int(r * 0.24), 8)
	var max_w : float = r * 0.90
	while font_size > 7 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
		font_size -= 1
	var tc := C_TAG_P if p else C_TAG
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, Vector2(c.x - text_size.x / 2.0, sy + text_size.y * 0.85),
				text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, tc)
