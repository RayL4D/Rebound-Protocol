# =============================================================
# score_summary.gd — VERSION STYLÉE AVEC FOND ANIMÉ
# =============================================================
extends CanvasLayer

# Références UI
@onready var combat_stats = $CenterContainer/MainVBox/StatsPanel/StatsMargin/StatsVBox/CombatSection/CombatStats
@onready var progress_stats = $CenterContainer/MainVBox/StatsPanel/StatsMargin/StatsVBox/ProgressSection/ProgressStats
@onready var performance_stats = $CenterContainer/MainVBox/StatsPanel/StatsMargin/StatsVBox/PerformanceSection/PerformanceStats
@onready var score_label = $CenterContainer/MainVBox/TotalScoreContainer/ScoreLabel
@onready var rank_label = $CenterContainer/MainVBox/TotalScoreContainer/RankLabel
@onready var btn_restart = $CenterContainer/MainVBox/ButtonsContainer/BtnRestart
@onready var btn_menu = $CenterContainer/MainVBox/ButtonsContainer/BtnMenu
@onready var main_title = $CenterContainer/MainVBox/TitleSection/MainTitle
@onready var mission_status = $CenterContainer/MainVBox/TitleSection/MissionStatus
@onready var status_label = $StatusLabel
@onready var signal_label = $SignalLabel

const COLOR_CYAN := Color(0.0, 0.851, 1.0)
const COLOR_WHITE := Color(1.0, 1.0, 1.0)
const COLOR_GREEN := Color(0.0, 1.0, 0.5)
const COLOR_GOLD := Color(1.0, 0.85, 0.0)
const COLOR_PINK := Color(1.0, 0.15, 0.65)

const SFX_HOVER = preload("res://audio/sfx/ui/btn_hover.wav")
const SFX_CLICK = preload("res://audio/sfx/ui/btn_click.wav")

var _status_blink: float = 0.0
var _signal_timer: float = 0.0
var _signal_level: int = 4

# =============================================================
# CLASSE FOND ANIMÉ (version simplifiée du main_menu)
# =============================================================

