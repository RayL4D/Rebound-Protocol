extends Control
## Menu coopératif – Lobby créer/rejoindre un salon.
## Style cyberpunk cohérent avec le main menu (BgFX complet, cyan #00D9FF, Xolonium).

# ── Palette (identique au main menu) ─────────────────────────────────────────
const C_BG      := Color(0.025, 0.045, 0.075)
const C_CYAN    := Color(0.0,   0.851, 1.0)
const C_TEXT    := Color(0.88,  0.92,  0.96)
const C_GRAY    := Color(0.40,  0.45,  0.52)
const C_GREEN   := Color(0.18,  0.85,  0.45)
const C_RED     := Color(0.90,  0.25,  0.25)
const C_DARK    := Color(0.012, 0.022, 0.038)
const FONT_PATH := "res://ui_theme/fonts/Xolonium-Regular.ttf"

# ── Fond animé complet (identique au BgFX du main menu) ──────────────────────
class _BgFX extends Control:
	const C_CYAN := Color(0.0, 0.851, 1.0)
	const C_DARK := Color(0.025, 0.045, 0.075)
	const C_PINK := Color(1.0, 0.15, 0.65)
	const C_PURP := Color(0.55, 0.0, 1.0)

	var _t:               float = 0.0
	var _scan_y:          float = 0.0
	var _pulse_a:         float = 0.0
	var _pulse_cd:        float = 8.0
	var _mouse_px:        float = 0.5
	var _mouse_py:        float = 0.5
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

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var srng := RandomNumberGenerator.new()
		srng.seed = 98765
		for _i in 120:
			_stars.append({
				"x": srng.randf(), "y": srng.randf() * 0.56,
				"r": srng.randf_range(0.5, 2.0),
				"a": srng.randf_range(0.25, 0.85),
				"phase": srng.randf() * TAU,
				"freq":  srng.randf_range(0.2, 1.8),
				"par":   srng.randf_range(0.005, 0.025),
			})
		for _i in 70:
			_pts.append({
				"x": randf(), "y": randf(),
				"vy": randf_range(0.007, 0.020),
				"r":  randf_range(1.2, 3.2),
				"a":  randf_range(0.15, 0.75),
			})
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
		var drng := RandomNumberGenerator.new()
		drng.seed = 54321
		for _i in 14:
			_data_lines.append(drng.randf_range(0.04, 0.13))

	func _process(delta: float) -> void:
		_t      += delta
		_scan_y  = fmod(_scan_y + delta * 48.0, 8.0)
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if vs.x > 0.0:
			_mouse_px = lerpf(_mouse_px, mp.x / vs.x, delta * 2.2)
			_mouse_py = lerpf(_mouse_py, mp.y / vs.y, delta * 2.2)
		_pulse_cd -= delta
		if _pulse_cd <= 0.0:
			_pulse_cd = randf_range(5.0, 12.0)
			_pulse_a  = 0.07
		elif _pulse_a > 0.0:
			_pulse_a = maxf(_pulse_a - delta * 0.28, 0.0)
		for p in _pts:
			p["y"] = float(p["y"]) - float(p["vy"]) * delta
			if float(p["y"]) < -0.02:
				p["y"] = 1.02
				p["x"] = randf()
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
		if _pulse_a > 0.0:
			draw_rect(Rect2(Vector2.ZERO, s), Color(C_CYAN, _pulse_a))

	func _draw_bg(s: Vector2) -> void:
		draw_rect(Rect2(Vector2.ZERO, s), C_DARK)
		for i in 32:
			var frac := float(i) / 32.0
			draw_rect(Rect2(0.0, frac * s.y * 0.65, s.x, s.y * 0.65 / 32.0),
				Color(0.0, 0.32 * (1.0 - frac), 0.52 * (1.0 - frac), 0.055))
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
			var a:    float = sin(prog * PI) * 0.95
			draw_line(Vector2(tx - lx, ty - ly),        Vector2(tx, ty), Color(1.0, 1.0, 1.0, a), 1.5)
			draw_line(Vector2(tx - lx * 0.35, ty - ly * 0.35), Vector2(tx, ty), Color(C_CYAN, a * 0.65), 0.9)
			draw_circle(Vector2(tx, ty), 2.0, Color(1.0, 1.0, 1.0, a * 0.85))

	func _draw_center_glow(s: Vector2) -> void:
		var cx: float = s.x * 0.5
		var cy: float = s.y * 0.40
		var base: float = 0.016 + sin(_t * 0.38) * 0.005
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
				var glow: float = 0.0
				for ah in _active_hexes:
					if int(ah["ci"]) == ci and int(ah["row"]) == row:
						var life:     float = float(ah["life"])
						var max_life: float = float(ah["max_life"])
						glow = sin(life / max_life * PI) * 0.11
						break
				if glow > 0.0:
					_draw_hex_filled(Vector2(cx, cy), hex_r * 0.82, Color(C_CYAN, glow))
				_draw_hex(Vector2(cx, cy), hex_r, Color(C_CYAN, alpha + glow * 0.5))

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
			draw_line(Vector2(maxf(sx - xlen, 0.0), sy), Vector2(sx, sy), Color(C_CYAN, a), th)
			draw_line(Vector2(maxf(sx - xlen * 2.0, 0.0), sy), Vector2(maxf(sx - xlen, 0.0), sy),
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
		draw_rect(Rect2(0.0, 0.0,       s.x, 2.5), Color(C_CYAN, a))
		draw_rect(Rect2(0.0, 2.5,       s.x, 1.5), Color(C_CYAN, a * 0.20))
		draw_rect(Rect2(0.0, s.y - 2.5, s.x, 2.5), Color(C_CYAN, a * 0.50))
		var mid:  float = s.y * 0.5
		var mlen: float = 22.0
		draw_line(Vector2(1.0, mid - mlen), Vector2(1.0, mid + mlen), Color(C_CYAN, a * 0.6), 2.0)
		draw_line(Vector2(s.x - 1.0, mid - mlen), Vector2(s.x - 1.0, mid + mlen), Color(C_CYAN, a * 0.6), 2.0)
		var ba:  float = 0.75 + sin(_t * 2.0) * 0.18
		var bc           := Color(C_CYAN, ba)
		var bw:  float = 2.5
		var mx:  float = 32.0
		var my:  float = 24.0
		var arm: float = 52.0
		var sq:  float = 5.0
		draw_line(Vector2(mx, my), Vector2(mx + arm, my), bc, bw)
		draw_line(Vector2(mx, my), Vector2(mx, my + arm), bc, bw)
		draw_rect(Rect2(mx - sq * 0.5, my - sq * 0.5, sq, sq), bc)
		draw_line(Vector2(s.x - mx, my), Vector2(s.x - mx - arm, my), bc, bw)
		draw_line(Vector2(s.x - mx, my), Vector2(s.x - mx, my + arm), bc, bw)
		draw_rect(Rect2(s.x - mx - sq * 0.5, my - sq * 0.5, sq, sq), bc)
		draw_line(Vector2(mx, s.y - my), Vector2(mx + arm, s.y - my), bc, bw)
		draw_line(Vector2(mx, s.y - my), Vector2(mx, s.y - my - arm), bc, bw)
		draw_rect(Rect2(mx - sq * 0.5, s.y - my - sq * 0.5, sq, sq), bc)
		draw_line(Vector2(s.x - mx, s.y - my), Vector2(s.x - mx - arm, s.y - my), bc, bw)
		draw_line(Vector2(s.x - mx, s.y - my), Vector2(s.x - mx, s.y - my - arm), bc, bw)
		draw_rect(Rect2(s.x - mx - sq * 0.5, s.y - my - sq * 0.5, sq, sq), bc)


# ── État ──────────────────────────────────────────────────────────────────────
enum Screen   { MAIN, LOBBY }
enum JoinMode { CODE, IP }
var _screen:    Screen   = Screen.MAIN
var _join_mode: JoinMode = JoinMode.CODE

var _lbl_status:    Label
var _lbl_code:      Label
var _lbl_lan_ip:    Label
var _lbl_players:   VBoxContainer
var _btn_start:     Button
var _lbl_wait:      Label
var _entry_name:      LineEdit
var _entry_code:      LineEdit   # rejoindre par code relay
var _entry_ip:        LineEdit   # rejoindre par IP directe
var _panel_main:    Control
var _panel_lobby:   Control
var _panel_code:    VBoxContainer
var _panel_ip:      VBoxContainer
var _font:          FontFile = null
var _content_root:  Control
var _btn_copy:      Button


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as FontFile
	_build_ui()
	_show_main()
	call_deferred("_animate_entrance")
	NetworkManager.room_code_ready.connect(_on_room_code_ready)
	NetworkManager.connection_success.connect(_on_connection_success)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.players_updated.connect(_on_players_updated)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.relay_awake.connect(_on_relay_awake)
	# Réveille le relay dès l'ouverture (Render free tier peut dormir)
	_set_status("Connexion au serveur relay…", false)
	NetworkManager.ping_relay()


func _exit_tree() -> void:
	if NetworkManager.room_code_ready.is_connected(_on_room_code_ready):
		NetworkManager.room_code_ready.disconnect(_on_room_code_ready)
	if NetworkManager.connection_success.is_connected(_on_connection_success):
		NetworkManager.connection_success.disconnect(_on_connection_success)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.players_updated.is_connected(_on_players_updated):
		NetworkManager.players_updated.disconnect(_on_players_updated)
	if NetworkManager.game_started.is_connected(_on_game_started):
		NetworkManager.game_started.disconnect(_on_game_started)
	if NetworkManager.relay_awake.is_connected(_on_relay_awake):
		NetworkManager.relay_awake.disconnect(_on_relay_awake)


# ── Animation d'entrée ────────────────────────────────────────────────────────
func _animate_entrance() -> void:
	if _content_root == null or not is_inside_tree():
		return
	_content_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_content_root, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD)


