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


func _ready() -> void:
	flags_container.hide()

	# Appliquer les paramètres sauvegardés dès le menu
	Settings.apply_saved_settings()

	# Connexions du menu principal
	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	btn_options.pressed.connect(_on_options_pressed)

	# BtnContinue désactivé (pas de système de sauvegarde pour l'instant)
	btn_continue.disabled = true
	btn_continue.modulate = Color(0.5, 0.5, 0.5, 0.8)

	# Connexion du bouton pour dérouler les langues
	btn_toggle_language.pressed.connect(_on_toggle_language_pressed)

	# Connexions des drapeaux
	btn_flag_fr.pressed.connect(func(): _change_language("fr"))
	btn_flag_en.pressed.connect(func(): _change_language("en"))
	btn_flag_es.pressed.connect(func(): _change_language("es"))


func _on_new_game_pressed() -> void:
	SceneManager.load_level("res://scenes/levels/arena_base.tscn")


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
