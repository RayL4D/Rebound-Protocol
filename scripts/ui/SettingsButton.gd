# =============================================================
# SettingsButton.gd — Bouton settings : engrenage seul
# Rebound Protocol
# =============================================================
# Pas de cercle, pas de fond — juste l'engrenage cyan.
# Légère opacité au repos, plein + glow au press.
# =============================================================
extends Control

const C_GEAR       := Color(0.00, 0.80, 1.00, 0.75)
const C_GEAR_PRESS := Color(1.00, 1.00, 1.00, 1.00)
const C_GLOW       := Color(0.00, 0.80, 1.00, 1.00)

var _held: bool = false
var _pause_menu: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root: Node = get_parent().get_parent()
	_pause_menu = root.get_node_or_null("PauseMenu")
	if _pause_menu == null:
		push_warning("SettingsButton: PauseMenu introuvable.")


func _gui_input(event: InputEvent) -> void:
	var is_press: bool   = false
	var is_release: bool = false

	if event is InputEventScreenTouch:
		is_press   = (event as InputEventScreenTouch).pressed
		is_release = not (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		is_press   = (event as InputEventMouseButton).pressed
		is_release = not (event as InputEventMouseButton).pressed

	if is_press:
		_held = true
		queue_redraw()
		accept_event()
	elif is_release and _held:
		_held = false
		queue_redraw()
		accept_event()
		if _pause_menu != null and _pause_menu.has_method("_open"):
			_pause_menu._open()


func _draw() -> void:
	var s: Vector2 = size
	var c: Vector2 = s * 0.5
	var r: float   = min(s.x, s.y) * 0.5 - 2.0

	var col: Color = C_GEAR_PRESS if _held else C_GEAR

	# Glow discret derrière l'engrenage au press
	if _held:
		for i: int in 5:
			var a: float = 0.20 - i * 0.04
			draw_arc(c, r * 0.55 + float(i) * 3.0, 0.0, TAU, 48,
					Color(C_GLOW.r, C_GLOW.g, C_GLOW.b, a), 2.0, true)

	# --- Dents ---
	var teeth: int   = 8
	var r_out: float = r
	var r_in:  float = r * 0.72
	var r_hub: float = r * 0.32
	var r_hole:float = r * 0.16
	var tooth_half_angle: float = TAU / float(teeth) * 0.28

	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in teeth:
		var base_angle: float  = TAU / float(teeth) * float(i)
		var a0: float = base_angle - tooth_half_angle
		var a1: float = base_angle + tooth_half_angle
		# Flanc montant (bord intérieur → bord extérieur)
		pts.append(c + Vector2(cos(a0), sin(a0)) * r_in)
		pts.append(c + Vector2(cos(a0), sin(a0)) * r_out)
		pts.append(c + Vector2(cos(a1), sin(a1)) * r_out)
		pts.append(c + Vector2(cos(a1), sin(a1)) * r_in)
		# Remplissage de la base entre deux dents
		var a2: float = base_angle + tooth_half_angle
		var a3: float = base_angle + TAU / float(teeth) - tooth_half_angle
		var steps: int = 4
		for j: int in steps + 1:
			var t: float = float(j) / float(steps)
			var a: float = lerp(a2, a3, t)
			pts.append(c + Vector2(cos(a), sin(a)) * r_in)

	draw_colored_polygon(pts, col)

	# --- Moyeu (disque central) ---
	draw_circle(c, r_hub, col)

	# --- Trou central ---
	draw_circle(c, r_hole, Color(0.0, 0.0, 0.0, 0.0))
	# On redessine le trou en effaçant avec la couleur transparente via arc épais
	draw_arc(c, r_hole * 0.5, 0.0, TAU, 32,
			Color(0.02, 0.05, 0.12, 1.0) if not _held else Color(0.0, 0.5, 0.8, 1.0),
			r_hole * 1.1, true)