# ── Construction UI ────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Fond
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Animation de fond complète (identique au main menu)
	var fx := _BgFX.new()
	add_child(fx)

	# Conteneur centré
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(540, 0)
	root.add_theme_constant_override("separation", 0)
	center.add_child(root)
	_content_root = root

	# ── En-tête ──────────────────────────────────────────────────────────────
	var deco_top := _make_deco_label("◈  ━━━━━━━━━━━━━━━━━━━━━━━━━━━  ◈")
	root.add_child(deco_top)
	_add_spacer(root, 6)

	var title := Label.new()
	title.text = "CO-OP EN LIGNE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", C_CYAN)
	if _font: title.add_theme_font_override("font", _font)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "MODE SURVIE — VAGUES INFINIES"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(C_CYAN, 0.5))
	if _font: subtitle.add_theme_font_override("font", _font)
	root.add_child(subtitle)
	_add_spacer(root, 6)

	var deco_bot := _make_deco_label("─  ─  ─  ─  ─  ─  ─  ─  ─  ─  ─  ─")
	root.add_child(deco_bot)
	_add_spacer(root, 22)

	# ── Panneaux ─────────────────────────────────────────────────────────────
	_panel_main  = _make_panel()
	root.add_child(_panel_main)
	_build_main_panel()

	_add_spacer(root, 14)

	_panel_lobby = _make_panel()
	_panel_lobby.visible = false
	root.add_child(_panel_lobby)
	_build_lobby_panel()

	# ── Bouton retour ─────────────────────────────────────────────────────────
	_add_spacer(root, 18)
	var btn_back := _make_menu_button("← RETOUR AU MENU")
	btn_back.pressed.connect(_on_back_pressed)
	root.add_child(btn_back)

	# ── Label de statut en bas ────────────────────────────────────────────────
	_add_spacer(root, 10)
	_lbl_status = Label.new()
	_lbl_status.text = ""
	_lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lbl_status.add_theme_color_override("font_color", C_RED)
	_lbl_status.add_theme_font_size_override("font_size", 13)
	if _font: _lbl_status.add_theme_font_override("font", _font)
	root.add_child(_lbl_status)


