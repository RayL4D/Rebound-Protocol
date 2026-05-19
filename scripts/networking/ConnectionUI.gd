extends Control

@onready var ip_edit: LineEdit = $Panel/VBoxContainer/IPEdit
@onready var name_edit: LineEdit = $Panel/VBoxContainer/NameEdit
@onready var host_button: Button = $Panel/VBoxContainer/HostButton
@onready var join_button: Button = $Panel/VBoxContainer/JoinButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel

func _ready() -> void:
	if ip_edit: ip_edit.text = "127.0.0.1"
	if name_edit: name_edit.text = "Joueur_" + str(randi() % 1000)
	
	NetworkManager.connection_success.connect(_on_network_success)
	NetworkManager.connection_failed.connect(_on_network_failed)
	NetworkManager.player_list_changed.connect(_on_player_list_updated)
	_setup_ui_sounds()

func _setup_ui_sounds() -> void:
	var click_sound = load("res://audio/sfx/ui/btn_click.wav")
	for btn in [host_button, join_button]:
		if btn: btn.pressed.connect(func(): _play_temp_sound(click_sound))

func _play_temp_sound(stream: AudioStream) -> void:
	if stream == null: return
	var player = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _on_host_button_pressed() -> void:
	_prepare_local_player_data()
	status_label.text = "Création du serveur..."
	if NetworkManager.host_game() == OK:
		# ICI : On charge ta bonne arène multijoueur !
		NetworkManager.load_arena_scene.rpc("res://scenes/levels/multiplayer/arena_multiplayer.tscn")
	else:
		status_label.text = "Erreur de création"

func _on_join_button_pressed() -> void:
	_prepare_local_player_data()
	status_label.text = "Connexion..."
	NetworkManager.join_game(ip_edit.text.strip_edges())

func _prepare_local_player_data() -> void:
	if name_edit and not name_edit.text.is_empty(): NetworkManager.local_player_data["name"] = name_edit.text
	if has_node("/root/SaveData") and SaveData.has_method("get_current_data") and SaveData.get_current_data() != null:
		var sd = SaveData.get_current_data()
		NetworkManager.local_player_data["skin"] = sd.get("equipped_skin", "default")
	else:
		NetworkManager.local_player_data["skin"] = "default"

func _on_network_success() -> void:
	status_label.text = "Connecté ! Attente de l'hôte..."
	join_button.disabled = true; host_button.disabled = true
func _on_network_failed() -> void: status_label.text = "Échec connexion."
func _on_player_list_updated() -> void: status_label.text = "Joueurs : " + str(NetworkManager.players.size()) + "/4"
