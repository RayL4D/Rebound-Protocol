# =============================================================
# settings.gd — Écran des paramètres (audio, affichage, langue)
# Persistance via ConfigFile dans user://settings.cfg
# =============================================================
class_name Settings
extends Control

const SETTINGS_PATH := "user://settings.cfg"

# Chemin de la police pour rester cohérent avec le menu principal
const FONT_PATH := "res://ui_theme/fonts/Xolonium-Regular.ttf"

const COLOR_CYAN   := Color(0.0,  0.851, 1.0, 1.0)
const COLOR_BG     := Color(0.168, 0.212, 0.259, 1.0)
const COLOR_PANEL  := Color(0.08,  0.11,  0.14,  0.95)

# Refs UI
var _volume_slider:     HSlider
var _music_slider:      HSlider
var _sfx_slider:        HSlider
var _fullscreen_check:  CheckButton
var _lang_buttons:      Dictionary = {}  # "fr" / "en" / "es" → Button

var _font: FontFile = null

# --- Audio ------------------------------------------------------
const _SFX_HOVER: AudioStream = preload("res://audio/sfx/ui/btn_hover.wav")
const _SFX_CLICK: AudioStream = preload("res://audio/sfx/ui/btn_click.wav")
var _sfx_player: AudioStreamPlayer = null


# =============================================================
# INIT
# =============================================================

func _ready() -> void:
	# Chargement de la police (optionnel — fallback sur la police par défaut)
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)

	_sfx_player     = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)

	_build_ui()
	_load_and_apply_settings()


# =============================================================
# CONSTRUCTION UI PROGRAMMATIQUE
# =============================================================

func _build_ui() -> void:
	# --- Fond plein écran ---
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = COLOR_BG
	add_child(bg)

	# --- Conteneur centré ---
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 28)
	center.add_child(vbox)

	# Panneau décoratif autour du vbox
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color       = COLOR_PANEL
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_color        = COLOR_CYAN
	style.content_margin_left   = 40.0
	style.content_margin_right  = 40.0
	style.content_margin_top    = 32.0
	style.content_margin_bottom = 32.0
	panel.add_theme_stylebox_override("panel", style)
	vbox.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 24)
	panel.add_child(inner)

	# --- Titre ---
	_add_title(inner, "SETTINGS_TITLE")

	# --- Séparateur ---
	inner.add_child(HSeparator.new())

	# --- Section Audio ---
	_add_section_label(inner, "SETTINGS_SECTION_AUDIO")
	_volume_slider = _add_slider(inner, "SETTINGS_MASTER_VOLUME", 0.0, 100.0, 100.0)
	_music_slider  = _add_slider(inner, "SETTINGS_MUSIC",         0.0, 100.0, 100.0)
	_sfx_slider    = _add_slider(inner, "SETTINGS_SFX",           0.0, 100.0, 100.0)

	_volume_slider.value_changed.connect(_on_master_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	# --- Séparateur ---
	inner.add_child(HSeparator.new())

	# --- Section Affichage ---
	_add_section_label(inner, "SETTINGS_SECTION_DISPLAY")
	_fullscreen_check = _add_check(inner, "SETTINGS_FULLSCREEN")
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	# --- Séparateur ---
	inner.add_child(HSeparator.new())

	# --- Section Langue ---
	_add_section_label(inner, "SETTINGS_SECTION_LANGUAGE")
	_add_language_buttons(inner)

	# --- Bouton retour (hors du panneau) ---
	vbox.add_child(_make_button("SETTINGS_BACK", _on_back_pressed))


# =============================================================
# HELPERS UI
# =============================================================

func _add_title(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", COLOR_CYAN)
	parent.add_child(lbl)


func _add_section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.9))
	parent.add_child(lbl)


