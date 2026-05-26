# =============================================================
# main_menu.gd — Menu principal animé v4
# Rebound Protocol
# =============================================================
extends Control

@onready var btn_new_game        = $CenterContainer/MainVBox/ButtonsVBox/BtnNewGame
@onready var btn_continue        = $CenterContainer/MainVBox/ButtonsVBox/BtnContinue
@onready var btn_coop            = $CenterContainer/MainVBox/ButtonsVBox/BtnCoop
@onready var btn_options         = $CenterContainer/MainVBox/ButtonsVBox/BtnOptions
@onready var btn_quit            = $CenterContainer/MainVBox/ButtonsVBox/BtnQuit
@onready var btn_credits         = $CenterContainer/MainVBox/ButtonsVBox/BtnCredits
@onready var btn_toggle_language = $CenterContainer/MainVBox/LanguageVBox/BtnToggleLanguage
@onready var flags_container     = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer
@onready var btn_flag_fr         = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer/BtnFlagFR
@onready var btn_flag_en         = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer/BtnFlagEN
@onready var btn_flag_es         = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer/BtnFlagES
@onready var _title_label        = $CenterContainer/MainVBox/TitlesVBox/TitleLabel
@onready var _subtitle_label     = $CenterContainer/MainVBox/TitlesVBox/SubtitleLabel
@onready var _bg_rect            = $Background

const _SFX_HOVER: AudioStream = preload("res://audio/sfx/ui/btn_hover.wav")
const _SFX_CLICK: AudioStream = preload("res://audio/sfx/ui/btn_click.wav")
const FONT_PATH                := "res://ui_theme/fonts/Xolonium-Regular.ttf"

const COLOR_CYAN := Color(0.0, 0.851, 1.0)

var _sfx_player:   AudioStreamPlayer = null
var _font:         FontFile           = null
var _status_label: Label              = null
var _signal_label: Label              = null
var _status_blink: float = 0.0
var _signal_timer: float = 0.0
var _signal_level: int   = 4
var _pulse_timer:  float = 8.0


# =============================================================
# FOND ANIMÉ
# =============================================================