class _BgFX extends Control:
	const C_CYAN := Color(0.0, 0.851, 1.0)
	const C_DARK := Color(0.025, 0.045, 0.075)
	const C_PINK := Color(1.0, 0.15, 0.65)

	var _t: float = 0.0
	var _stars: Array = []
	var _pts: Array = []
	var _streaks: Array = []
	var _streak_timer: float = 0.2
	var _rings: Array = []
	var _ring_timer: float = 2.5
	var _mouse_px: float = 0.5
	var _mouse_py: float = 0.5

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS 
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Étoiles
		var srng := RandomNumberGenerator.new()
		srng.seed = 98765
		for _i in 120:
			_stars.append({
				"x": srng.randf(), "y": srng.randf() * 0.56,
				"r": srng.randf_range(0.5, 2.0),
				"a": srng.randf_range(0.25, 0.85),
				"phase": srng.randf() * TAU,
				"freq":  srng.randf_range(0.2, 1.8),
			})

		# Particules
		for _i in 70:
			_pts.append({
				"x": randf(), "y": randf(),
				"vy": randf_range(0.007, 0.020),
				"r":  randf_range(1.2, 3.2),
				"a":  randf_range(0.15, 0.75),
			})

	func _process(delta: float) -> void:
		_t += delta

		# Parallaxe souris
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if vs.x > 0.0:
			_mouse_px = lerpf(_mouse_px, mp.x / vs.x, delta * 2.2)
			_mouse_py = lerpf(_mouse_py, mp.y / vs.y, delta * 2.2)

		# Particules
		for p in _pts:
			p["y"] = float(p["y"]) - float(p["vy"]) * delta
			if float(p["y"]) < -0.02:
				p["y"] = 1.02
				p["x"] = randf()

		# Streaks
		_streak_timer -= delta
		if _streak_timer <= 0.0:
			_streak_timer = randf_range(0.08, 0.55)
			_streaks.append({
				"y": randf_range(0.05, 0.92), "x": 0.0,
				"len": randf_range(0.04, 0.22),
				"spd": randf_range(0.4, 1.1),
				"a": randf_range(0.4, 0.95),
			})
		var si := 0
		while si < _streaks.size():
			_streaks[si]["x"] = float(_streaks[si]["x"]) + float(_streaks[si]["spd"]) * delta
			if float(_streaks[si]["x"]) > 1.1:
				_streaks.remove_at(si)
			else:
				si += 1

		# Anneaux
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

		queue_redraw()

	func _draw() -> void:
		var vp_size := get_viewport_rect().size
		var w := vp_size.x
		var h := vp_size.y
		var dx := (_mouse_px - 0.5) * 2.0
		var dy := (_mouse_py - 0.5) * 2.0

		# Étoiles scintillantes
		for star in _stars:
			var sp := float(star["phase"]) + _t * float(star["freq"])
			var sa := float(star["a"]) * (0.5 + 0.5 * sin(sp))
			var sx := (float(star["x"]) + dx * 0.01) * w
			var sy := (float(star["y"]) + dy * 0.01) * h
			draw_circle(Vector2(sx, sy), float(star["r"]), Color(C_CYAN, sa))

		# Particules flottantes
		for pt in _pts:
			var px := (float(pt["x"]) + dx * 0.014) * w
			var py := (float(pt["y"]) + dy * 0.018) * h
			draw_circle(Vector2(px, py), float(pt["r"]), Color(C_CYAN, float(pt["a"])))

		# Streaks
		for st in _streaks:
			var sx := float(st["x"]) * w
			var sy := float(st["y"]) * h
			var ex := (float(st["x"]) - float(st["len"])) * w
			draw_line(Vector2(sx, sy), Vector2(ex, sy), Color(C_CYAN, float(st["a"])), 1.5)

		# Anneaux
		for ring in _rings:
			var rad := float(ring["r"]) * mini(w, h) * 0.4
			var alp := float(ring["a"])
			draw_arc(Vector2(w * 0.5, h * 0.5), rad, 0, TAU, 64, Color(C_CYAN, alp), 2.0)

# =============================================================
# INITIALISATION
# =============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	
	if not has_node("/root/ScoreManager"):
		push_error("❌ ScoreManager n'existe pas!")
		return
	
	_build_animated_background()
	_populate_detailed_stats()
	_setup_buttons()
	call_deferred("_animate_entrance")

func _process(delta: float) -> void:
	_status_blink += delta
	if _status_blink >= 0.85:
		_status_blink = 0.0
	status_label.modulate.a = 1.0 if _status_blink < 0.55 else 0.0
	
	_signal_timer -= delta
	if _signal_timer <= 0.0:
		_signal_timer = randf_range(1.8, 4.0)
		_signal_level = randi_range(3, 5)
		_update_signal_label()

func _build_animated_background() -> void:
	var fx := _BgFX.new()
	add_child(fx)
	move_child(fx, 1)

func _update_signal_label() -> void:
	signal_label.text = tr("UI_SCORE_DATA_SIGNAL") % [
		"◆".repeat(_signal_level),
		"◇".repeat(5 - _signal_level)
	]

# =============================================================
# STATISTIQUES DÉTAILLÉES
# =============================================================

