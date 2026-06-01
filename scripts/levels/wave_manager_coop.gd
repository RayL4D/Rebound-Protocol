# =============================================================
# WaveManagerCoop.gd — Gestionnaire de vagues infinies pour la Coop
# =============================================================
class_name WaveManagerCoop
extends Node

# --- SIGNAUX ---
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal game_over

# --- ENUMS ---
enum WaveType { NORMAL, SPECIAL, BOSS }

# --- CONFIGURATION ---
@export_group("Dropships")
@export var dropship_scene: PackedScene
@export var dropship_spawn_points: Array[NodePath] = []

@export_group("Catalogue d'ennemis")
## Les ennemis de base (ex: chien, chat, vache, lapin)
@export var basic_enemies: Array[PackedScene] = [] 
## Les ennemis plus durs (ex: ours, gorille, etc.)
@export var advanced_enemies: Array[PackedScene] = [] 
## Les boss (ex: Boss Lion)
@export var bosses: Array[PackedScene] = [] 

@export_group("Paramètres de difficulté infinie")
@export var time_between_waves: float = 3.0
@export var base_enemy_count: int = 5
@export var enemies_per_wave_multiplier: float = 1.5

# --- VARIABLES INTERNES ---
var _current_wave: int = 0
var _enemies_alive: int = 0
var _is_running: bool = false
var _wave_completed: bool = false
var _spawn_positions: Array[Vector3] = []

# Gestion des joueurs en Coop
var _players: Array[Node] = []
var _players_alive: int = 0

# Références UI
var _wave_label: Label = null
var _message_label: Label = null
var _enemies_label: Label = null
var _panel: Control = null

# =============================================================
# INITIALISATION
# =============================================================

func _ready() -> void:
	TranslationServer.set_locale(SceneManager.current_lang)

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

func _find_players() -> void:
	_players = get_tree().get_nodes_in_group("player")
	_players_alive = _players.size()
	
	for p in _players:
		if p.has_signal("player_died") and not p.player_died.is_connected(_on_player_died):
			# On bind le joueur mort pour savoir qui c'est
			p.player_died.connect(_on_player_died.bind(p))

# =============================================================
# LOGIQUE PRINCIPALE DES VAGUES
# =============================================================

func start() -> void:
	if _is_running: return
	
	await get_tree().process_frame
	_find_players()

	if _players.is_empty():
		push_error("WaveManagerCoop : aucun joueur trouvé dans le groupe 'player' !")
		return

	_is_running = true
	_current_wave = 0
	_start_next_wave()

func _start_next_wave() -> void:
	if not _is_running: return
	
	_current_wave += 1
	_wave_completed = false
	
	var type = _determine_wave_type(_current_wave)
	_update_wave_label()
	
	var custom_msg = ""
	if type == WaveType.BOSS:
		custom_msg = tr("WARNING_BOSS_APPROACHING") # Ajoute cette clé dans tes traductions
	elif type == WaveType.SPECIAL:
		custom_msg = tr("WARNING_SPECIAL_WAVE")

	_show_message(tr("HUD_WAVE_COUNT_ENDLESS") % _current_wave + ("\n" + custom_msg if custom_msg != "" else ""))
	wave_started.emit(_current_wave)

	await get_tree().create_timer(time_between_waves).timeout
	
	if not _is_running: return
	
	_hide_message()
	_generate_and_spawn_wave(_current_wave, type)

# =============================================================
# GÉNÉRATION PROCÉDURALE
# =============================================================

func _determine_wave_type(wave_num: int) -> WaveType:
	if wave_num % 5 == 0:
		return WaveType.BOSS
	# 20% de chances d'avoir une vague spéciale (un seul type d'ennemi basique), sauf manche 1
	elif wave_num > 1 and randf() < 0.2:
		return WaveType.SPECIAL
	return WaveType.NORMAL

func _get_random_enemy(pool: Array[PackedScene]) -> PackedScene:
	if pool.is_empty(): return null
	return pool[randi() % pool.size()]