class _BgFX extends Control:
	const C_CYAN := Color(0.0, 0.851, 1.0)
	const C_DARK := Color(0.025, 0.045, 0.075)
	const C_PINK := Color(1.0, 0.15, 0.65)
	const C_PURP := Color(0.55, 0.0, 1.0)

	# --- Timers et états internes ---
	var _t:               float = 0.0
	var _scan_y:          float = 0.0
	var _pulse_a:         float = 0.0
	var _pulse_cd:        float = 8.0

	# --- Parallaxe souris ---
	var _mouse_px: float = 0.5
	var _mouse_py: float = 0.5

	# --- Particules et effets ---
	var _stars:           Array = []
	var _pts:             Array = []
	var _streaks:         Array = []
	var _streak_timer:    float = 0.2
	var _glitches:        Array = []
	var _glitch_timer:    float = 3.0
	var _data_lines:      Array = []
	var _arcs:            Array = []
	var _arc_timer:       float = 5.0
	var _rings:           Array = []
	var _ring_timer:      float = 2.5
	var _active_hexes:    Array = []
	var _hex_spawn_timer: float = 0.8
	var _nebulae:         Array = []
	var _shoot_stars:     Array = []
	var _shoot_timer:     float = 3.5

	# ─────────────────────────────────────────────────────────
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Étoiles scintillantes (positions fixes, phase individuelle)
		var srng := RandomNumberGenerator.new()
		srng.seed = 98765
		for _i in 120:
			_stars.append({
				"x": srng.randf(), "y": srng.randf() * 0.56,
				"r": srng.randf_range(0.5, 2.0),
				"a": srng.randf_range(0.25, 0.85),
				"phase": srng.randf() * TAU,
				"freq":  srng.randf_range(0.2, 1.8),
				"par":   srng.randf_range(0.005, 0.025),  # force de parallaxe individuelle
			})

		# Particules flottantes
		for _i in 70:
			_pts.append({
				"x": randf(), "y": randf(),
				"vy": randf_range(0.007, 0.020),
				"r":  randf_range(1.2, 3.2),
				"a":  randf_range(0.15, 0.75),
			})

		# Nébuleuses atmosphériques
		var nrng := RandomNumberGenerator.new()
		nrng.seed = 11223
		for _i in 5:
			_nebulae.append({
				"x":     nrng.randf_range(0.12, 0.88),
				"y":     nrng.randf_range(0.06, 0.52),
				"r":     nrng.randf_range(0.11, 0.21),
				"phase": nrng.randf() * TAU,
				"freq":  nrng.randf_range(0.07, 0.22),
				"purple": nrng.randf() > 0.55,
				"par":   nrng.randf_range(0.012, 0.028),
			})

		# Longueurs du panneau de données (précompilées)
		var drng := RandomNumberGenerator.new()
		drng.seed = 54321
		for _i in 14:
			_data_lines.append(drng.randf_range(0.04, 0.13))

	# ─────────────────────────────────────────────────────────
	func _process(delta: float) -> void:
		_t      += delta
		_scan_y  = fmod(_scan_y + delta * 48.0, 8.0)

		# Suivi de la souris pour le parallaxe (lissé)
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if vs.x > 0.0:
			_mouse_px = lerpf(_mouse_px, mp.x / vs.x, delta * 2.2)
			_mouse_py = lerpf(_mouse_py, mp.y / vs.y, delta * 2.2)

		# Pulse global
		_pulse_cd -= delta
		if _pulse_cd <= 0.0:
			_pulse_cd = randf_range(5.0, 12.0)
			_pulse_a  = 0.07
		elif _pulse_a > 0.0:
			_pulse_a = maxf(_pulse_a - delta * 0.28, 0.0)

		# Particules flottantes
		for p in _pts:
			p["y"] = float(p["y"]) - float(p["vy"]) * delta
			if float(p["y"]) < -0.02:
				p["y"] = 1.02
				p["x"] = randf()

		# Étoiles filantes
		_shoot_timer -= delta
		if _shoot_timer <= 0.0:
			_shoot_timer = randf_range(2.5, 8.0)
			_shoot_stars.append({
				"x":   randf_range(0.0, 0.75),
				"y":   randf_range(0.02, 0.42),
				"dx":  randf_range(0.22, 0.48),
				"dy":  randf_range(0.04, 0.14),
				"t":   0.0,
				"dur": randf_range(0.40, 0.85),
				"len": randf_range(0.05, 0.13),
			})
		var ssi := 0
		while ssi < _shoot_stars.size():
			_shoot_stars[ssi]["t"] = float(_shoot_stars[ssi]["t"]) + delta
			if float(_shoot_stars[ssi]["t"]) >= float(_shoot_stars[ssi]["dur"]):
				_shoot_stars.remove_at(ssi)
			else:
				ssi += 1

		# Data streaks
		_streak_timer -= delta
		if _streak_timer <= 0.0:
			_streak_timer = randf_range(0.08, 0.55)
			_streaks.append({
				"y": randf_range(0.05, 0.92), "x": 0.0,
				"len": randf_range(0.04, 0.22),
				"spd": randf_range(0.4, 1.1),
				"a":   randf_range(0.4, 0.95),
				"th":  randf_range(0.8, 2.0),
			})
		var si := 0
		while si < _streaks.size():
			_streaks[si]["x"] = float(_streaks[si]["x"]) + float(_streaks[si]["spd"]) * delta
			if float(_streaks[si]["x"]) > 1.1:
				_streaks.remove_at(si)
			else:
				si += 1

		# Glitch rectangles
		_glitch_timer -= delta
		if _glitch_timer <= 0.0:
			_glitch_timer = randf_range(1.5, 4.5)
			for _i in randi_range(2, 6):
				_glitches.append({
					"x": randf(), "y": randf() * 0.82,
					"w": randf_range(0.03, 0.22),
					"h": randf_range(0.003, 0.008),
					"life": randf_range(0.04, 0.12),
					"cyan": randf() > 0.35,
				})
		var gi := 0
		while gi < _glitches.size():
			_glitches[gi]["life"] = float(_glitches[gi]["life"]) - delta
			if float(_glitches[gi]["life"]) <= 0.0:
				_glitches.remove_at(gi)
			else:
				gi += 1

		# Arcs électriques
		_arc_timer -= delta
		if _arc_timer <= 0.0:
			_arc_timer = randf_range(3.0, 7.0)
			_spawn_arc()
		var ai := 0
		while ai < _arcs.size():
			_arcs[ai]["life"] = float(_arcs[ai]["life"]) - delta
			if float(_arcs[ai]["life"]) <= 0.0:
				_arcs.remove_at(ai)
			else:
				ai += 1

		# Anneaux d'énergie
		_ring_timer -= delta
		if _ring_timer <= 0.0:
			_ring_timer = randf_range(1.8, 3.5)
			_rings.append({"r": 0.0, "a": 0.55, "spd": randf_range(0.18, 0.34)})
		var ri := 0
		while ri < _rings.size():
			_rings[ri]["r"] = float(_rings[ri]["r"]) + float(_rings[ri]["spd"]) * delta
			_rings[ri]["a"] = float(_rings[ri]["a"]) - delta * 0.42
			if float(_rings[ri]["a"]) <= 0.0:
				_rings.remove_at(ri)
			else:
				ri += 1

		# Hexagones actifs
		_hex_spawn_timer -= delta
		if _hex_spawn_timer <= 0.0:
			_hex_spawn_timer = randf_range(0.25, 1.1)
			_active_hexes.append({
				"ci": randi_range(0, 24), "row": randi_range(0, 6),
				"life": 0.0,
				"max_life": randf_range(0.6, 1.8),
			})
		var hi := 0
		while hi < _active_hexes.size():
			_active_hexes[hi]["life"] = float(_active_hexes[hi]["life"]) + delta
			if float(_active_hexes[hi]["life"]) >= float(_active_hexes[hi]["max_life"]):
				_active_hexes.remove_at(hi)
			else:
				hi += 1

		queue_redraw()

	func _spawn_arc() -> void:
		var s := get_viewport_rect().size
		if s.x < 1.0:
			return
		var pts := PackedVector2Array()
		var x: float = randf() * s.x
		var y: float = randf_range(0.04, 0.38) * s.y
		pts.append(Vector2(x, y))
		for _i in randi_range(4, 8):
			x = clampf(x + randf_range(-90.0, 90.0), 0.0, s.x)
			y += randf_range(25.0, 75.0)
			pts.append(Vector2(x, y))
		_arcs.append({
			"pts":  pts,
			"life": randf_range(0.06, 0.18),
			"a":    randf_range(0.5, 0.9),
		})

	# ─────────────────────────────────────────────────────────
	func _draw() -> void:
		var s := get_viewport_rect().size
		if s.x < 1.0:
			return
		_draw_bg(s)
		_draw_nebula(s)
		_draw_center_glow(s)
		_draw_shoot_stars(s)
		_draw_hexgrid(s)
		_draw_grid(s)
		_draw_rings(s)
		_draw_scanlines(s)
		_draw_arcs_fx(s)
		_draw_streaks_fx(s)
		_draw_glitch_fx(s)
		_draw_particles(s)
		_draw_horizon(s)
		_draw_data_panel(s)
		_draw_vignette(s)
		_draw_accents(s)
		# Pulse plein-écran en dernier (par-dessus tout)
		if _pulse_a > 0.0:
			draw_rect(Rect2(Vector2.ZERO, s), Color(C_CYAN, _pulse_a))

	func _draw_bg(s: Vector2) -> void:
		draw_rect(Rect2(Vector2.ZERO, s), C_DARK)
		for i in 32:
			var frac := float(i) / 32.0
			draw_rect(Rect2(0.0, frac * s.y * 0.65, s.x, s.y * 0.65 / 32.0),
				Color(0.0, 0.32 * (1.0 - frac), 0.52 * (1.0 - frac), 0.055))
		# Étoiles scintillantes avec parallaxe individuelle
		var base_par_x: float = (_mouse_px - 0.5) * s.x
		var base_par_y: float = (_mouse_py - 0.5) * s.y
		for star in _stars:
			var par:  float = float(star["par"])
			var sx:   float = float(star["x"]) * s.x + base_par_x * par
			var sy:   float = float(star["y"]) * s.y + base_par_y * par * 0.55
			var sr:   float = float(star["r"])
			var sa:   float = float(star["a"]) * (0.45 + sin(_t * float(star["freq"]) + float(star["phase"])) * 0.42)
			draw_circle(Vector2(sx, sy), sr, Color(1.0, 1.0, 1.0, maxf(sa, 0.0)))

	func _draw_nebula(s: Vector2) -> void:
		var bpx: float = (_mouse_px - 0.5) * s.x
		var bpy: float = (_mouse_py - 0.5) * s.y
		for neb in _nebulae:
			var nx:     float = float(neb["x"]) * s.x + bpx * float(neb["par"])
			var ny:     float = float(neb["y"]) * s.y + bpy * float(neb["par"]) * 0.55
			var nr:     float = float(neb["r"]) * s.x
			var phase:  float = float(neb["phase"])
			var freq:   float = float(neb["freq"])
			var is_pur: bool  = neb["purple"]
			var a:      float = 0.010 + sin(_t * freq + phase) * 0.004
			var col:    Color = C_PURP if is_pur else C_CYAN
			for j in 10:
				var frac: float = float(j) / 9.0
				draw_circle(Vector2(nx, ny), maxf(nr * (1.0 - frac * 0.88), 1.0), Color(col, a * frac * 0.5 + a * 0.5))

	func _draw_shoot_stars(s: Vector2) -> void:
		for ss in _shoot_stars:
			var t:    float = float(ss["t"])
			var dur:  float = float(ss["dur"])
			var prog: float = t / dur
			var ox:   float = float(ss["dx"]) * prog
			var oy:   float = float(ss["dy"]) * prog
			var tx:   float = (float(ss["x"]) + ox) * s.x
			var ty:   float = (float(ss["y"]) + oy) * s.y
			var lx:   float = float(ss["len"]) * s.x
			var ang_y: float = float(ss["dy"]) / maxf(float(ss["dx"]), 0.001)
			var ly:   float  = lx * ang_y
			# Fondu entrée/sortie
			var a:    float = sin(prog * PI) * 0.95
			# Queue longue (blanc)
			draw_line(Vector2(tx - lx, ty - ly),        Vector2(tx, ty),
				Color(1.0, 1.0, 1.0, a), 1.5)
			# Queue courte (cyan, plus brillante)
			draw_line(Vector2(tx - lx * 0.35, ty - ly * 0.35), Vector2(tx, ty),
				Color(C_CYAN, a * 0.65), 0.9)
			# Tête lumineuse
			draw_circle(Vector2(tx, ty), 2.0, Color(1.0, 1.0, 1.0, a * 0.85))

	func _draw_center_glow(s: Vector2) -> void:
		var cx: float = s.x * 0.5
		var cy: float = s.y * 0.40
		var base: float = 0.016 + sin(_t * 0.38) * 0.005
		# Cercles concentriques du plus grand au plus petit → accumulation au centre
		for i in 18:
			var frac: float = float(i) / 17.0
			var r:    float = s.x * 0.30 * (1.0 - frac * 0.88)
			draw_circle(Vector2(cx, cy), maxf(r, 1.0), Color(C_CYAN, base * frac))

	func _draw_hexgrid(s: Vector2) -> void:
		var hex_r:  float = 52.0
		var hex_w:  float = hex_r * 2.0
		var hex_h:  float = hex_r * 1.7320508
		var max_y:  float = s.y * 0.56
		var alpha:  float = 0.022 + sin(_t * 0.28) * 0.007
		var cols_n: int   = int(s.x / (hex_w * 0.75)) + 3
		var rows_n: int   = int(max_y / hex_h) + 2
		for row in rows_n:
			for ci in cols_n:
				var cx: float = hex_w * 0.75 * float(ci)
				var cy: float = hex_h * float(row) + (hex_h * 0.5 if ci % 2 == 1 else 0.0)
				if cy >= max_y:
					continue
				# Hex actif ?
				var glow: float = 0.0
				for ah in _active_hexes:
					if int(ah["ci"]) == ci and int(ah["row"]) == row:
						var life:     float = float(ah["life"])
						var max_life: float = float(ah["max_life"])
						glow = sin(life / max_life * PI) * 0.11
						break
				if glow > 0.0:
					_draw_hex_filled(Vector2(cx, cy), hex_r * 0.82, Color(C_CYAN, glow))
				_draw_hex(Vector2(cx, cy), hex_r,
					Color(C_CYAN, alpha + glow * 0.5))

	func _draw_hex(center: Vector2, radius: float, col: Color) -> void:
		var prev := center + Vector2(radius, 0.0)
		for i in 6:
			var angle := TAU * float(i + 1) / 6.0
			var pt    := center + Vector2(cos(angle) * radius, sin(angle) * radius)
			draw_line(prev, pt, col, 0.75)
			prev = pt

	func _draw_hex_filled(center: Vector2, radius: float, col: Color) -> void:
		var pts    := PackedVector2Array()
		var colors := PackedColorArray()
		for i in 6:
			var angle := TAU * float(i) / 6.0
			pts.append(center + Vector2(cos(angle) * radius, sin(angle) * radius))
			colors.append(col)
		draw_polygon(pts, colors)

	func _draw_grid(s: Vector2) -> void:
		var hy:   float = s.y * 0.60
		var vp           := Vector2(s.x * 0.5, hy)
		var base: float  = 0.055 + sin(_t * 0.45) * 0.012
		for i in 20:
			var frac:  float = float(i) / 19.0
			var end_x: float = lerpf(-s.x * 0.12, s.x * 1.12, frac)
			var a:     float = base * (1.0 - absf(frac - 0.5) * 1.6)
			if a > 0.0:
				draw_line(vp, Vector2(end_x, s.y), Color(C_CYAN, a), 1.0)
		for i in 11:
			var frac: float = float(i + 1) / 12.0
			var y:    float = hy + frac * (s.y - hy)
			var a:    float = base * (1.0 - frac * 0.55)
			draw_line(Vector2(0.0, y), Vector2(s.x, y), Color(C_CYAN, a), 1.0)

	func _draw_rings(s: Vector2) -> void:
		var cx: float = s.x * 0.5
		var cy: float = s.y * 0.40
		for ring in _rings:
			var r: float = float(ring["r"]) * s.x * 0.45
			var a: float = float(ring["a"])
			if a > 0.0 and r > 0.0:
				draw_arc(Vector2(cx, cy), r, 0.0, TAU, 72, Color(C_CYAN, a), 1.5)

	func _draw_scanlines(s: Vector2) -> void:
		var y := fmod(_scan_y, 8.0)
		while y < s.y:
			draw_rect(Rect2(0.0, y, s.x, 1.0), Color(0.0, 0.0, 0.0, 0.085))
			y += 8.0

	func _draw_arcs_fx(s: Vector2) -> void:
		for arc in _arcs:
			var pts: PackedVector2Array = arc["pts"]
			var a:   float              = float(arc["a"])
			for i in pts.size() - 1:
				draw_line(pts[i], pts[i + 1], Color(C_CYAN, a),              1.5)
				draw_line(pts[i], pts[i + 1], Color(1.0, 1.0, 1.0, a * 0.4), 0.7)

	func _draw_streaks_fx(s: Vector2) -> void:
		for streak in _streaks:
			var sy:   float = float(streak["y"])   * s.y
			var sx:   float = float(streak["x"])   * s.x
			var xlen: float = float(streak["len"])  * s.x
			var a:    float = float(streak["a"])
			var th:   float = float(streak["th"])
			draw_line(Vector2(maxf(sx - xlen, 0.0), sy), Vector2(sx, sy),
				Color(C_CYAN, a), th)
			draw_line(Vector2(maxf(sx - xlen * 2.0, 0.0), sy),
				Vector2(maxf(sx - xlen, 0.0), sy),
				Color(C_CYAN, a * 0.22), th * 0.65)

	func _draw_glitch_fx(s: Vector2) -> void:
		for g in _glitches:
			var rect     := Rect2(float(g["x"]) * s.x, float(g["y"]) * s.y,
				float(g["w"]) * s.x, float(g["h"]) * s.y)
			var is_cyan: bool = g["cyan"]
			draw_rect(rect, Color(C_CYAN, 0.18) if is_cyan else Color(C_PINK, 0.12))

	func _draw_particles(s: Vector2) -> void:
		for p in _pts:
			var px: float = float(p["x"]) * s.x
			var py: float = float(p["y"]) * s.y
			var a:  float = float(p["a"])
			var r:  float = float(p["r"])
			draw_circle(Vector2(px, py), r,       Color(C_CYAN, a))
			draw_circle(Vector2(px, py), r * 3.0, Color(C_CYAN, a * 0.10))

	func _draw_horizon(s: Vector2) -> void:
		var hy: float = s.y * 0.60
		var a:  float = 0.32 + sin(_t * 0.85) * 0.10
		draw_line(Vector2(0.0, hy), Vector2(s.x, hy), Color(C_CYAN, a), 2.0)
		for i in 6:
			var spread: float = float(i + 1) * 4.0
			draw_line(Vector2(0.0, hy + spread), Vector2(s.x, hy + spread),
				Color(C_CYAN, a * 0.55 / float(i + 1)), 1.5)

	func _draw_data_panel(s: Vector2) -> void:
		var px:   float = s.x * 0.855
		var py:   float = s.y * 0.15
		var lh:   float = 15.0
		var base: float = 0.16 + sin(_t * 0.55) * 0.05
		draw_line(Vector2(px - 5.0, py),
			Vector2(px - 5.0, py + lh * float(_data_lines.size())),
			Color(C_CYAN, base + 0.05), 1.2)
		for i in _data_lines.size():
			var lw:    float = float(_data_lines[i]) * s.x * 0.12
			var phase: float = float(i) * 0.35 + _t * 0.75
			var a:     float = base * (0.55 + sin(phase) * 0.45)
			draw_line(Vector2(px, py + float(i) * lh),
				Vector2(px + lw, py + float(i) * lh),
				Color(C_CYAN, maxf(a, 0.0)), 1.5)

	func _draw_vignette(s: Vector2) -> void:
		for i in 16:
			var frac:  float = float(i) / 16.0
			var alpha: float = (1.0 - frac) * 0.30 / 16.0
			var mx:    float = frac * s.x * 0.40
			var my:    float = frac * s.y * 0.28
			draw_rect(Rect2(0.0,       0.0,      mx, s.y), Color(0, 0, 0, alpha))
			draw_rect(Rect2(s.x - mx,  0.0,      mx, s.y), Color(0, 0, 0, alpha))
			draw_rect(Rect2(0.0,       0.0,      s.x, my), Color(0, 0, 0, alpha * 0.7))
			draw_rect(Rect2(0.0, s.y - my, s.x,   my),     Color(0, 0, 0, alpha * 0.7))

	func _draw_accents(s: Vector2) -> void:
		var a:  float = 0.55 + sin(_t * 1.3) * 0.14
		# Barres top/bottom
		draw_rect(Rect2(0.0, 0.0,       s.x, 2.5), Color(C_CYAN, a))
		draw_rect(Rect2(0.0, 2.5,       s.x, 1.5), Color(C_CYAN, a * 0.20))
		draw_rect(Rect2(0.0, s.y - 2.5, s.x, 2.5), Color(C_CYAN, a * 0.50))
		# Marques latérales (milieu des bords gauche/droit)
		var mid:  float = s.y * 0.5
		var mlen: float = 22.0
		draw_line(Vector2(1.0, mid - mlen), Vector2(1.0, mid + mlen), Color(C_CYAN, a * 0.6), 2.0)
		draw_line(Vector2(s.x - 1.0, mid - mlen), Vector2(s.x - 1.0, mid + mlen), Color(C_CYAN, a * 0.6), 2.0)
		# Crochets de coin pulsants
		var ba:  float = 0.75 + sin(_t * 2.0) * 0.18
		var bc           := Color(C_CYAN, ba)
		var bw:  float = 2.5
		var mx:  float = 32.0
		var my:  float = 24.0
		var arm: float = 52.0
		var sq:  float = 5.0
		# ┌
		draw_line(Vector2(mx, my), Vector2(mx + arm, my), bc, bw)
		draw_line(Vector2(mx, my), Vector2(mx, my + arm), bc, bw)
		draw_rect(Rect2(mx - sq * 0.5, my - sq * 0.5, sq, sq), bc)
		# ┐
		draw_line(Vector2(s.x - mx, my), Vector2(s.x - mx - arm, my), bc, bw)
		draw_line(Vector2(s.x - mx, my), Vector2(s.x - mx, my + arm), bc, bw)
		draw_rect(Rect2(s.x - mx - sq * 0.5, my - sq * 0.5, sq, sq), bc)
		# └
		draw_line(Vector2(mx, s.y - my), Vector2(mx + arm, s.y - my), bc, bw)
		draw_line(Vector2(mx, s.y - my), Vector2(mx, s.y - my - arm), bc, bw)
		draw_rect(Rect2(mx - sq * 0.5, s.y - my - sq * 0.5, sq, sq), bc)
		# ┘
		draw_line(Vector2(s.x - mx, s.y - my), Vector2(s.x - mx - arm, s.y - my), bc, bw)
		draw_line(Vector2(s.x - mx, s.y - my), Vector2(s.x - mx, s.y - my - arm), bc, bw)
		draw_rect(Rect2(s.x - mx - sq * 0.5, s.y - my - sq * 0.5, sq, sq), bc)


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	MusicManager.play("menu")
	flags_container.hide()

	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as FontFile

	_sfx_player     = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)

	_build_background()
	_build_hud_labels()
	_build_title_decorations()

	# SFX sur tous les boutons
	for btn in [btn_new_game, btn_continue, btn_coop, btn_options, btn_quit,
				btn_toggle_language, btn_flag_fr, btn_flag_en, btn_flag_es, btn_credits]:
		btn.mouse_entered.connect(func():
			if _sfx_player and is_inside_tree():
				_sfx_player.stream      = _SFX_HOVER
				_sfx_player.volume_db   = 2.0
				_sfx_player.pitch_scale = randf_range(0.97, 1.03)
				_sfx_player.play()
		)
		btn.pressed.connect(func():
			var p := AudioStreamPlayer.new()
			p.stream      = _SFX_CLICK
			p.bus         = "SFX"
			p.volume_db   = 5.0
			p.pitch_scale = randf_range(0.97, 1.03)
			get_tree().root.add_child(p)
			p.play()
			p.finished.connect(p.queue_free)
		)

	# Hover : couleur + scale + StyleBox glow
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.0, 0.851, 1.0, 0.08)
	hover_style.border_color = Color(0.0, 0.851, 1.0, 0.70)
	hover_style.set_border_width_all(1)
	hover_style.corner_radius_top_left    = 3
	hover_style.corner_radius_top_right   = 3
	hover_style.corner_radius_bottom_left = 3
	hover_style.corner_radius_bottom_right = 3

	for btn in [btn_new_game, btn_continue, btn_coop, btn_options, btn_quit, btn_credits]:
		var b: Button = btn
		b.add_theme_stylebox_override("hover", hover_style)
		b.mouse_entered.connect(func():
			var tw := b.create_tween()
			tw.tween_method(func(c: Color): b.add_theme_color_override("font_color", c),
				COLOR_CYAN, Color(1.0, 1.0, 1.0, 1.0), 0.10)
			tw.parallel().tween_property(b, "scale", Vector2(1.045, 1.045), 0.10)
		)
		b.mouse_exited.connect(func():
			var tw := b.create_tween()
			tw.tween_method(func(c: Color): b.add_theme_color_override("font_color", c),
				Color(1.0, 1.0, 1.0, 1.0), COLOR_CYAN, 0.13)
			tw.parallel().tween_property(b, "scale", Vector2(1.0, 1.0), 0.13)
		)

	Settings.apply_saved_settings()

	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	btn_options.pressed.connect(_on_options_pressed)
	btn_continue.pressed.connect(_on_continue_pressed)
	btn_coop.pressed.connect(_on_coop_pressed)
	btn_credits.pressed.connect(_on_credits_pressed)

	var has_save := false
	for i in SaveData.MAX_SLOTS:
		if SaveData.get_slot_info(i)["used"]:
			has_save = true
			break
	if not has_save:
		btn_continue.disabled = true
		btn_continue.modulate  = Color(0.5, 0.5, 0.5, 0.8)

	btn_toggle_language.pressed.connect(_on_toggle_language_pressed)
	btn_flag_fr.pressed.connect(func(): _change_language("fr"))
	btn_flag_en.pressed.connect(func(): _change_language("en"))
	btn_flag_es.pressed.connect(func(): _change_language("es"))

	call_deferred("_animate_entrance")