func _add_slider(parent: Control, label_text: String, min_v: float, max_v: float, default_v: float) -> HSlider:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(160, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step      = 1.0
	slider.value     = default_v
	slider.custom_minimum_size = Vector2(220, 0)
	hbox.add_child(slider)

	# Valeur affichée
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(40, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	val_lbl.text = str(int(default_v)) + "%"
	if _font:
		val_lbl.add_theme_font_override("font", _font)
	val_lbl.add_theme_font_size_override("font_size", 14)
	val_lbl.add_theme_color_override("font_color", COLOR_CYAN)
	hbox.add_child(val_lbl)

	# Mise à jour du label en temps réel
	slider.value_changed.connect(func(v: float): val_lbl.text = str(int(v)) + "%")

	return slider


func _add_check(parent: Control, label_text: String) -> CheckButton:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = label_text
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(lbl)

	var check := CheckButton.new()
	hbox.add_child(check)
	return check


func _add_language_buttons(parent: Control) -> void:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	parent.add_child(hbox)

	var langs := {"FR": "fr", "EN": "en", "ES": "es"}
	for label in langs:
		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(60, 36)
		if _font:
			btn.add_theme_font_override("font", _font)
		btn.pressed.connect(_change_language.bind(langs[label]))
		btn.mouse_entered.connect(func():
			if _sfx_player and _SFX_HOVER:
				_sfx_player.stream      = _SFX_HOVER
				_sfx_player.volume_db   = 2.0
				_sfx_player.pitch_scale = randf_range(0.97, 1.03)
				_sfx_player.play()
		)
		btn.pressed.connect(func():
			if _sfx_player and _SFX_CLICK:
				_sfx_player.stream      = _SFX_CLICK
				_sfx_player.volume_db   = 5.0
				_sfx_player.pitch_scale = randf_range(0.97, 1.03)
				_sfx_player.play()
		)
		hbox.add_child(btn)
		_lang_buttons[langs[label]] = btn
	
	_refresh_lang_buttons()


func _make_button(label_text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(200, 44)
	if _font:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COLOR_CYAN)

	var style := StyleBoxFlat.new()
	style.bg_color         = Color(0.6, 0.6, 0.6, 0.0)
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_color        = COLOR_CYAN
	btn.add_theme_stylebox_override("normal", style)
	btn.mouse_entered.connect(func():
		if _sfx_player and _SFX_HOVER and is_inside_tree():
			_sfx_player.stream      = _SFX_HOVER
			_sfx_player.volume_db   = 2.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	# Son connecté EN PREMIER — joue avant que le callback change de scène
	btn.pressed.connect(func():
		if _sfx_player and _SFX_CLICK and is_inside_tree():
			_sfx_player.stream      = _SFX_CLICK
			_sfx_player.volume_db   = 5.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	btn.pressed.connect(callback)
	return btn


func _refresh_lang_buttons() -> void:
	# Met en évidence la langue actuellement active
	var current := TranslationServer.get_locale()
	for locale in _lang_buttons:
		var btn: Button = _lang_buttons[locale]
		if locale == current:
			btn.add_theme_color_override("font_color", COLOR_CYAN)
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			btn.modulate = Color(0.8, 0.8, 0.8, 1.0)


# =============================================================
# CALLBACKS
# =============================================================

func _on_master_volume_changed(value: float) -> void:
	_apply_bus_volume("Master", value)
	_save_settings()


func _on_music_volume_changed(value: float) -> void:
	_apply_bus_volume("Music", value)
	_save_settings()


func _on_sfx_volume_changed(value: float) -> void:
	_apply_bus_volume("SFX", value)
	_save_settings()


func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()


func _change_language(locale: String) -> void:
	TranslationServer.set_locale(locale)
	_refresh_lang_buttons()
	_save_settings()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# =============================================================
# AUDIO HELPER
# =============================================================

func _apply_bus_volume(bus_name: String, percent: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		# Bus non trouvé — on ignore silencieusement
		return
	var db := linear_to_db(percent / 100.0) if percent > 0.0 else -80.0
	AudioServer.set_bus_volume_db(idx, db)


# =============================================================
# PERSISTANCE
# =============================================================

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio",   "master_volume", _volume_slider.value)
	cfg.set_value("audio",   "music_volume",  _music_slider.value)
	cfg.set_value("audio",   "sfx_volume",    _sfx_slider.value)
	cfg.set_value("display", "fullscreen",    _fullscreen_check.button_pressed)
	cfg.set_value("locale",  "language",      TranslationServer.get_locale())
	cfg.save(SETTINGS_PATH)


func _load_and_apply_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		# Aucun fichier de config → valeurs par défaut déjà appliquées dans _build_ui
		return

	# Audio
	var master: float = cfg.get_value("audio", "master_volume", 100.0)
	var music:  float = cfg.get_value("audio", "music_volume",  100.0)
	var sfx:    float = cfg.get_value("audio", "sfx_volume",    100.0)
	# set_value_no_signal n'existe pas sur HSlider → on déconnecte temporairement
	_volume_slider.value_changed.disconnect(_on_master_volume_changed)
	_music_slider.value_changed.disconnect(_on_music_volume_changed)
	_sfx_slider.value_changed.disconnect(_on_sfx_volume_changed)
	_volume_slider.value = master
	_music_slider.value  = music
	_sfx_slider.value    = sfx
	_volume_slider.value_changed.connect(_on_master_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_apply_bus_volume("Master", master)
	_apply_bus_volume("Music",  music)
	_apply_bus_volume("SFX",    sfx)

	# Affichage
	var fs: bool = cfg.get_value("display", "fullscreen", false)
	_fullscreen_check.set_pressed_no_signal(fs)
	if fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# Langue
	var lang: String = cfg.get_value("locale", "language", "fr")
	TranslationServer.set_locale(lang)
	_refresh_lang_buttons()


# =============================================================
# FONCTION STATIQUE — à appeler au démarrage depuis d'autres scènes
# pour que les réglages soient actifs dès le lancement
# =============================================================

static func apply_saved_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return

	# Audio
	var master: float = cfg.get_value("audio", "master_volume", 100.0)
	var music:  float = cfg.get_value("audio", "music_volume",  100.0)
	var sfx:    float = cfg.get_value("audio", "sfx_volume",    100.0)

	var idx_m := AudioServer.get_bus_index("Master")
	var idx_mu := AudioServer.get_bus_index("Music")
	var idx_s := AudioServer.get_bus_index("SFX")
	if idx_m != -1:
		AudioServer.set_bus_volume_db(idx_m, linear_to_db(master / 100.0) if master > 0.0 else -80.0)
	if idx_mu != -1:
		AudioServer.set_bus_volume_db(idx_mu, linear_to_db(music / 100.0) if music > 0.0 else -80.0)
	if idx_s != -1:
		AudioServer.set_bus_volume_db(idx_s, linear_to_db(sfx / 100.0) if sfx > 0.0 else -80.0)

	# Affichage
	var fs: bool = cfg.get_value("display", "fullscreen", false)
	if fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# Langue
	var lang: String = cfg.get_value("locale", "language", "fr")
	TranslationServer.set_locale(lang)
