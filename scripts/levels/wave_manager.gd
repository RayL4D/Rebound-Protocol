# =============================================================
# WaveManager.gd — Gestionnaire de vagues générique
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name WaveManager
extends Node

# --- Structure d'une vague ------------------------------------
class WaveData:
	var enemy_count: int
	var dropship_count: int
	var message: String

	func _init(p_count: int, p_ships: int, p_msg: String) -> void:
		enemy_count = p_count
		dropship_count = p_ships
		message = p_msg

@export var dropship_scene: PackedScene
@export var enemy_scene: PackedScene
@export var dropship_spawn_points: Array[NodePath] = []

# --- Références UI ---
var _wave_label: Label    = null
var _message_label: Label = null
var _enemies_label: Label = null

var _waves: Array[WaveData] = []
var _current_wave: int = -1
var _enemies_alive: int = 0
var _player: Player = null
var _spawn_positions: Array[Vector3] = []

func _ready() -> void:
	# On attend un frame pour que Player._ready() ait eu le temps
	# de faire add_to_group("player") avant qu'on le cherche
	await get_tree().process_frame

	_player = get_tree().get_first_node_in_group("player")
	if not _player:
		push_error("WaveManager : aucun joueur trouvé dans le groupe 'player' !")
		return

	_player.player_died.connect(_on_player_died)
	_start_wave(0)

func setup_waves(waves: Array[WaveData]) -> void:
	_waves = waves

## Appelé par arena_base.gd pour brancher les labels du HUD
func setup_ui(wave_label: Label, message_label: Label, enemies_label: Label = null) -> void:
	_wave_label     = wave_label
	_message_label  = message_label
	_enemies_label  = enemies_label
	if _message_label:
		_message_label.visible = false


# =============================================================
# LOGIQUE DE VAGUES
# =============================================================

func _start_wave(index: int) -> void:
	if index >= _waves.size():
		_on_all_waves_cleared()
		return

	_current_wave = index
	var wave: WaveData = _waves[index]

	_show_message("Vague %d / %d\n%s" % [index + 1, _waves.size(), wave.message])
	_update_wave_label()

	await get_tree().create_timer(2.5).timeout
	_hide_message()
	_spawn_wave(wave)


func _spawn_wave(wave: WaveData) -> void:
	_enemies_alive = wave.enemy_count
	_update_enemies_label()

	var positions: Array[Vector3] = _get_spawn_positions()
	if positions.is_empty():
		push_error("WaveManager : aucun point de spawn configuré !")
		return

	var ships := mini(wave.dropship_count, positions.size())
	var base_per_ship: int = int(float(wave.enemy_count) / float(ships))
	var remainder: int = wave.enemy_count % ships

	for i in range(ships):
		var count := base_per_ship + (1 if i < remainder else 0)
		if count <= 0:
			continue
		_spawn_dropship(positions[i % positions.size()], count)


func _spawn_dropship(pos: Vector3, enemy_count: int) -> void:
	if not dropship_scene:
		push_error("WaveManager : dropship_scene non assigné !")
		return

	var ship: Dropship = dropship_scene.instantiate()
	ship.mob_scene = enemy_scene
	ship.spawn_count = enemy_count
	ship.enemy_died_callback = _on_enemy_died

	get_tree().current_scene.add_child(ship)
	ship.global_position = pos


## Appelé par arena_base.gd pour définir les positions de spawn en code
func setup_spawn_points(positions: Array[Vector3]) -> void:
	_spawn_positions = positions

func _get_spawn_positions() -> Array[Vector3]:
	# Priorité aux positions passées en code, sinon on lit les NodePath de l'inspecteur
	if not _spawn_positions.is_empty():
		return _spawn_positions
	var result: Array[Vector3] = []
	for np in dropship_spawn_points:
		var n := get_node_or_null(np)
		if n is Node3D:
			result.append((n as Node3D).global_position)
	return result


# =============================================================
# CALLBACKS
# =============================================================

func _on_enemy_died() -> void:
	_enemies_alive -= 1
	_update_enemies_label()
	if _enemies_alive <= 0:
		_on_wave_cleared()


func _on_wave_cleared() -> void:
	_show_message("Vague %d terminée !" % (_current_wave + 1))
	await get_tree().create_timer(2.0).timeout
	_hide_message()
	_start_wave(_current_wave + 1)


func _on_player_died() -> void:
	_show_message("Tu es mort.\nRetour à la vague 1...")
	await get_tree().create_timer(2.5).timeout
	get_tree().reload_current_scene()


func _on_all_waves_cleared() -> void:
	_show_message("Arène terminée !\nBravo !")


# =============================================================
# UI
# =============================================================

func _update_wave_label() -> void:
	if _wave_label:
		_wave_label.text = "Vague %d / %d" % [_current_wave + 1, _waves.size()]


func _show_message(msg: String) -> void:
	if _message_label:
		_message_label.text    = msg
		_message_label.visible = true


func _hide_message() -> void:
	if _message_label:
		_message_label.visible = false


func _update_enemies_label() -> void:
	if _enemies_label:
		_enemies_label.text = "Ennemis : %d" % _enemies_alive