func _process(delta: float) -> void:
	_status_blink += delta
	if _status_blink >= 0.85:
		_status_blink = 0.0
	if _status_label:
		_status_label.modulate.a = 1.0 if _status_blink < 0.55 else 0.0

	_signal_timer -= delta
	if _signal_timer <= 0.0:
		_signal_timer = randf_range(1.8, 4.0)
		_signal_level = randi_range(3, 5)
		_update_signal_label()


# =============================================================
# CONSTRUCTION VISUELLE
# =============================================================

func _build_background() -> void:
	_bg_rect.color = Color(0.025, 0.045, 0.075)
	var fx := _BgFX.new()
	add_child(fx)
	move_child(fx, 1)   # entre Background et CenterContainer


func _build_hud_labels() -> void:
	_status_label = Label.new()
	_status_label.text = "▸ SYSTÈME ACTIF"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", COLOR_CYAN)
	if _font:
		_status_label.add_theme_font_override("font", _font)
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status_label.offset_left   =  18.0
	_status_label.offset_top    = -34.0
	_status_label.offset_bottom = -14.0
	_status_label.offset_right  =  220.0
	add_child(_status_label)

	_signal_label = Label.new()
	_signal_label.add_theme_font_size_override("font_size", 12)
	_signal_label.add_theme_color_override("font_color", COLOR_CYAN)
	if _font:
		_signal_label.add_theme_font_override("font", _font)
	_signal_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_signal_label.offset_left   = -210.0
	_signal_label.offset_top    = -34.0
	_signal_label.offset_bottom = -14.0
	_signal_label.offset_right  = -18.0
	_signal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_signal_label)
	_update_signal_label()