func _build_main_panel() -> void:
	var vb: VBoxContainer = _panel_main.get_child(0)

	# ── Section RÉSEAU ───────────────────────────────────────────────────────
	# ── Section CRÉER ────────────────────────────────────────────────────────
	_add_section_header(vb, "▸ CRÉER UN SALON")
	_add_spacer(vb, 10)

	_add_field_label(vb, "TON NOM DE JOUEUR")
	_add_spacer(vb, 5)
	_entry_name = _make_line_edit("John Doe", 20)
	vb.add_child(_entry_name)
	_add_spacer(vb, 12)

	var btn_host := _make_action_button("CRÉER EN LIGNE  ◆", C_CYAN)
	btn_host.pressed.connect(_on_host_pressed)
	vb.add_child(btn_host)

	_add_spacer(vb, 6)

	var btn_host_lan := _make_action_button("CRÉER EN LAN (même réseau)  ◈", Color(0.18, 0.78, 0.58))
	btn_host_lan.pressed.connect(_on_host_lan_pressed)
	vb.add_child(btn_host_lan)

	# ── Séparateur ───────────────────────────────────────────────────────────
	_add_spacer(vb, 20)
	var sep_row := HBoxContainer.new()
	sep_row.add_theme_constant_override("separation", 10)
	var sep_l := HSeparator.new()
	sep_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep_l.add_theme_color_override("color", Color(C_CYAN, 0.20))
	var sep_lbl := Label.new()
	sep_lbl.text = "OU"
	sep_lbl.add_theme_font_size_override("font_size", 11)
	sep_lbl.add_theme_color_override("font_color", Color(C_CYAN, 0.45))
	if _font: sep_lbl.add_theme_font_override("font", _font)
	var sep_r := HSeparator.new()
	sep_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep_r.add_theme_color_override("color", Color(C_CYAN, 0.20))
	sep_row.add_child(sep_l)
	sep_row.add_child(sep_lbl)
	sep_row.add_child(sep_r)
	vb.add_child(sep_row)
	_add_spacer(vb, 20)

	# ── Section REJOINDRE ────────────────────────────────────────────────────
	_add_section_header(vb, "▸ REJOINDRE UN SALON")
	_add_spacer(vb, 12)

	# Sélecteur CODE / IP
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	vb.add_child(join_row)

	var btn_by_code := _make_action_button("PAR CODE", C_CYAN)
	var btn_by_ip   := _make_action_button("PAR IP DIRECTE", Color(0.18, 0.78, 0.58))
	btn_by_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_by_ip.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	btn_by_ip.modulate.a = 0.55
	btn_by_code.pressed.connect(func(): _set_join_mode(JoinMode.CODE, btn_by_code, btn_by_ip))
	btn_by_ip.pressed.connect(func():   _set_join_mode(JoinMode.IP,   btn_by_code, btn_by_ip))
	join_row.add_child(btn_by_code)
	join_row.add_child(btn_by_ip)
	_add_spacer(vb, 12)

	# Panneau PAR CODE
	_panel_code = VBoxContainer.new()
	_panel_code.add_theme_constant_override("separation", 0)
	vb.add_child(_panel_code)

	_add_field_label(_panel_code, "CODE DU SALON  (6 CARACTÈRES)")
	_add_spacer(_panel_code, 5)
	_entry_code = _make_line_edit("ABC123", 6)
	_entry_code.text = ""
	_panel_code.add_child(_entry_code)
	_add_spacer(_panel_code, 10)

	var btn_join_code := _make_action_button("REJOINDRE  →", Color(0.0, 0.55, 0.22))
	btn_join_code.pressed.connect(_on_join_pressed)
	_panel_code.add_child(btn_join_code)

	# Panneau PAR IP
	_panel_ip = VBoxContainer.new()
	_panel_ip.add_theme_constant_override("separation", 0)
	_panel_ip.visible = false
	vb.add_child(_panel_ip)

	_add_field_label(_panel_ip, "IP DE L'HÔTE  (ex : 192.168.1.89)")
	_add_spacer(_panel_ip, 5)
	_entry_ip = _make_line_edit("192.168.1.x", 64)
	_entry_ip.text = ""
	_panel_ip.add_child(_entry_ip)
	_add_spacer(_panel_ip, 10)
	var btn_join_ip := _make_action_button("REJOINDRE  →", Color(0.0, 0.55, 0.22))
	btn_join_ip.pressed.connect(_on_join_lan_pressed)
	_panel_ip.add_child(btn_join_ip)


