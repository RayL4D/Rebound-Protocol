# =============================================================
# pause_menu.gd — Menu pause en jeu (Échap)
# Rebound Protocol
# =============================================================
# Deux panels :
#   • _panel_main    → Reprendre / Paramètres / Menu principal
#   • _panel_settings → Paramètres audio + affichage + langue
#
# Le jeu est gelé via get_tree().paused = true.
# Ce nœud tourne en PROCESS_MODE_ALWAYS pour répondre
# aux entrées même quand le jeu est en pause.
# =============================================================
class_name PauseMenu
extends CanvasLayer

const SETTINGS_PATH := "user://settings.cfg"
const FONT_PATH     := "res://ui_theme/fonts/Xolonium-Regular.ttf"

const COLOR_CYAN  := Color(0.0,  0.851, 1.0,  1.0)
const COLOR_BG    := Color(0.0,  0.0,   0.0,  0.65)   # overlay semi-transparent
const COLOR_PANEL := Color(0.08, 0.11,  0.14, 0.95)

# --- Refs UI -------------------------------------------------
var _panel_main:     Control
var _panel_settings: Control

var _volume_slider:    HSlider
var _music_slider:     HSlider
var _sfx_slider:       HSlider
var _fullscreen_check: CheckButton
var _lang_buttons:     Dictionary = {}

var _font: FontFile = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)

	_build_ui()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if visible:
			_resume()
		else:
			_open()


# =============================================================
# PAUSE / REPRISE
# =============================================================

func _open() -> void:
	_show_main_panel()
	get_tree().paused = true
	show()


func _resume() -> void:
	get_tree().paused = false
	hide()


# =============================================================
# CONSTRUCTION UI
# =============================================================

func _build_ui() -> void:
	# Fond assombri plein écran
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = COLOR_BG
	add_child(overlay)

	_panel_main     = _build_main_panel()
	_panel_settings = _build_settings_panel()

	add_child(_panel_main)
	add_child(_panel_settings)


# ------------------------------------------------------------------
# Panel principal : Reprendre / Paramètres / Quitter
# ------------------------------------------------------------------

func _build_main_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := _make_panel_box()
	center.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 20)
	panel.add_child(inner)

	_add_title(inner, "PAUSE_TITLE")
	inner.add_child(HSeparator.new())
	inner.add_child(_make_button("PAUSE_RESUME",   _resume))
	inner.add_child(_make_button("PAUSE_SETTINGS", _show_settings_panel))
	inner.add_child(_make_button("PAUSE_QUIT_MENU",  _quit_to_menu))

	return center


# ------------------------------------------------------------------
# Panel paramètres : Audio + Affichage + Langue + Retour
# ------------------------------------------------------------------

func _build_settings_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var panel := _make_panel_box()
	vbox.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 18)
	panel.add_child(inner)

	_add_title(inner, "SETTINGS_TITLE")
	inner.add_child(HSeparator.new())

	# Audio
	_add_section_label(inner, "SETTINGS_SECTION_AUDIO")
	_volume_slider = _add_slider(inner, "SETTINGS_MASTER_VOLUME", 0.0, 100.0, 100.0)
	_music_slider  = _add_slider(inner, "SETTINGS_MUSIC",         0.0, 100.0, 100.0)
	_sfx_slider    = _add_slider(inner, "SETTINGS_SFX",           0.0, 100.0, 100.0)

	_volume_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)

	inner.add_child(HSeparator.new())

	# Affichage
	_add_section_label(inner, "SETTINGS_SECTION_DISPLAY")
	_fullscreen_check = _add_check(inner, "SETTINGS_FULLSCREEN")
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	inner.add_child(HSeparator.new())

	# Langue
	_add_section_label(inner, "SETTINGS_SECTION_LANGUAGE")
	_add_language_buttons(inner)

	# Bouton retour (hors panneau)
	vbox.add_child(_make_button("SETTINGS_BACK", _show_main_panel))

	# Charger les valeurs sauvegardées
	_load_settings_into_panel()

	return center