func _build_title_decorations() -> void:
	var tbox = $CenterContainer/MainVBox/TitlesVBox

	# Ligne décorative au-dessus du titre
	var deco_top := Label.new()
	deco_top.text = "◈  ━━━━━━━━━━━━━━━━━━━━━━━  ◈"
	deco_top.add_theme_font_size_override("font_size", 13)
	deco_top.add_theme_color_override("font_color", Color(COLOR_CYAN, 0.65))
	deco_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font:
		deco_top.add_theme_font_override("font", _font)
	tbox.add_child(deco_top)
	tbox.move_child(deco_top, 0)

	# Séparateur sous le sous-titre
	var deco_bot := Label.new()
	deco_bot.text = "─  ─  ─  ─  ─  ─  ─  ─  ─  ─  ─"
	deco_bot.add_theme_font_size_override("font_size", 11)
	deco_bot.add_theme_color_override("font_color", Color(COLOR_CYAN, 0.35))
	deco_bot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font:
		deco_bot.add_theme_font_override("font", _font)
	tbox.add_child(deco_bot)

	# Animer les décos avec le reste du titre
	deco_top.modulate.a = 0.0
	deco_bot.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.20)
	tw.tween_property(deco_top, "modulate:a", 1.0, 0.50)
	tw.parallel().tween_property(deco_bot, "modulate:a", 1.0, 0.50)


