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

var _M:            float              = 1.6 if OS.has_feature("mobile") else 1.0
var _sfx_player:   AudioStreamPlayer = null
var _font:         FontFile           = null
var _status_label: Label              = null
var _signal_label: Label              = null
var _status_blink: float = 0.0
var _signal_timer: float = 0.0
var _signal_level: int   = 4
var _pulse_timer:  float = 8.0


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
	if _M > 1.0:
		_apply_mobile_scaling()

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

func _apply_mobile_scaling() -> void:
	var M := _M
	# Titre et sous-titre
	_title_label.add_theme_font_size_override("font_size", int(40 * M))
	_subtitle_label.add_theme_font_size_override("font_size", int(25 * M))

	# Séparations des VBox
	var main_vbox := $CenterContainer/MainVBox as VBoxContainer
	main_vbox.add_theme_constant_override("separation", int(50 * M))
	var btns_vbox := $CenterContainer/MainVBox/ButtonsVBox as VBoxContainer
	btns_vbox.add_theme_constant_override("separation", int(15 * M))
	var lang_vbox := $CenterContainer/MainVBox/LanguageVBox as VBoxContainer
	lang_vbox.add_theme_constant_override("separation", int(10 * M))

	# Taille minimale des boutons principaux
	var main_btns := [btn_new_game, btn_continue, btn_coop, btn_options, btn_quit, btn_credits]
	for btn in main_btns:
		var b := btn as Button
		b.add_theme_font_size_override("font_size", int(18 * M))
		b.custom_minimum_size = Vector2(260.0 * M, 44.0 * M)

	# Bouton langue
	btn_toggle_language.add_theme_font_size_override("font_size", int(14 * M))
	btn_toggle_language.custom_minimum_size = Vector2(160.0 * M, 36.0 * M)


func _build_background() -> void:
	_bg_rect.color = Color(0.025, 0.045, 0.075)
	
	# Instanciation de la nouvelle classe globale de fond animé
	var fx := AnimatedBackground.new()
	add_child(fx)
	move_child(fx, 1)   # entre Background et CenterContainer


func _build_hud_labels() -> void:
	var M := _M
	_status_label = Label.new()
	_status_label.text = "▸ SYSTÈME ACTIF"
	_status_label.add_theme_font_size_override("font_size", int(12 * M))
	_status_label.add_theme_color_override("font_color", COLOR_CYAN)
	if _font:
		_status_label.add_theme_font_override("font", _font)
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status_label.offset_left   =  18.0 * M
	_status_label.offset_top    = -34.0 * M
	_status_label.offset_bottom = -14.0 * M
	_status_label.offset_right  =  280.0 * M
	add_child(_status_label)

	_signal_label = Label.new()
	_signal_label.add_theme_font_size_override("font_size", int(12 * M))
	_signal_label.add_theme_color_override("font_color", COLOR_CYAN)
	if _font:
		_signal_label.add_theme_font_override("font", _font)
	_signal_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_signal_label.offset_left   = -260.0 * M
	_signal_label.offset_top    = -34.0 * M
	_signal_label.offset_bottom = -14.0 * M
	_signal_label.offset_right  = -18.0 * M
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
	SceneManager.update_language(locale)
	flags_container.hide()