func _build_lobby_panel() -> void:
	var vb: VBoxContainer = _panel_lobby.get_child(0)

	# ── Code du salon ────────────────────────────────────────────────────────
	_add_section_header(vb, "▸ CODE DU SALON")
	_add_spacer(vb, 12)

	var code_box := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = C_DARK
	cs.border_color = Color(C_CYAN, 0.6)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(4)
	cs.set_content_margin_all(16)
	code_box.add_theme_stylebox_override("panel", cs)
	vb.add_child(code_box)

	var code_inner := VBoxContainer.new()
	code_inner.add_theme_constant_override("separation", 4)
	code_box.add_child(code_inner)

	_lbl_code = Label.new()
	_lbl_code.text = "------"
	_lbl_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_code.add_theme_font_size_override("font_size", 48)
	_lbl_code.add_theme_color_override("font_color", C_CYAN)
	if _font: _lbl_code.add_theme_font_override("font", _font)
	code_inner.add_child(_lbl_code)

	var lbl_hint := Label.new()
	lbl_hint.text = "Partage ce code ou cette IP avec ton ami"
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.add_theme_color_override("font_color", Color(C_CYAN, 0.40))
	lbl_hint.add_theme_font_size_override("font_size", 11)
	if _font: lbl_hint.add_theme_font_override("font", _font)
	code_inner.add_child(lbl_hint)

	_add_spacer(code_inner, 8)

	# IP LAN toujours visible en dessous (utile pour rejoindre par IP directe)
	var lbl_lan_row := HBoxContainer.new()
	lbl_lan_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lbl_lan_row.add_theme_constant_override("separation", 6)
	code_inner.add_child(lbl_lan_row)

	var lbl_ip_prefix := Label.new()
	lbl_ip_prefix.text = "IP LAN :"
	lbl_ip_prefix.add_theme_font_size_override("font_size", 12)
	lbl_ip_prefix.add_theme_color_override("font_color", Color(C_CYAN, 0.35))
	if _font: lbl_ip_prefix.add_theme_font_override("font", _font)
	lbl_lan_row.add_child(lbl_ip_prefix)

	_lbl_lan_ip = Label.new()
	_lbl_lan_ip.text = NetworkManager.get_lan_ip()
	_lbl_lan_ip.add_theme_font_size_override("font_size", 12)
	_lbl_lan_ip.add_theme_color_override("font_color", Color(C_CYAN, 0.75))
	if _font: _lbl_lan_ip.add_theme_font_override("font", _font)
	lbl_lan_row.add_child(_lbl_lan_ip)

	# ── Bouton Copier le code ─────────────────────────────────────────────────
	_add_spacer(vb, 8)
	_btn_copy = _make_action_button("⎘  COPIER LE CODE", C_CYAN)
	_btn_copy.pressed.connect(_on_copy_pressed)
	vb.add_child(_btn_copy)

	_add_spacer(vb, 22)

	# ── Joueurs connectés ────────────────────────────────────────────────────
	_add_section_header(vb, "▸ JOUEURS CONNECTÉS")
	_add_spacer(vb, 10)

	_lbl_players = VBoxContainer.new()
	_lbl_players.add_theme_constant_override("separation", 6)
	vb.add_child(_lbl_players)

	# Slots vides par défaut
	_rebuild_player_slots({})

	_add_spacer(vb, 22)

	# ── Actions ──────────────────────────────────────────────────────────────
	_btn_start = _make_action_button("LANCER LA PARTIE  ▶", C_CYAN)
	_btn_start.visible = false
	_btn_start.pressed.connect(_on_start_pressed)
	vb.add_child(_btn_start)

	_lbl_wait = Label.new()
	_lbl_wait.text = "En attente que l'hôte lance la partie…"
	_lbl_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_wait.add_theme_color_override("font_color", Color(C_CYAN, 0.50))
	_lbl_wait.add_theme_font_size_override("font_size", 13)
	if _font: _lbl_wait.add_theme_font_override("font", _font)
	_lbl_wait.visible = false
	vb.add_child(_lbl_wait)