func _update_signal_label() -> void:
	if _signal_label == null:
		return
	_signal_label.text = "SIGNAL %s%s" % [
		"◆".repeat(_signal_level),
		"◇".repeat(5 - _signal_level)
	]


# =============================================================
# ANIMATIONS D'ENTRÉE
# =============================================================

func _animate_entrance() -> void:
	_title_label.modulate.a    = 0.0
	_subtitle_label.modulate.a = 0.0
	_subtitle_label.visible_ratio = 0.0

	# Titre : fondu + glitch
	var tw_title := create_tween()
	tw_title.tween_property(_title_label, "modulate:a", 1.0, 0.55) \
		.set_trans(Tween.TRANS_QUAD)
	tw_title.tween_callback(_glitch_title)

	# Sous-titre : fondu rapide puis typewriter
	var tw_sub := create_tween()
	tw_sub.tween_interval(0.35)
	tw_sub.tween_property(_subtitle_label, "modulate:a", 1.0, 0.18)
	tw_sub.tween_property(_subtitle_label, "visible_ratio", 1.0, 0.65) \
		.set_trans(Tween.TRANS_LINEAR)

	# Boutons : apparition décalée
	var buttons := [btn_new_game, btn_continue, btn_coop, btn_options, btn_quit, btn_credits]
	for i in buttons.size():
		var btn: Button = buttons[i]
		btn.modulate.a = 0.0
		var btn_tw := create_tween()
		btn_tw.tween_interval(0.55 + float(i) * 0.13)
		btn_tw.tween_property(btn, "modulate:a", 1.0, 0.38)


