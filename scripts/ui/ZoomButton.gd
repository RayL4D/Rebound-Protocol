# =============================================================
# ZoomButton.gd — Bouton zoom / dézoom cyberpunk (Control)
# Rebound Protocol
# =============================================================
# Un appui court = un pas de zoom.
# Maintien appuyé = zoom continu après HOLD_DELAY secondes.
# Animation en boucle : anneaux qui s'expandent (zoom_in)
#                       ou se contractent (zoom_out).
# =============================================================
extends Control

## true  → zoom avant  (rapproche la caméra, réduit spring_length)
## false → zoom arrière (éloigne la caméra, augmente spring_length)
@export var zoom_in: bool = true

# --- Palette ---
const C_BG       := Color(0.016, 0.055, 0.135, 0.88)
const C_BG_PRESS := Color(0.00,  0.56,  0.84,  0.97)
const C_RING     := Color(0.00,  0.80,  1.00,  1.00)
const C_RING_P   := Color(0.88,  0.98,  1.00,  1.00)
const C_ICON     := Color(0.55,  0.97,  1.00,  1.00)
const C_ICON_P   := Color(1.00,  1.00,  1.00,  1.00)

## Pas de zoom appliqué à chaque tap (unités de spring_length).
const ZOOM_STEP   : float = 1.2
## Délai avant que le zoom continu ne démarre (secondes).
const HOLD_DELAY  : float = 0.35
## Vitesse du zoom continu une fois HOLD_DELAY dépassé (unités / seconde).
const HOLD_SPEED  : float = 4.0

## Durée d'un cycle complet des anneaux animés (secondes).
const RING_PERIOD : float = 1.1
## Nombre d'anneaux simultanés en boucle.
const RING_COUNT  : int   = 3

var _held       : bool   = false
var _hold_timer : float  = 0.0
var _time       : float  = 0.0
var _player     : Player = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player


# =============================================================
# INPUT
# =============================================================

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
		_hold_timer = 0.0
		accept_event()
		var p := _get_player()
		if p != null:
			var dir : float = -1.0 if zoom_in else 1.0
			p._target_zoom = clamp(p._target_zoom + dir * ZOOM_STEP, p.zoom_min, p.zoom_max)

	elif just_released:
		_held = false
		_hold_timer = 0.0
		accept_event()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()  # animation continue

	if not _held:
		return
	_hold_timer += delta
	if _hold_timer < HOLD_DELAY:
		return
	var p := _get_player()
	if p != null:
		var dir : float = -1.0 if zoom_in else 1.0
		p._target_zoom = clamp(
			p._target_zoom + dir * HOLD_SPEED * delta,
			p.zoom_min,
			p.zoom_max
		)


# =============================================================
# RENDU
# =============================================================

func _draw() -> void:
	var s  : Vector2 = size
	var c  : Vector2 = s * 0.5
	var r  : float   = minf(s.x, s.y) * 0.5 - 4.0
	var p  : bool    = _held
	var gc := C_RING_P if p else C_RING
	var ic := C_ICON_P if p else C_ICON

	# ----------------------------------------------------------
	# 1. Halos externes (glow)
	# ----------------------------------------------------------
	for i in 5:
		var alpha : float = (0.15 if p else 0.09) - i * 0.02
		if alpha <= 0.0:
			break
		draw_arc(c, r + 4.0 + i * 3.5, 0.0, TAU, 64,
				 Color(gc.r, gc.g, gc.b, alpha), 2.0, true)

	# ----------------------------------------------------------
	# 2. Disque de fond
	# ----------------------------------------------------------
	draw_circle(c, r, C_BG_PRESS if p else C_BG)

	# ----------------------------------------------------------
	# 3. Anneaux animés en boucle
	#    zoom_in  → anneaux qui s'expandent vers l'extérieur
	#    zoom_out → anneaux qui se contractent vers l'intérieur
	# ----------------------------------------------------------
	var r_inner : float = r * 0.18
	var r_outer : float = r * 0.82
	var base_alpha : float = 0.55 if p else 0.32

	for i in RING_COUNT:
		# Phase décalée pour chaque anneau
		var t : float = fmod(_time / RING_PERIOD + float(i) / float(RING_COUNT), 1.0)
		var ring_r  : float
		var ring_a  : float
		if zoom_in:
			# Expansion : démarre au centre, s'élargit et s'efface
			ring_r = r_inner + (r_outer - r_inner) * t
			ring_a = (1.0 - t) * base_alpha
		else:
			# Contraction : démarre à l'extérieur, rétrécit et s'efface
			ring_r = r_outer - (r_outer - r_inner) * t
			ring_a = (1.0 - t) * base_alpha
		draw_arc(c, ring_r, 0.0, TAU, 48,
				 Color(gc.r, gc.g, gc.b, ring_a), 1.8, true)

	# ----------------------------------------------------------
	# 4. Bordure principale
	# ----------------------------------------------------------
	draw_arc(c, r, 0.0, TAU, 64, C_RING_P if p else C_RING, 2.5, true)

	# ----------------------------------------------------------
	# 5. Icône + ou − (centré, plus grand sans le label)
	# ----------------------------------------------------------
	var bw : float = r * 0.46   # demi-largeur de la barre
	var bh : float = r * 0.11   # demi-épaisseur de la barre

	# Barre horizontale
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - bw, c.y - bh),
		Vector2(c.x + bw, c.y - bh),
		Vector2(c.x + bw, c.y + bh),
		Vector2(c.x - bw, c.y + bh),
	]), ic)

	# Barre verticale uniquement pour le bouton +
	if zoom_in:
		draw_colored_polygon(PackedVector2Array([
			Vector2(c.x - bh, c.y - bw),
			Vector2(c.x + bh, c.y - bw),
			Vector2(c.x + bh, c.y + bw),
			Vector2(c.x - bh, c.y + bw),
		]), ic)