# ── Changement d'écran ────────────────────────────────────────────────────────
func _show_main() -> void:
	_screen = Screen.MAIN
	_panel_main.visible = true
	_panel_lobby.visible = false


func _show_lobby() -> void:
	_screen = Screen.LOBBY
	_panel_main.visible = false
	_panel_lobby.visible = true
	_lbl_code.text = NetworkManager.room_code if NetworkManager.room_code != "" else "------"
	if _lbl_lan_ip != null:
		_lbl_lan_ip.text = NetworkManager.get_lan_ip()
	_btn_start.visible = NetworkManager.is_host
	_lbl_wait.visible  = not NetworkManager.is_host
	# Adapte le label du bouton copier : IP directe ou code relay
	if _btn_copy != null:
		var is_ip: bool = "." in NetworkManager.room_code
		_btn_copy.text = "⎘  COPIER L'IP" if is_ip else "⎘  COPIER LE CODE"


# ── Handlers boutons ──────────────────────────────────────────────────────────

func _set_join_mode(mode: JoinMode, btn_code: Button, btn_ip: Button) -> void:
	_join_mode = mode
	var is_code := mode == JoinMode.CODE
	_panel_code.visible = is_code
	_panel_ip.visible   = not is_code
	btn_code.modulate.a = 1.0 if is_code else 0.55
	btn_ip.modulate.a   = 1.0 if not is_code else 0.55


