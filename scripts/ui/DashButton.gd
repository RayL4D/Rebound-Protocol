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

var _held   : bool   = false
var _player : Player = null

func _ready() -> void:
	# Ajuste cette ligne si tu utilises une autre méthode pour récupérer le Player
	# (Par exemple, si c'est MobileControls.gd qui injecte la référence)
	_player = get_tree().get_first_node_in_group("player")

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_held = true
			queue_redraw()
			# Si ton système de dash fonctionne avec l'Input Map de Godot :
			Input.action_press("dash")
			
			# Ou si tu appelles une fonction directe dans ton Player.gd :
			# if _player and _player.has_method("request_dash"):
			# 	_player.request_dash()
		else:
			_held = false
			queue_redraw()
			Input.action_release("dash")

func _draw() -> void:
	var c : Vector2 = size / 2.0
	var r : float   = min(size.x, size.y) * 0.45
	var p : bool    = _held

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

	# 5. Icône : Flèche de Dash Cyberpunk avec lignes de vitesse
	var ic := C_ICON_P if p else C_ICON
	var hw : float = r * 0.22 # Échelle horizontale
	var hh : float = r * 0.18 # Échelle verticale
	var offset_y : float = r * 0.10 # Décalage vers le haut pour le texte

	# --- Traînées de vitesse (Speed lines) ---
	# Ligne centrale longue
	draw_line(Vector2(c.x - hw * 1.8, c.y - offset_y),
			  Vector2(c.x + hw * 0.2, c.y - offset_y), ic, 3.0, true)
	
	# Ligne supérieure (plus courte)
	draw_line(Vector2(c.x - hw * 1.2, c.y - offset_y - hh * 0.6),
			  Vector2(c.x - hw * 0.2, c.y - offset_y - hh * 0.6), ic, 2.0, true)
			  
	# Ligne inférieure (décalée)
	draw_line(Vector2(c.x - hw * 1.5, c.y - offset_y + hh * 0.6),
			  Vector2(c.x - hw * 0.5, c.y - offset_y + hh * 0.6), ic, 2.0, true)

	# --- Flèche fantôme (Afterimage / Écho semi-transparent) ---
	var ghost_pts = PackedVector2Array([
		Vector2(c.x - hw * 0.4, c.y - offset_y - hh * 0.75),
		Vector2(c.x + hw * 0.6, c.y - offset_y),
		Vector2(c.x - hw * 0.4, c.y - offset_y + hh * 0.75)
	])
	draw_polyline(ghost_pts, Color(ic.r, ic.g, ic.b, 0.4 if p else 0.15), 2.5, true)

	# --- Tête de flèche principale (Pointue et agressive) ---
	var arrow_pts = PackedVector2Array([
		Vector2(c.x + hw * 0.2, c.y - offset_y - hh),
		Vector2(c.x + hw * 1.4, c.y - offset_y),
		Vector2(c.x + hw * 0.2, c.y - offset_y + hh)
	])
	draw_polyline(arrow_pts, ic, 3.0, true)
	
	# 6. Séparateur
	var sy : float = c.y + r * 0.38
	draw_line(
		Vector2(c.x - r * 0.42, sy),
		Vector2(c.x + r * 0.42, sy),
		C_SEP_P if p else C_SEP, 1.5, true)

	# 7. Label "DASH"
	var font : Font = ThemeDB.fallback_font
	var text := "DASH"
	var font_size := int(r * 0.24)
	var tc := C_TAG_P if p else C_TAG
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	
	draw_string(font, Vector2(c.x - text_size.x / 2.0, sy + text_size.y * 0.85),
				text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, tc)
