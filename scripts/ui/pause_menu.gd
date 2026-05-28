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
const COLOR_DIM    := Color(0.55,  0.60,  0.65,  1.0)
const COLOR_GOLD   := Color(1.0,   0.82,  0.0,   1.0)
const COLOR_RED   := Color(0.9,   0.25,  0.25,  1.0)

# --- Refs UI -------------------------------------------------
var _panel_main:     Control
var _panel_settings: Control
var _panel_skills:   Control
var _skills_list:    VBoxContainer   # contenu dynamique, rebâti à chaque ouverture

var _volume_slider:    HSlider
var _music_slider:     HSlider
var _sfx_slider:       HSlider
var _fullscreen_check: CheckButton
var _lang_buttons:     Dictionary = {}
var _font: FontFile = null
var _confirm_overlay: ColorRect = null

# --- Audio ------------------------------------------------------
const _SFX_HOVER:       AudioStream = preload("res://audio/sfx/ui/btn_hover.wav")
const _SFX_CLICK:       AudioStream = preload("res://audio/sfx/ui/btn_click.wav")
const _SFX_PAUSE_OPEN:  AudioStream = preload("res://audio/sfx/ui/pause_open.wav")
const _SFX_PAUSE_CLOSE: AudioStream = preload("res://audio/sfx/ui/pause_close.wav")
var _sfx_player: AudioStreamPlayer = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)

	_sfx_player              = AudioStreamPlayer.new()
	_sfx_player.bus          = "SFX"
	_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx_player)

	_build_ui()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		# Ne pas interferer avec l'écran GameOver si le joueur est mort
		var player := get_tree().get_first_node_in_group("player") as Player
		if player != null and player.is_dead:
			return
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
	if _sfx_player and _SFX_PAUSE_OPEN:
		_sfx_player.stream      = _SFX_PAUSE_OPEN
		_sfx_player.volume_db   = -6.0
		_sfx_player.pitch_scale = 1.0
		_sfx_player.play()
	show()


func _resume() -> void:
	get_tree().paused = false
	if _sfx_player and _SFX_PAUSE_CLOSE:
		_sfx_player.stream      = _SFX_PAUSE_CLOSE
		_sfx_player.volume_db   = -6.0
		_sfx_player.pitch_scale = 1.0
		_sfx_player.play()
	hide()


# =============================================================
# CONSTRUCTION UI
# =============================================================

func _build_ui() -> void:
	# Fond assombri plein écran (IGNORE pour ne pas bloquer les clics sur les boutons)
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = COLOR_BG
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_panel_main     = _build_main_panel()
	_panel_settings = _build_settings_panel()
	_panel_skills   = _build_skills_panel()

	add_child(_panel_main)
	add_child(_panel_settings)
	add_child(_panel_skills)


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
	inner.add_child(_make_button("PAUSE_RESUME",    _resume))
	inner.add_child(_make_button("PAUSE_SETTINGS",  _show_settings_panel))
	inner.add_child(_make_button("UI_BTN_SKILL",     _show_skills_panel))
	inner.add_child(_make_button("PAUSE_QUIT_MENU", _quit_to_menu))

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
	_panel_skills.hide()


func _show_settings_panel() -> void:
	_panel_main.hide()
	_panel_settings.show()
	_panel_skills.hide()


func _show_skills_panel() -> void:
	_panel_main.hide()
	_panel_settings.hide()

	# Vider et rebâtir la liste (les skills évoluent en cours de run)
	for child in _skills_list.get_children():
		child.queue_free()

	var acquired: Array = []
	if get_tree().root.has_node("XpManager"):
		acquired = XpManager.acquired_skills

	if acquired.is_empty():
		var lbl := Label.new()
		lbl.text = tr("SKILL_VIEW")
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.60))
		if _font:
			lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 15)
		_skills_list.add_child(lbl)
	else:
		for skill_id in acquired:
			if SkillCatalogue.SKILLS.has(skill_id):
				_skills_list.add_child(_make_skill_row(skill_id))

	_panel_skills.show()


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
	if TranslationServer.get_locale().begins_with(locale):
		return
	_show_language_confirm_dialog(locale)


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


# ------------------------------------------------------------------
# Panel compétences : liste scrollable des skills acquis
# ------------------------------------------------------------------

func _build_skills_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	center.add_child(outer)

	var panel := _make_panel_box()
	panel.custom_minimum_size = Vector2(580, 0)
	outer.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	panel.add_child(inner)

	_add_title(inner, "⚡  " + tr("UI_BTN_SKILL") + "  ⚡")
	inner.add_child(HSeparator.new())

	# ScrollContainer : hauteur bornée pour ne pas dépasser l'écran
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size          = Vector2(0, 340)
	scroll.horizontal_scroll_mode       = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical          = Control.SIZE_EXPAND_FILL
	inner.add_child(scroll)

	_skills_list = VBoxContainer.new()
	_skills_list.add_theme_constant_override("separation", 8)
	_skills_list.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	scroll.add_child(_skills_list)

	# Bouton Retour (hors panneau, comme le panel settings)
	outer.add_child(_make_button("RETOUR", _show_main_panel))

	return center