func _populate_detailed_stats() -> void:
	print("=== POPULATION DES STATS DÉTAILLÉES ===")
	
	var sm = ScoreManager
	
	# Stats de base
	var enemies_killed = sm.enemies_killed
	var waves_cleared = sm.waves_cleared
	var time_elapsed = sm.time_elapsed
	
	# Stats dérivées
	var kills_per_wave = float(enemies_killed) / max(1, waves_cleared)
	var kills_per_minute = (float(enemies_killed) / max(1.0, time_elapsed)) * 60.0
	var avg_time_per_wave = time_elapsed / max(1, waves_cleared)
	
	# SECTION COMBAT
	_add_stat_row(combat_stats, tr("UI_STAT_ENEMIES_KILLED"), str(enemies_killed), sm.PTS_PER_KILL * enemies_killed)
	_add_stat_row(combat_stats, tr("UI_STAT_KILLS_PER_WAVE"), "%.1f" % kills_per_wave, 0, false)
	_add_stat_row(combat_stats, tr("UI_STAT_KILLS_PER_MIN"), "%.1f" % kills_per_minute, 0, false)
	
	# SECTION PROGRESSION
	_add_stat_row(progress_stats, tr("UI_STAT_WAVES_CLEARED"), str(waves_cleared), sm.PTS_PER_WAVE * waves_cleared)
	_add_stat_row(progress_stats, tr("UI_STAT_TIME_PER_WAVE"), "%d s" % int(avg_time_per_wave), 0, false)
	_add_stat_row(progress_stats, tr("UI_STAT_SURVIVAL_TIME"), _format_time(time_elapsed), int(time_elapsed) * sm.PTS_PER_SECOND)
	
	# SECTION PERFORMANCE
	var total_score = sm.get_total_score()
	var efficiency = (float(total_score) / max(1.0, time_elapsed)) * 60.0
	var survival_rate = (float(waves_cleared) / max(1.0, time_elapsed / 60.0))
	
	_add_stat_row(performance_stats, tr("UI_STAT_EFFICIENCY"), "%d pts/min" % int(efficiency), 0, false)
	_add_stat_row(performance_stats, tr("UI_STAT_WAVES_PER_MIN"), "%.2f" % survival_rate, 0, false)
	_add_stat_row(performance_stats, tr("UI_STAT_AVG_DURATION"), "%d s/kill" % int(max(1.0, time_elapsed / max(1, enemies_killed))), 0, false)
	
	# Score total et rang
	var rank = _calculate_rank(total_score)
	score_label.text = tr("UI_SCORE_TOTAL") % total_score
	rank_label.text = tr("UI_SCORE_RANK") % rank
	
	print("✅ Stats affichées - Score total: %d, Rang: %s" % [total_score, rank])

func _add_stat_row(container: VBoxContainer, label_text: String, value_text: String, score: int, show_score: bool = true) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	
	# Nom de la stat
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", COLOR_WHITE)
	lbl.add_theme_font_size_override("font_size", 18)
	
	# Valeur
	var val_lbl := Label.new()
	val_lbl.text = value_text
	val_lbl.custom_minimum_size = Vector2(120, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", COLOR_CYAN)
	val_lbl.add_theme_font_size_override("font_size", 18)
	
	row.add_child(lbl)
	row.add_child(val_lbl)
	
	# Score (optionnel)
	if show_score and score > 0:
		var score_lbl := Label.new()
		score_lbl.text = "+ %d" % score
		score_lbl.custom_minimum_size = Vector2(100, 0)
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score_lbl.add_theme_color_override("font_color", COLOR_GREEN)
		score_lbl.add_theme_font_size_override("font_size", 18)
		row.add_child(score_lbl)
	
	container.add_child(row)

func _calculate_rank(score: int) -> String:
	if score >= 10000: return "S+"
	elif score >= 7500: return "S"
	elif score >= 5000: return "A"
	elif score >= 3000: return "B"
	elif score >= 1500: return "C"
	else: return "D"

func _format_time(seconds: float) -> String:
	var mins: int = floori(seconds / 60.0)
	var secs: int = floori(fmod(seconds, 60.0))
	return "%d:%02d" % [mins, secs]

# =============================================================
# BOUTONS
# =============================================================

func _setup_buttons() -> void:
	# Style hover
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.0, 0.851, 1.0, 0.12)
	hover_style.border_color = Color(0.0, 0.851, 1.0, 0.75)
	hover_style.set_border_width_all(2)
	hover_style.corner_radius_top_left = 4
	hover_style.corner_radius_top_right = 4
	hover_style.corner_radius_bottom_left = 4
	hover_style.corner_radius_bottom_right = 4
	
	for btn in [btn_restart, btn_menu]:
		btn.add_theme_stylebox_override("hover", hover_style)
		
		# Animations hover
		btn.mouse_entered.connect(func():
			_play_sfx(SFX_HOVER)
			var tw: Tween = btn.create_tween()
			tw.tween_method(func(c: Color): btn.add_theme_color_override("font_color", c),
				COLOR_CYAN, COLOR_WHITE, 0.10)
			tw.parallel().tween_property(btn, "scale", Vector2(1.05, 1.05), 0.10)
		)
		
		btn.mouse_exited.connect(func():
			var tw: Tween = btn.create_tween()
			tw.tween_method(func(c: Color): btn.add_theme_color_override("font_color", c),
				COLOR_WHITE, COLOR_CYAN, 0.13)
			tw.parallel().tween_property(btn, "scale", Vector2(1.0, 1.0), 0.13)
		)
	
	# Connexions
	btn_restart.pressed.connect(_on_restart)
	btn_menu.pressed.connect(_on_menu)