func _on_host_lan_pressed() -> void:
	var n := _entry_name.text.strip_edges()
	if n.is_empty():
		_set_status("Entre ton nom d'abord.", true)
		return
	_set_status("Démarrage du serveur…", false)
	NetworkManager.host_lan(n)


func _on_join_lan_pressed() -> void:
	var n := _entry_name.text.strip_edges()
	var ip := _entry_ip.text.strip_edges()
	if n.is_empty():
		_set_status("Entre ton nom d'abord.", true)
		return
	if ip.is_empty():
		_set_status("Entre l'IP de l'hôte.", true)
		return
	_set_status("Connexion à %s…" % ip, false)
	NetworkManager.join_lan(ip, n)


func _on_host_pressed() -> void:
	var n := _entry_name.text.strip_edges()
	if n.is_empty():
		_set_status("Entre ton nom d'abord.", true)
		return
	_set_status("Création du salon…", false)
	NetworkManager.host_game(n)


func _on_join_pressed() -> void:
	var n := _entry_name.text.strip_edges()
	var c := _entry_code.text.strip_edges().to_upper()
	if n.is_empty():
		_set_status("Entre ton nom d'abord.", true)
		return
	if c.length() != 6:
		_set_status("Le code doit faire 6 caractères.", true)
		return
	_set_status("Connexion en cours…", false)
	NetworkManager.join_game(c, n)


func _on_start_pressed() -> void:
	if NetworkManager.players.size() < 2:
		_set_status("En attente d'un 2ème joueur…", false)
		return
	NetworkManager.start_game()


func _on_back_pressed() -> void:
	NetworkManager.disconnect_from_game()
	if _screen == Screen.LOBBY:
		_set_status("", false)
		_show_main()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_copy_pressed() -> void:
	var code: String = NetworkManager.room_code
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	var original_label: String = _btn_copy.text
	_btn_copy.text = "✓  COPIÉ !"
	var tw := _btn_copy.create_tween()
	tw.tween_interval(1.8)
	tw.tween_callback(func(): _btn_copy.text = original_label)


# ── Callbacks NetworkManager ──────────────────────────────────────────────────
func _on_room_code_ready(code: String) -> void:
	_show_lobby()
	_lbl_code.text = code


func _on_connection_success() -> void:
	_show_lobby()


func _on_connection_failed(reason: String) -> void:
	_set_status(reason, true)
	if _screen == Screen.LOBBY:
		_show_main()


func _on_players_updated(updated: Dictionary) -> void:
	_rebuild_player_slots(updated)
	if _screen == Screen.LOBBY and NetworkManager.is_host:
		_btn_start.visible = true


func _on_relay_awake(ok: bool) -> void:
	if ok:
		_set_status("", false)
	else:
		_set_status("Serveur relay hors ligne. Mode LAN uniquement.", true)


func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://scenes/coop/coop_arena.tscn")