func _generate_and_spawn_wave(wave_num: int, type: WaveType) -> void:
	# Dictionnaire pour stocker les types d'ennemis et leur quantité
	var enemy_roster := {}
	var total_to_spawn := int(base_enemy_count + (wave_num * enemies_per_wave_multiplier))
	
	match type:
		WaveType.BOSS:
			var boss = _get_random_enemy(bosses)
			if boss:
				# 1 boss par défaut, on en rajoute 1 tous les 15 niveaux
				enemy_roster[boss] = 1 + int(wave_num / 15.0)
			
			# Minions qui accompagnent le boss
			var minion = _get_random_enemy(basic_enemies)
			if minion:
				enemy_roster[minion] = max(2, int(total_to_spawn * 0.4))
				
		WaveType.SPECIAL:
			# Vague Spéciale : Uniquement un type d'ennemi facile/basique
			var special_enemy = _get_random_enemy(basic_enemies)
			if special_enemy:
				enemy_roster[special_enemy] = total_to_spawn
				
		WaveType.NORMAL:
			# Vague classique : Mélange d'ennemis
			var num_types = randi_range(2, 3)
			var remaining = total_to_spawn
			
			for i in range(num_types):
				var selected_scene: PackedScene = null
				# La chance de spawn un ennemi avancé augmente avec les vagues (max 50%)
				if not advanced_enemies.is_empty() and randf() < min(0.05 * wave_num, 0.5):
					selected_scene = _get_random_enemy(advanced_enemies)
				else:
					selected_scene = _get_random_enemy(basic_enemies)
					
				if selected_scene:
					var amount = remaining if i == num_types - 1 else int(remaining / float(num_types - i))
					if enemy_roster.has(selected_scene):
						enemy_roster[selected_scene] += amount
					else:
						enemy_roster[selected_scene] = amount
					remaining -= amount

	# Calcul du total des ennemis pour l'UI
	_enemies_alive = 0
	for count in enemy_roster.values():
		_enemies_alive += count
		
	_update_enemies_label()
	
	if _enemies_alive <= 0:
		push_warning("WaveManagerCoop : Aucun ennemi n'a pu être généré (Vérifie tes tableaux exportés).")
		_complete_wave()
		return

	# Distribution dans les dropships
	var positions = _get_spawn_positions()
	if positions.is_empty(): return
	var pos_index = 0
	
	for enemy_scene in enemy_roster:
		var count: int = enemy_roster[enemy_scene]
		# On limite à 6 ennemis max par vaisseau pour éviter qu'ils ne se chevauchent trop
		var ships_needed = max(1, ceil(float(count) / 6.0))
		var base_per_ship = count / ships_needed
		var remainder = count % ships_needed
		
		for i in range(ships_needed):
			var final_count = base_per_ship + (1 if i < remainder else 0)
			if final_count > 0:
				_spawn_dropship(positions[pos_index % positions.size()], enemy_scene, final_count)
				pos_index += 1

func _spawn_dropship(pos: Vector3, enemy_scene: PackedScene, amount: int) -> void:
	if not dropship_scene: return
	
	var ship = dropship_scene.instantiate()
	ship.mob_scene = enemy_scene
	ship.spawn_count = amount
	ship.enemy_died_callback = _on_enemy_died
	
	get_tree().current_scene.add_child(ship)
	ship.global_position = pos

# =============================================================
# CALLBACKS & CONDITIONS DE FIN
# =============================================================

func _on_enemy_died() -> void:
	_enemies_alive = max(0, _enemies_alive - 1)
	_update_enemies_label()
	
	if _enemies_alive <= 0 and not _wave_completed:
		_complete_wave()

func _complete_wave() -> void:
	if _wave_completed: return
	
	_wave_completed = true
	wave_completed.emit(_current_wave)
	ScoreManager.add_wave()
	
	_show_message(tr("WAVE_CLEARED") % _current_wave)
	await get_tree().create_timer(2.5).timeout
	
	_hide_message()
	_start_next_wave()

func _on_player_died(_player: Node) -> void:
	_players_alive -= 1
	if _players_alive <= 0:
		_is_running = false
		_show_message(tr("UI_DEATH_MSG"))
		game_over.emit()

# =============================================================
# UI ET CONTRÔLE
# =============================================================

func _update_wave_label() -> void:
	if _wave_label:
		# Pas de max_waves ici puisqu'elles sont infinies
		_wave_label.text = tr("HUD_WAVE_COUNT_ENDLESS") % _current_wave

func _show_message(msg: String) -> void:
	if _panel: _panel.visible = true
	if _message_label: _message_label.text = msg

func _hide_message() -> void:
	if _panel: _panel.visible = false

func _update_enemies_label() -> void:
	if _enemies_label:
		_enemies_label.text = tr("HUD_ENEMIES_LEFT") % _enemies_alive

func stop() -> void:
	_is_running = false
	for p in _players:
		if is_instance_valid(p) and p.player_died.is_connected(_on_player_died):
			p.player_died.disconnect(_on_player_died)
	_players.clear()

func reset() -> void:
	stop()
	_current_wave = 0
	_enemies_alive = 0
	_wave_completed = false