func _make_skill_row(skill_id: String) -> Control:
	var data: Dictionary = SkillCatalogue.SKILLS[skill_id]
	var rarity: int  = data["rarity"]
	var rc: Color    = SkillCatalogue.RARITY_COLORS[rarity]
	var rn: String   = SkillCatalogue.RARITY_NAMES[rarity]

	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color              = Color(rc.r, rc.g, rc.b, 0.07)
	style.border_width_left     = 4
	style.border_width_right    = 0
	style.border_width_top      = 0
	style.border_width_bottom   = 0
	style.border_color          = rc
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 8.0
	style.content_margin_bottom = 8.0
	row.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)

	# Ligne du haut : nom + badge rareté
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text                    = data["name"]
	name_lbl.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	if _font:
		name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 16)
	header.add_child(name_lbl)

	var rar_lbl := Label.new()
	rar_lbl.text = rn
	rar_lbl.add_theme_color_override("font_color", rc)
	if _font:
		rar_lbl.add_theme_font_override("font", _font)
	rar_lbl.add_theme_font_size_override("font_size", 12)
	header.add_child(rar_lbl)

	# Description
	var desc := Label.new()
	desc.text         = data["description"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_color_override("font_color", Color(0.72, 0.80, 0.88))
	if _font:
		desc.add_theme_font_override("font", _font)
	desc.add_theme_font_size_override("font_size", 13)
	col.add_child(desc)

	return row


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
	btn.process_mode           = Node.PROCESS_MODE_WHEN_PAUSED  # reçoit le touch/clic pendant la pause
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
	btn.mouse_entered.connect(func():
		if _sfx_player and _SFX_HOVER and is_inside_tree():
			_sfx_player.stream      = _SFX_HOVER
			_sfx_player.volume_db   = 2.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	# Son connecté EN PREMIER pour jouer avant que le callback quitte la scène
	btn.pressed.connect(func():
		if _sfx_player and _SFX_CLICK and is_inside_tree():
			_sfx_player.stream      = _SFX_CLICK
			_sfx_player.volume_db   = 5.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	btn.pressed.connect(callback)
	return btn
	
# =============================================================
# BOÎTE DE DIALOGUE DE LANGUE
# =============================================================

func _show_language_confirm_dialog(new_locale: String) -> void:
	if _confirm_overlay != null:
		_confirm_overlay.queue_free()

	var previous_locale := TranslationServer.get_locale()
	
	# ASTUCE : On applique la nouvelle langue IMMÉDIATEMENT. 
	# Ainsi, les tr() en dessous génèreront les textes dans la langue ciblée.
	TranslationServer.set_locale(new_locale)

	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color            = COLOR_PANEL
	pstyle.border_color        = COLOR_CYAN
	pstyle.set_border_width_all(2)
	pstyle.content_margin_left   = 40.0
	pstyle.content_margin_right  = 40.0
	pstyle.content_margin_top    = 32.0
	pstyle.content_margin_bottom = 32.0
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# Titre et textes (seront traduits dans la nouvelle langue)
	vbox.add_child(_make_dialog_label(tr("UI_LANG_DIALOG_TITLE"), 16, COLOR_CYAN, true))
	vbox.add_child(_make_dialog_label(tr("UI_LANG_DIALOG_MSG"), 15, Color(0.9, 0.9, 1.0), false))
	vbox.add_child(_make_dialog_label(tr("UI_LANG_DIALOG_WARN"), 12, COLOR_GOLD, false))
	vbox.add_child(_make_dialog_label(tr("UI_LANG_DIALOG_RESTART"), 11, COLOR_DIM, false))

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	# Bouton ANNULER — Fond ROUGE
	var cancel_btn := _make_dialog_button(tr("UI_LANG_DIALOG_CANCEL"), COLOR_RED, true, func():
		overlay.queue_free()
		_confirm_overlay = null
		# Le joueur annule : on restaure l'ancienne langue !
		TranslationServer.set_locale(previous_locale)
		_refresh_lang_buttons()
	)
	cancel_btn.custom_minimum_size = Vector2(150, 44)
	hbox.add_child(cancel_btn)

	# Bouton CONTINUER — Fond CYAN
	var confirm_btn := _make_dialog_button(tr("UI_LANG_DIALOG_CONFIRM"), COLOR_CYAN, true, func():
		overlay.queue_free()
		_confirm_overlay = null
		# Le joueur confirme : on valide le changement via SceneManager
		SceneManager.update_language(new_locale)
		_refresh_lang_buttons()
		_save_settings()
	)
	confirm_btn.custom_minimum_size = Vector2(150, 44)
	hbox.add_child(confirm_btn)

	_confirm_overlay = overlay
	add_child(_confirm_overlay)

func _make_dialog_label(text: String, size: int, color: Color, outlined: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(380, 0)
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if outlined:
		lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		lbl.add_theme_constant_override("outline_size", 2)
	return lbl

func _make_dialog_button(text: String, color: Color, filled: bool, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	if _font:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	
	var sn := StyleBoxFlat.new()
	var sh := StyleBoxFlat.new()
	sn.set_border_width_all(1)
	sh.set_border_width_all(1)
	
	if filled:
		# Colore le fond en fonction de la couleur passée en argument
		sn.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.9)
		sn.border_color = color
		sh.bg_color = Color(color.r * 0.45, color.g * 0.45, color.b * 0.45, 0.95)
		sh.border_color = color
		btn.add_theme_color_override("font_color", color)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
	else:
		sn.bg_color = Color(0.08, 0.08, 0.10, 0.90)
		sn.border_color = color
		sh.bg_color = Color(0.14, 0.14, 0.18, 0.95)
		sh.border_color = color
		btn.add_theme_color_override("font_color", color)
		
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover", sh)
	
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
	btn.pressed.connect(callback)
	return btn