# ── Construction des slots joueurs ────────────────────────────────────────────
func _rebuild_player_slots(updated: Dictionary) -> void:
	for child in _lbl_players.get_children():
		child.queue_free()

	for slot in MAX_PLAYERS:
		var slot_box := PanelContainer.new()
		var ss := StyleBoxFlat.new()
		var keys: Array = updated.keys()
		var filled: bool = slot < keys.size()
		var pid: int = keys[slot] if filled else -1

		ss.bg_color = Color(0.0, 0.851, 1.0, 0.06) if filled else Color(0.0, 0.0, 0.0, 0.0)
		ss.border_color = Color(C_CYAN, 0.35) if filled else Color(C_CYAN, 0.12)
		ss.set_border_width_all(1)
		ss.set_corner_radius_all(3)
		ss.set_content_margin_all(12)
		slot_box.add_theme_stylebox_override("panel", ss)
		_lbl_players.add_child(slot_box)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		slot_box.add_child(row)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = C_GREEN if filled else Color(C_CYAN, 0.15)
		row.add_child(dot)

		var lbl_slot := Label.new()
		lbl_slot.text = "P%d" % (slot + 1)
		lbl_slot.add_theme_font_size_override("font_size", 11)
		lbl_slot.add_theme_color_override("font_color", Color(C_CYAN, 0.45))
		if _font: lbl_slot.add_theme_font_override("font", _font)
		lbl_slot.custom_minimum_size = Vector2(28, 0)
		row.add_child(lbl_slot)

		var lbl_name := Label.new()
		if filled:
			var pinfo: Dictionary = updated[pid]
			lbl_name.text = pinfo.get("name", "Joueur")
			if pid == 1:
				lbl_name.text += "  ◆ hôte"
			lbl_name.add_theme_color_override("font_color", C_TEXT)
		else:
			lbl_name.text = "En attente…"
			lbl_name.add_theme_color_override("font_color", Color(C_CYAN, 0.25))
		lbl_name.add_theme_font_size_override("font_size", 14)
		if _font: lbl_name.add_theme_font_override("font", _font)
		row.add_child(lbl_name)


# ── Helpers visuels ───────────────────────────────────────────────────────────
const MAX_PLAYERS := 2

func _set_status(text: String, error: bool) -> void:
	_lbl_status.text = text
	_lbl_status.add_theme_color_override("font_color", C_RED if error else Color(C_CYAN, 0.55))


func _make_panel() -> PanelContainer:
	var pc := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	s.border_color = Color(C_CYAN, 0.22)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(24)
	pc.add_theme_stylebox_override("panel", s)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	pc.add_child(vb)
	return pc


func _add_section_header(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(C_CYAN, 0.70))
	if _font: lbl.add_theme_font_override("font", _font)
	parent.add_child(lbl)


func _add_field_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(C_CYAN, 0.40))
	if _font: lbl.add_theme_font_override("font", _font)
	parent.add_child(lbl)


func _make_deco_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(C_CYAN, 0.45))
	if _font: l.add_theme_font_override("font", _font)
	return l


func _make_line_edit(placeholder: String, max_length: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.max_length = max_length
	le.custom_minimum_size = Vector2(0, 46)
	var sn := StyleBoxFlat.new()
	sn.bg_color = C_DARK
	sn.border_color = Color(C_CYAN, 0.28)
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(3)
	sn.set_content_margin_all(10)
	var sf := sn.duplicate() as StyleBoxFlat
	sf.border_color = Color(C_CYAN, 0.80)
	sf.bg_color = Color(0.0, 0.851, 1.0, 0.05)
	le.add_theme_stylebox_override("normal", sn)
	le.add_theme_stylebox_override("focus",  sf)
	le.add_theme_color_override("font_color", C_TEXT)
	le.add_theme_color_override("font_placeholder_color", Color(C_CYAN, 0.25))
	le.add_theme_color_override("caret_color", C_CYAN)
	le.add_theme_font_size_override("font_size", 18)
	if _font: le.add_theme_font_override("font", _font)
	return le


func _make_action_button(label: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 50)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(color, 0.0)
	sn.border_color = Color(color, 0.65)
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(3)
	sn.set_content_margin_all(12)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(color, 0.12)
	sh.border_color = Color(color, 1.0)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = Color(color, 0.22)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 14)
	if _font: btn.add_theme_font_override("font", _font)
	btn.mouse_entered.connect(func():
		var tw := btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.03, 1.03), 0.10)
	)
	btn.mouse_exited.connect(func():
		var tw := btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12)
	)
	return btn


func _make_menu_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 42)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sn.border_color = Color(C_CYAN, 0.25)
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(3)
	sn.set_content_margin_all(10)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(C_CYAN, 0.07)
	sh.border_color = Color(C_CYAN, 0.65)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sh)
	btn.add_theme_color_override("font_color", Color(C_CYAN, 0.6))
	btn.add_theme_color_override("font_hover_color", C_CYAN)
	btn.add_theme_font_size_override("font_size", 13)
	if _font: btn.add_theme_font_override("font", _font)
	return btn


func _add_spacer(parent: Control, height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)
  