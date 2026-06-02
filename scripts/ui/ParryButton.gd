# =============================================================
# ParryButton.gd — Bouton parade cyberpunk (Control)
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
			p.request_parry()
	elif just_released:
		_held = false
		queue_redraw()
		accept_event()


# =============================================================
# RENDU
# =============================================================

func _draw() -> void:
	var s  : Vector2 = size
	var c  : Vector2 = s * 0.5
	var r  : float   = minf(s.x, s.y) * 0.5 - 6.0
	var p  : bool    = _held

	# ----------------------------------------------------------
	# 1. Halos externes (glow)
	# ----------------------------------------------------------
	var gc := C_RING_P if p else C_RING
	for i in 6:
		var alpha : float = (0.18 if p else 0.12) - i * 0.02
		if alpha <= 0.0:
			break
		draw_arc(c, r + 5.0 + i * 4.0, 0.0, TAU, 64,
				 Color(gc.r, gc.g, gc.b, alpha), 2.5, true)

	# ----------------------------------------------------------
	# 2. Disque de fond
	# ----------------------------------------------------------
	draw_circle(c, r, C_BG_PRESS if p else C_BG)

	# ----------------------------------------------------------
	# 3. Anneau intérieur subtil
	# ----------------------------------------------------------
	draw_arc(c, r - 6.0, 0.0, TAU, 64,
			 Color(0.0, 0.8, 1.0, 0.20 if p else 0.08), 5.0, true)

	# ----------------------------------------------------------
	# 4. Bordure principale
	# ----------------------------------------------------------
	draw_arc(c, r, 0.0, TAU, 64, C_RING_P if p else C_RING, 3.0, true)

	# ----------------------------------------------------------
	# 5. Bouclier vectoriel
	#    5 points : toit plat, côtés droits, pointe en bas
	#    Fill semi-transparent + contour plein → look cyberpunk propre
	# ----------------------------------------------------------
	var ic    := C_ICON_P if p else C_ICON
	var hw    : float = r * 0.28   # demi-largeur
	var sh_t  : float = c.y - r * 0.38   # haut du bouclier
	var sh_m  : float = c.y + r * 0.04   # jonction côtés / convergence
	var sh_b  : float = c.y + r * 0.26   # pointe basse

	var pts := PackedVector2Array([
		Vector2(c.x - hw, sh_t),
		Vector2(c.x + hw, sh_t),
		Vector2(c.x + hw, sh_m),
		Vector2(c.x,       sh_b),
		Vector2(c.x - hw, sh_m),
	])

	# Fill transparent
	draw_colored_polygon(pts, Color(ic.r, ic.g, ic.b, 0.22 if p else 0.14))

	# Contour (polyline fermé)
	draw_polyline(PackedVector2Array([
		Vector2(c.x - hw, sh_t),
		Vector2(c.x + hw, sh_t),
		Vector2(c.x + hw, sh_m),
		Vector2(c.x,       sh_b),
		Vector2(c.x - hw, sh_m),
		Vector2(c.x - hw, sh_t),
	]), ic, 2.5, true)

	# Barre horizontale dans le tiers supérieur du bouclier (heraldique)
	var bar_y : float = sh_t + (sh_m - sh_t) * 0.42
	var bar_w : float = hw * 0.88
	draw_line(Vector2(c.x - bar_w, bar_y),
			  Vector2(c.x + bar_w, bar_y),
			  Color(ic.r, ic.g, ic.b, 0.55 if p else 0.38), 1.5, true)

	# ----------------------------------------------------------
	# 6. Séparateur — positionné sous la pointe du bouclier
	# ----------------------------------------------------------
	var sy : float = c.y + r * 0.38   # sh_b est à r*0.26, gap de 0.12
	draw_line(
		Vector2(c.x - r * 0.42, sy),
		Vector2(c.x + r * 0.42, sy),
		C_SEP_P if p else C_SEP, 1.5, true)

	# ----------------------------------------------------------
	# 7. Label localisé — auto-fit pour que ça rentre quelle que soit la langue
	# ----------------------------------------------------------
	var tc  := C_TAG_P if p else C_TAG
	var fnt := get_theme_default_font()
	var lbl := tr("BTN_PARRY")
	var fsz : int   = maxi(int(r * 0.21), 8)
	var max_w : float = r * 0.90
	while fsz > 7 and fnt.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x > max_w:
		fsz -= 1
	var tw  : float = fnt.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	# Baseline : centre vertical entre séparateur et bord du cercle
	var text_y : float = sy + (r - sy + c.y) * 0.52 + fsz * 0.5
	draw_string(fnt,
		Vector2(c.x - tw * 0.5, text_y),
		lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, tc)