func _on_restart() -> void:
	_play_sfx(SFX_CLICK)
	print("🔄 Rejouer")
	get_tree().paused = false
	ScoreManager.is_tracking = false
	# Adapter le chemin vers votre scène de jeu
	get_tree().change_scene_to_file("res://scenes/levels/arena_first_level_1.tscn")

func _on_menu() -> void:
	_play_sfx(SFX_CLICK)
	print("📋 Retour au menu")
	get_tree().paused = false
	ScoreManager.is_tracking = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _play_sfx(stream: AudioStream) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = 0.0
	p.pitch_scale = randf_range(0.97, 1.03)
	get_tree().root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# =============================================================
# ANIMATIONS D'ENTRÉE
# =============================================================

func _animate_entrance() -> void:
	# Titre
	main_title.modulate.a = 0.0
	mission_status.modulate.a = 0.0
	
	var tw_title := create_tween()
	tw_title.tween_property(main_title, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_QUAD)
	tw_title.tween_callback(_glitch_title)
	
	var tw_status := create_tween()
	tw_status.tween_interval(0.35)
	tw_status.tween_property(mission_status, "modulate:a", 1.0, 0.38)
	
	# Panel stats
	var stats_panel = $CenterContainer/MainVBox/StatsPanel
	stats_panel.modulate.a = 0.0
	var tw_stats := create_tween()
	tw_stats.tween_interval(0.80)
	tw_stats.tween_property(stats_panel, "modulate:a", 1.0, 0.65)
	
	# Score
	var score_container = $CenterContainer/MainVBox/TotalScoreContainer
	score_container.modulate.a = 0.0
	var tw_score := create_tween()
	tw_score.tween_interval(1.45)
	tw_score.tween_property(score_container, "modulate:a", 1.0, 0.45)
	tw_score.tween_callback(_start_score_pulse)
	
	# Boutons
	btn_restart.modulate.a = 0.0
	btn_menu.modulate.a = 0.0
	var tw_btns := create_tween()
	tw_btns.tween_interval(2.0)
	tw_btns.tween_property(btn_restart, "modulate:a", 1.0, 0.38)
	tw_btns.parallel().tween_property(btn_menu, "modulate:a", 1.0, 0.38)

func _glitch_title() -> void:
	if not is_inside_tree():
		return
	var tw := create_tween()
	for _i in 4:
		tw.tween_property(main_title, "modulate:a", 0.1, 0.025)
		tw.tween_property(main_title, "modulate:a", 1.0, 0.045)

func _start_score_pulse() -> void:
	if not is_inside_tree():
		return
	
	# 1. On déclare et crée le Tween proprement
	var tw: Tween = create_tween()
	# 2. On applique les boucles sur une ligne séparée
	tw.set_loops()
	
	tw.tween_property(score_label, "modulate",
		Color(0.4, 1.0, 0.8, 1.0), 2.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(score_label, "modulate",
		COLOR_GREEN, 2.0).set_trans(Tween.TRANS_SINE)
