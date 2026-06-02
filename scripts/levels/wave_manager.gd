# =============================================================
# WaveManager.gd — Gestionnaire de vagues générique et optimisé
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name WaveManager
extends Node

# --- SIGNAUX ---
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal all_waves_finished

# --- Structure d'une vague ---
class WaveData:
	var enemy_count: int
	var dropship_count: int
	var message: String
	# --- Sélection d'ennemi par index dans le catalogue ---
	var enemy_index: int = -1  # -1 = utiliser enemy_scene par défaut, sinon index dans enemy_catalog
	# --- boss ---	
	var enemy_scene: PackedScene = null 
	var dropship_mesh: PackedScene = null 

	func _init(p_count: int, p_ships: int, p_msg: String, p_enemy_idx: int = -1) -> void:
		enemy_count = p_count
		dropship_count = p_ships
		message = p_msg
		enemy_index = p_enemy_idx

# --- CONFIGURATION ---
@export_group("Dropships")
@export var dropship_scene: PackedScene
@export var dropship_spawn_points: Array[NodePath] = []

@export_group("Ennemis")
@export var enemy_scene: PackedScene  ## Ennemi par défaut (rétro-compatibilité)
@export var enemy_catalog: Array[PackedScene] = []  ## 📋 Catalogue d'ennemis : [0]=Dog, [1]=Cat, [2]=Lion...
@export var time_between_waves: float = 2.5

# --- VARIABLES INTERNES ---
var _waves: Array[WaveData] = []
var _current_wave: int = -1
var _enemies_alive: int = 0
var _is_running: bool = false
var _wave_completed: bool = false
var _spawn_positions: Array[Vector3] = []

# Références UI (assignées par arena_base.gd)
var _wave_label: Label = null
var _message_label: Label = null
var _enemies_label: Label = null
var _panel: Control = null

# Référence au joueur
var _player: Player = null
var _player_connected: bool = false
var _current_wave_data: WaveData = null


# =============================================================
# INITIALISATION
# =============================================================

func _ready() -> void:
	TranslationServer.set_locale(SceneManager.current_lang)

func _find_player() -> void:
	"""Trouve et stocke la référence au joueur"""
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_node is Player:
		_player = player_node
	else:
		push_warning("WaveManager: Joueur non trouvé dans le groupe 'player'")

# =============================================================
# CONFIGURATION
# =============================================================

func setup_waves(waves: Array[WaveData]) -> void:
	_waves = waves

func setup_ui(wave_label: Label, message_label: Label, enemies_label: Label = null, panel: Control = null) -> void:
	_wave_label = wave_label
	_message_label = message_label
	_enemies_label = enemies_label
	_panel = panel
	
	if _panel:
		_panel.visible = false

func setup_spawn_points(positions: Array[Vector3]) -> void:
	_spawn_positions = positions

func _get_spawn_positions() -> Array[Vector3]:
	if not _spawn_positions.is_empty():
		return _spawn_positions
	var result: Array[Vector3] = []
	for np in dropship_spawn_points:
		var n := get_node_or_null(np)
		if n is Node3D:
			result.append((n as Node3D).global_position)
	return result

# =============================================================
# DÉMARRAGE ET LOGIQUE PRINCIPALE
# =============================================================

func start() -> void:
	if _is_running:
		push_warning("WaveManager: Déjà en cours d'exécution")
		return

	await get_tree().process_frame
	_find_player()

	if not _player:
		push_error("WaveManager : aucun joueur trouvé dans le groupe 'player' !")
		return

	# Connexion au joueur sécurisée (une seule fois)
	if _player and not _player_connected:
		if not _player.player_died.is_connected(_on_player_died):
			_player.player_died.connect(_on_player_died)
			_player_connected = true

	_is_running = true
	_start_wave(0)

func _start_wave(index: int) -> void:
	if not _is_running:
		return

	if index >= _waves.size():
		_finish_all_waves()
		return

	_current_wave = index
	var wave: WaveData = _waves[index]
	_wave_completed = false

	var final_text = tr("HUD_WAVE_COUNT") % [index + 1, _waves.size()]
	if wave.message != null and wave.message != "":
		final_text += "\n" + tr(wave.message)

	_show_message(final_text)
	_update_wave_label()
	
	wave_started.emit(index + 1)

	await get_tree().create_timer(time_between_waves).timeout
	
	if not _is_running:
		return
		
	_hide_message()
	_spawn_wave(wave)

