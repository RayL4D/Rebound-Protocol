# =============================================================
# multiplayer_menu.gd — Menu de configuration multijoueur
# =============================================================
extends Control

# --- RÉFÉRENCES UI ---
@onready var name_edit: LineEdit = %NameEdit
@onready var ip_edit: LineEdit = %IPEdit
@onready var port_edit: LineEdit = %PortEdit
@onready var btn_host: Button = %BtnHost
@onready var btn_join: Button = %BtnJoin
@onready var btn_back: Button = %BtnBack
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	# Initialisation des valeurs par défaut
	if name_edit:
		name_edit.text = "Joueur_" + str(randi() % 1000)
	
	if ip_edit:
		ip_edit.text = "127.0.0.1"
	
	if port_edit:
		port_edit.text = str(NetworkManager.DEFAULT_PORT)
	
	# Connexion des signaux NetworkManager
	NetworkManager.connection_success.connect(_on_connection_success)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	
	# Sons UI
	_setup_ui_sounds()


func _setup_ui_sounds() -> void:
	"""Configure les sons de clic pour les boutons"""
	var click_sound = load("res://audio/sfx/ui/btn_click.wav")
	if click_sound:
		for btn in [btn_host, btn_join, btn_back]:
			if btn:
				btn.pressed.connect(func(): _play_ui_sound(click_sound))


func _play_ui_sound(stream: AudioStream) -> void:
	"""Joue un son UI temporaire"""
	if not stream:
		return
	
	var player = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


# =============================================================
# CALLBACKS BOUTONS
# =============================================================

func _on_btn_host_pressed() -> void:
	"""Créer une partie (serveur)"""
	_prepare_player_data()
	_update_port()
	
	status_label.text = "Création du serveur..."
	status_label.modulate = Color.YELLOW
	
	if NetworkManager.host_game() == OK:
		status_label.text = "Serveur créé ! En attente de joueurs..."
		status_label.modulate = Color.GREEN
		
		# Désactiver les boutons
		btn_host.disabled = true
		btn_join.disabled = true
		
		# Charger l'arène multijoueur après un court délai
		await get_tree().create_timer(1.0).timeout
		NetworkManager.load_arena_scene.rpc("res://scenes/levels/multiplayer/arena_multiplayer.tscn")
	else:
		status_label.text = "Erreur : impossible de créer le serveur"
		status_label.modulate = Color.RED


func _on_btn_join_pressed() -> void:
	"""Rejoindre une partie (client)"""
	_prepare_player_data()
	_update_port()
	
	var ip = ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	
	status_label.text = "Connexion à " + ip + "..."
	status_label.modulate = Color.YELLOW
	
	if NetworkManager.join_game(ip) == OK:
		# La confirmation viendra via le signal connection_success
		btn_host.disabled = true
		btn_join.disabled = true
	else:
		status_label.text = "Erreur : impossible de se connecter"
		status_label.modulate = Color.RED


func _on_btn_back_pressed() -> void:
	"""Retour au menu principal"""
	# Déconnecter si connecté
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	
	# Retour au menu principal
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# =============================================================
# GESTION DES DONNÉES
# =============================================================

func _prepare_player_data() -> void:
	"""Prépare les données du joueur local"""
	# Nom du joueur
	if name_edit and not name_edit.text.strip_edges().is_empty():
		NetworkManager.local_player_data["name"] = name_edit.text.strip_edges()
	else:
		NetworkManager.local_player_data["name"] = "Joueur_" + str(randi() % 1000)
	
	# Skin du joueur (depuis SaveData si disponible)
	if has_node("/root/SaveData") and SaveData.has_method("get_current_data"):
		var save_data = SaveData.get_current_data()
		if save_data:
			NetworkManager.local_player_data["skin"] = save_data.get("equipped_skin", "default")
		else:
			NetworkManager.local_player_data["skin"] = "default"
	else:
		NetworkManager.local_player_data["skin"] = "default"


func _update_port() -> void:
	"""Met à jour le port dans NetworkManager"""
	if port_edit:
		var port_text = port_edit.text.strip_edges()
		if port_text.is_valid_int():
			var port = port_text.to_int()
			if port > 0 and port < 65536:
				# Note: Vous devrez peut-être modifier NetworkManager.gd
				# pour permettre de changer le port dynamiquement
				pass


# =============================================================
# CALLBACKS RÉSEAU
# =============================================================

func _on_connection_success() -> void:
	"""Appelé quand la connexion réussit (client uniquement)"""
	status_label.text = "Connecté ! Attente du démarrage..."
	status_label.modulate = Color.GREEN


func _on_connection_failed() -> void:
	"""Appelé quand la connexion échoue"""
	status_label.text = "Échec de la connexion"
	status_label.modulate = Color.RED
	
	# Réactiver les boutons
	btn_host.disabled = false
	btn_join.disabled = false


func _on_player_list_changed() -> void:
	"""Appelé quand la liste des joueurs change"""
	var player_count = NetworkManager.players.size()
	status_label.text = "Joueurs connectés : %d/%d" % [player_count, NetworkManager.MAX_PLAYERS]
	status_label.modulate = Color.CYAN
