# =============================================================
# cursor.gd — Réticule cyberpunk animé (PC uniquement)
# Rebound Protocol
# S'instancie depuis arena_base.gd, se nettoie à la sortie de scène.
# =============================================================
extends CanvasLayer

# --- Classe interne de dessin ---
class _CursorDraw extends Control:
	const C_CYAN  := Color(0.0, 0.851, 1.0)
	const C_WHITE := Color(1.0, 1.0, 1.0)
	const C_ORNG  := Color(1.0, 0.42, 0.0)

	var _t: float = 0.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter    = Control.MOUSE_FILTER_IGNORE
		process_mode    = Node.PROCESS_MODE_ALWAYS   # actif même en pause

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var mp := get_global_mouse_position()

		# ── Pulse principal ──────────────────────────────────────
		var pulse:  float = sin(_t * 3.8) * 0.5 + 0.5   # 0..1
		var ring_r: float = 13.0 + pulse * 3.5
		var ring_a: float = 0.60 + pulse * 0.30

		# ── Halos de lueur ──────────────────────────────────────
		draw_circle(mp, ring_r + 9.0, Color(C_CYAN, 0.04))
		draw_circle(mp, ring_r + 5.0, Color(C_CYAN, 0.09))
		draw_circle(mp, ring_r + 2.0, Color(C_CYAN, 0.14))

		# ── Anneau principal ────────────────────────────────────
		draw_arc(mp, ring_r, 0.0, TAU, 64, Color(C_CYAN, ring_a), 1.3)

		# ── 4 encoches sur l'anneau (style HUD sci-fi) ──────────
		for i in 4:
			var angle: float = TAU * float(i) / 4.0
			var inner := mp + Vector2(cos(angle), sin(angle)) * (ring_r - 3.0)
			var outer := mp + Vector2(cos(angle), sin(angle)) * (ring_r + 3.0)
			draw_line(inner, outer, Color(C_WHITE, 0.70), 1.8)

		# ── Branches du réticule (croix avec gap central) ───────
		var gap:    float = 5.5
		var length: float = 10.0
		var lw:     float = 1.5
		var la:     float = 0.88
		# Haut
		draw_line(mp + Vector2(0.0, -gap),          mp + Vector2(0.0, -(gap + length)), Color(C_CYAN, la), lw)
		# Bas
		draw_line(mp + Vector2(0.0,  gap),          mp + Vector2(0.0,  gap + length),   Color(C_CYAN, la), lw)
		# Gauche
		draw_line(mp + Vector2(-gap, 0.0),          mp + Vector2(-(gap + length), 0.0), Color(C_CYAN, la), lw)
		# Droite
		draw_line(mp + Vector2( gap, 0.0),          mp + Vector2( gap + length,  0.0),  Color(C_CYAN, la), lw)

		# ── Tirets diagonaux (coins à 45°) ──────────────────────
		var diag_r:   float = ring_r * 0.68
		var diag_len: float = 4.5
		for i in 4:
			var angle: float  = TAU * float(i) / 4.0 + PI * 0.25
			var inner := mp + Vector2(cos(angle), sin(angle)) * diag_r
			var outer := mp + Vector2(cos(angle), sin(angle)) * (diag_r + diag_len)
			draw_line(inner, outer, Color(C_CYAN, 0.45), 1.1)

		# ── Point central ───────────────────────────────────────
		draw_circle(mp, 2.8, Color(C_CYAN, 0.20))   # halo doux
		draw_circle(mp, 1.6, Color(C_WHITE, 0.95))
		draw_circle(mp, 0.9, Color(C_CYAN,  1.0))

		# ── Flash orange sur parade critique (via signal) ────────
		# (réservé pour extension future)


# =============================================================
# LIFECYCLE DU CANVASLAYER
# =============================================================

func _ready() -> void:
	layer = 128   # au-dessus de tout le HUD
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	var draw := _CursorDraw.new()
	add_child(draw)


func _exit_tree() -> void:
	# Remettre le curseur système à la sortie de scène
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
