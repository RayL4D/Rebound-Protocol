# =============================================================
# JumpButton.gd — Bouton saut cyberpunk (Control)
# Rebound Protocol
# =============================================================
# Extends Control et gère l'input directement dans _gui_input —
# plus fiable que les signaux Button sur mobile.
# Entièrement auto-suffisant : trouve le Player lui-même.
# =============================================================
extends Control

# --- Palette ---
const C_BG       := Color(0.016, 0.055, 0.135, 0.88)
const C_BG_PRESS := Color(0.00,  0.56,  0.84,  0.97)
const C_RING     := Color(0.00,  0.80,  1.00,  1.00)
const C_RING_P   := Color(0.88,  0.98,  1.00,  1.00)
const C_ARROW    := Color(0.55,  0.97,  1.00,  1.00)
const C_ARROW_P  := Color(1.00,  1.00,  1.00,  1.00)
const C_SEP      := Color(0.00,  0.80,  1.00,  0.55)
const C_SEP_P    := Color(1.00,  1.00,  1.00,  0.80)
const C_TAG      := Color(0.88,  0.98,  1.00,  0.90)
const C_TAG_P    := Color(1.00,  1.00,  1.00,  1.00)

var _held   : bool   = false
var _player : Player = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player


func _gui_input(event: InputEvent) -> void:
	var just_pressed  : bool = false
	var just_released : bool = false

	if event is InputEventScreenTouch:
		just_pressed  = event.pressed
		just_released = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		just_pressed  = event.pressed
		just_released = not event.pressed

	if just_pressed:
		_held = true
		queue_redraw()
		accept_event()
		var p := _get_player()
		if p != null:
			p.request_jump()

	elif just_released:
		_held = false
		queue_redraw()
		accept_event()


# =============================================================
# RENDU
# =============================================================

func _draw() -> void:
	var s  : Vector2 = size
	var c  : Vector2 = s * 0.5                        # centre
	var r  : float   = minf(s.x, s.y) * 0.5 - 6.0   # rayon
	var p  : bool    = _held

	# 1. Halos externes (glow concentrique)
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

	# 5. Flèche vectorielle (tête + hampe)
	var ac  := C_ARROW_P if p else C_ARROW
	var aw  : float = r * 0.40
	var sw  : float = r * 0.16
	var tip : float = c.y - r * 0.48
	var mid : float = c.y - r * 0.10
	var bot : float = c.y + r * 0.22
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x,      tip),
		Vector2(c.x - aw, mid),
		Vector2(c.x - sw, mid),
		Vector2(c.x - sw, bot),
		Vector2(c.x + sw, bot),
		Vector2(c.x + sw, mid),
		Vector2(c.x + aw, mid),
	]), ac)

	# 6. Séparateur horizontal
	var sy : float = c.y + r * 0.32
	draw_line(
		Vector2(c.x - r * 0.42, sy),
		Vector2(c.x + r * 0.42, sy),
		C_SEP_P if p else C_SEP, 1.5, true)

	# 7. Label "J  U  M  P"
	var tc  := C_TAG_P if p else C_TAG
	var fnt := get_theme_default_font()
	var fsz : int   = maxi(int(r * 0.21), 9)
	var lbl := "J  U  M  P"
	var tw  : float = fnt.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	draw_string(fnt,
		Vector2(c.x - tw * 0.5, sy + r * 0.25 + fsz),
		lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, tc)
