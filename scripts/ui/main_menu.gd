extends Control

# Boutons du menu principal
@onready var btn_new_game  = $CenterContainer/MainVBox/ButtonsVBox/BtnNewGame
@onready var btn_continue  = $CenterContainer/MainVBox/ButtonsVBox/BtnContinue
@onready var btn_options   = $CenterContainer/MainVBox/ButtonsVBox/BtnOptions
@onready var btn_quit      = $CenterContainer/MainVBox/ButtonsVBox/BtnQuit

# Éléments de la langue
@onready var btn_toggle_language = $CenterContainer/MainVBox/LanguageVBox/BtnToggleLanguage
@onready var flags_container     = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer

@onready var btn_flag_fr = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer/BtnFlagFR
@onready var btn_flag_en = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer/BtnFlagEN
@onready var btn_flag_es = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer/BtnFlagES

# --- Audio ------------------------------------------------------
const _SFX_HOVER: AudioStream = preload("res://audio/sfx/ui/btn_hover.wav")
const _SFX_CLICK: AudioStream = preload("res://audio/sfx/ui/btn_click.wav")
var _sfx_player: AudioStreamPlayer = null


func _ready() -> void:
	MusicManager.play("menu")
	flags_container.hide()

	_sfx_player     = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)

	# Connecter hover/click à tous les boutons du menu
	for btn in [btn_new_game, btn_continue, btn_options, btn_quit,
				btn_toggle_language, btn_flag_fr, btn_flag_en, btn_flag_es]:
		btn.mouse_entered.connect(func():
			_sfx_player.stream      = _SFX_HOVER
			_sfx_player.volume_db   = 2.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
		)
		btn.pressed.connect(func():
			_sfx_player.stream      = _SFX_CLICK
			_sfx_player.volume_db   = 5.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
		)

	# Appliquer les paramètres sauvegardés dès le menu
	Settings.apply_saved_settings()

	# Connexions du menu principal
	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	btn_options.pressed.connect(_on_options_pressed)

	btn_continue.pressed.connect(_on_continue_pressed)

	# Activer "Continuer" seulement s'il existe au moins un slot utilisé
	var has_save := false
	for i in SaveData.MAX_SLOTS:
		if SaveData.get_slot_info(i)["used"]:
			has_save = true
			break
	if not has_save:
		btn_continue.disabled = true
		btn_continue.modulate = Color(0.5, 0.5, 0.5, 0.8)

	# Connexion du bouton pour dérouler les langues
	btn_toggle_language.pressed.connect(_on_toggle_language_pressed)

	# Connexions des drapeaux
	btn_flag_fr.pressed.connect(func(): _change_language("fr"))
	btn_flag_en.pressed.connect(func(): _change_language("en"))
	btn_flag_es.pressed.connect(func(): _change_language("es"))


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


func _on_toggle_language_pressed() -> void:
	flags_container.visible = !flags_container.visible


func _change_language(locale: String) -> void:
	TranslationServer.set_locale(locale)
	SceneManager.current_lang = locale
	flags_container.hide()

	# Sauvegarder la langue dans la config
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("locale", "language", locale)
	cfg.save("user://settings.cfg")