func _glitch_title() -> void:
	if not is_inside_tree():
		return
	var tw := create_tween()
	for _i in 5:
		tw.tween_property(_title_label, "modulate:a", 0.04, 0.030)
		tw.tween_property(_title_label, "modulate:a", 1.00, 0.055)
	tw.tween_callback(_start_title_pulse)


func _start_title_pulse() -> void:
	if not is_inside_tree():
		return
	var tw := create_tween().set_loops()
	tw.tween_property(_title_label, "modulate",
		Color(0.60, 1.0, 1.0, 1.0), 2.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_title_label, "modulate",
		Color(1.0, 1.0, 1.0, 1.0), 2.2).set_trans(Tween.TRANS_SINE)


# =============================================================
# CALLBACKS
# =============================================================

func _on_coop_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/coop_menu.tscn")

func _on_new_game_pressed() -> void:
	SaveData.new_game_mode = true
	get_tree().change_scene_to_file("res://scenes/ui/slot_select.tscn")

func _on_continue_pressed() -> void:
	SaveData.new_game_mode = false
	get_tree().change_scene_to_file("res://scenes/ui/slot_select.tscn")

func _on_options_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
	
func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/credits.tscn")

func _on_toggle_language_pressed() -> void:
	flags_container.visible = !flags_container.visible

func _change_language(locale: String) -> void:
	TranslationServer.set_locale(locale)
	SceneManager.current_lang = locale
	flags_container.hide()
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("locale", "language", locale)
	cfg.save("user://settings.cfg")