func _spawn_wave(wave: WaveData) -> void:
	_current_wave_data = wave
	_enemies_alive = wave.enemy_count
	_update_enemies_label()

	var positions: Array[Vector3] = _get_spawn_positions()
	if positions.is_empty():
		push_error("WaveManager : aucun point de spawn configuré !")
		return

	var ships := mini(wave.dropship_count, positions.size())
	# Prévention des divisions par zéro si dropship_count est 0
	var base_per_ship: int = int(float(wave.enemy_count) / float(ships)) if ships > 0 else 0
	var remainder: int = wave.enemy_count % ships if ships > 0 else 0

	for i in range(ships):
		var count := base_per_ship + (1 if i < remainder else 0)
		if count <= 0:
			continue
		_spawn_dropship(positions[i % positions.size()], count)

func _spawn_dropship(pos: Vector3, enemy_count: int) -> void:
	if not dropship_scene:
		push_error("WaveManager : dropship_scene non assigné !")
		return

	var ship = dropship_scene.instantiate()
	
	# 🎯 NOUVELLE LOGIQUE : Sélection de l'ennemi
	var selected_enemy: PackedScene = null
	
	# Priorité 1 : enemy_scene dans WaveData (pour boss custom)
	if _current_wave_data.enemy_scene:
		selected_enemy = _current_wave_data.enemy_scene
	# Priorité 2 : enemy_index dans le catalogue
	elif _current_wave_data.enemy_index >= 0 and _current_wave_data.enemy_index < enemy_catalog.size():
		selected_enemy = enemy_catalog[_current_wave_data.enemy_index]
	# Priorité 3 : enemy_scene par défaut (rétro-compatibilité)
	else:
		selected_enemy = enemy_scene
	
	if not selected_enemy:
		push_error("WaveManager : Aucun ennemi configuré pour cette vague !")
		ship.queue_free()
		return
	
	ship.mob_scene = selected_enemy
	ship.spawn_count = enemy_count
	ship.enemy_died_callback = _on_enemy_died
	ship.dropship_mesh = _current_wave_data.dropship_mesh

	get_tree().current_scene.add_child(ship)
	ship.global_position = pos


# =============================================================
# CALLBACKS
# =============================================================

func _highlight_remaining_enemies() -> void:
	# On récupère les nœuds grâce au groupe "enemies" que tu as défini dans Enemy.gd
	var active_enemies := get_tree().get_nodes_in_group("enemies")
	
	for enemy in active_enemies:
		# On s'assure que l'ennemi possède la méthode et qu'il n'est pas déjà mort/en train de mourir
		if enemy.has_method("toggle_highlight") and not enemy.get("is_dead"):
			enemy.toggle_highlight(true)
			
			
func _on_enemy_died() -> void:
	_enemies_alive -= 1
	_enemies_alive = max(0, _enemies_alive) # Sécurité pour ne pas passer en négatif
	_update_enemies_label()
	
	if _enemies_alive <= 3 and _enemies_alive > 0:
		_highlight_remaining_enemies()
	
	if _enemies_alive <= 0 and not _wave_completed:
		_complete_wave()

func _complete_wave() -> void:
	if _wave_completed:
		return
	
	_wave_completed = true
	wave_completed.emit(_current_wave + 1)
	ScoreManager.add_wave()
	
	_show_message(tr("WAVE_CLEARED") % (_current_wave + 1))
	await get_tree().create_timer(2.0).timeout
	
	if not _is_running:
		return
		
	_hide_message()
	_start_wave(_current_wave + 1)

func _finish_all_waves() -> void:
	_is_running = false
	all_waves_finished.emit()

func _on_player_died() -> void:
	_is_running = false
	_show_message(tr("UI_DEATH_MSG"))


# =============================================================
# UI
# =============================================================

func _update_wave_label() -> void:
	if _wave_label:
		_wave_label.text = tr("HUD_WAVE_COUNT") % [_current_wave + 1, _waves.size()]

func _show_message(msg: String) -> void:
	if _panel:
		_panel.visible = true
	if _message_label:
		_message_label.text = msg

func _hide_message() -> void:
	if _panel:
		_panel.visible = false

func _update_enemies_label() -> void:
	if _enemies_label:
		_enemies_label.text = tr("HUD_ENEMIES_LEFT") % _enemies_alive


# =============================================================
# CONTRÔLE
# =============================================================

func stop() -> void:
	"""Arrête le système de vagues"""
	_is_running = false
	
	# Déconnecter le joueur si connecté
	if _player and _player_connected:
		if _player.player_died.is_connected(_on_player_died):
			_player.player_died.disconnect(_on_player_died)
		_player_connected = false

func reset() -> void:
	"""Réinitialise le système"""
	stop()
	_current_wave = -1
	_enemies_alive = 0
	_wave_completed = false