# =============================================================
# NAVIGATION ENTRE PANELS
# =============================================================

func _show_main_panel() -> void:
	_panel_main.show()
	_panel_settings.hide()


func _show_settings_panel() -> void:
	_panel_main.hide()
	_panel_settings.show()


func _quit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# =============================================================
# CALLBACKS PARAMÈTRES
# =============================================================

func _on_master_changed(value: float) -> void:
	_apply_bus("Master", value)
	_save_settings()


func _on_music_changed(value: float) -> void:
	_apply_bus("Music", value)
	_save_settings()


func _on_sfx_changed(value: float) -> void:
	_apply_bus("SFX", value)
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


# =============================================================
# AUDIO HELPER
# =============================================================

func _apply_bus(bus_name: String, percent: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(percent / 100.0) if percent > 0.0 else -80.0)


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


func _load_settings_into_panel() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return

	var master: float = cfg.get_value("audio", "master_volume", 100.0)
	var music:  float = cfg.get_value("audio", "music_volume",  100.0)
	var sfx:    float = cfg.get_value("audio", "sfx_volume",    100.0)

	# Assignation sans déclencher les callbacks
	_volume_slider.value_changed.disconnect(_on_master_changed)
	_music_slider.value_changed.disconnect(_on_music_changed)
	_sfx_slider.value_changed.disconnect(_on_sfx_changed)
	_volume_slider.value = master
	_music_slider.value  = music
	_sfx_slider.value    = sfx
	_volume_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)

	_fullscreen_check.set_pressed_no_signal(
		cfg.get_value("display", "fullscreen", false)
	)
	_refresh_lang_buttons()


# =============================================================
# HELPERS UI (même style que settings.gd)
# =============================================================

func _make_panel_box() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color              = COLOR_PANEL
	style.border_width_left     = 2
	style.border_width_right    = 2
	style.border_width_top      = 2
	style.border_width_bottom   = 2
	style.border_color          = COLOR_CYAN
	style.content_margin_left   = 40.0
	style.content_margin_right  = 40.0
	style.content_margin_top    = 32.0
	style.content_margin_bottom = 32.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


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
	lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value           = min_v
	slider.max_value           = max_v
	slider.step                = 1.0
	slider.value               = default_v
	slider.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size       = Vector2(40, 0)
	val_lbl.horizontal_alignment      = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment        = VERTICAL_ALIGNMENT_CENTER
	val_lbl.text                      = str(int(default_v)) + "%"
	if _font:
		val_lbl.add_theme_font_override("font", _font)
	val_lbl.add_theme_font_size_override("font_size", 14)
	val_lbl.add_theme_color_override("font_color", COLOR_CYAN)
	hbox.add_child(val_lbl)

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
		hbox.add_child(btn)
		_lang_buttons[langs[label]] = btn

	_refresh_lang_buttons()


func _refresh_lang_buttons() -> void:
	var current := TranslationServer.get_locale()
	for locale in _lang_buttons:
		var btn: Button = _lang_buttons[locale]
		if locale == current:
			btn.add_theme_color_override("font_color", COLOR_CYAN)
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			btn.modulate = Color(0.8, 0.8, 0.8, 1.0)


func _make_button(label_text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text                   = label_text
	btn.custom_minimum_size    = Vector2(220, 44)
	if _font:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COLOR_CYAN)

	var style := StyleBoxFlat.new()
	style.bg_color           = Color(0.6, 0.6, 0.6, 0.0)
	style.border_width_left  = 2
	style.border_width_right = 2
	style.border_width_top   = 2
	style.border_width_bottom = 2
	style.border_color       = COLOR_CYAN
	btn.add_theme_stylebox_override("normal", style)
	btn.pressed.connect(callback)
	return btn
