# =============================================================
# arena_base.gd — Arène tutoriel / arène de base
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
extends Node

@onready var wave_manager: Node = $WaveManager
@onready var tutorial_manager: TutorialManager = $TutorialManager
@onready var hud: Node = $HUD

# --- Boss ---
const BOSS_SCENE := preload("res://scenes/enemies/boss_lion.tscn")
var _boss: BossLion = null


func _ready() -> void:
	MusicManager.play("gameplay")

	TranslationServer.set_locale(SceneManager.current_lang)

	#TranslationServer.set_locale("es") # Espagnol pour le test
	# Générer les collisions manquantes pour la géométrie de cette scène.
	# Sans await : _ready() des enfants s'exécute avant celui du parent,
	# donc cet appel se termine AVANT celui du script racine du niveau.
	# Le CollisionManager détecte ensuite les StaticBody3D déjà créés → pas de doublon.
	CollisionManager.add_missing_collisions(self)

	# --- Labels HUD ---
	var wave_label:    Label   = hud.get_node_or_null("%WaveLabel")
	var message_label: Label   = hud.get_node_or_null("%MessageLabel")
	var enemies_label: Label   = hud.get_node_or_null("%EnemiesLabel")
	var step_label:    Label   = hud.get_node_or_null("%StepLabel")
	var panel:         Control = hud.get_node_or_null("%PanelContainer")

	wave_manager.setup_ui(wave_label, message_label, enemies_label, panel)

	# --- Vagues ---
	var waves: Array[WaveManager.WaveData] = [
		WaveManager.WaveData.new(1, 1, ""),   # Ennemi test post-tuto
		#WaveManager.WaveData.new(1, 1, tr("WAVE_MSG_1")),
		#WaveManager.WaveData.new(2, 1, tr("WAVE_MSG_2")),
		#WaveManager.WaveData.new(3, 2, tr("WAVE_MSG_FINAL")),
	]
	wave_manager.setup_waves(waves)

	# --- Tutoriel ---
	var player: Player = get_tree().get_first_node_in_group("player")
	tutorial_manager.setup(player, panel, message_label, step_label)
	tutorial_manager.tutorial_completed.connect(_on_tutorial_completed)
	tutorial_manager.start()

	# --- Connexion de fin de niveau ---
	wave_manager.all_waves_finished.connect(_on_waves_finished)


func _on_tutorial_completed() -> void:
	wave_manager.start()


# =============================================================
# BOSS
# =============================================================

func _on_waves_finished() -> void:
	# Les vagues normales sont terminées — spawner le boss
	_spawn_boss()


func _spawn_boss() -> void:
	MusicManager.play("boss")
	_boss = BOSS_SCENE.instantiate() as BossLion
	add_child(_boss)

	# Placer le boss en face du centre de l'arène (à 12 unités du joueur)
	var player: Player = get_tree().get_first_node_in_group("player")
	if player:
		var spawn_dir := Vector3(0.0, 0.0, -1.0)   # Côté opposé (ajuste si besoin)
		_boss.global_position = player.global_position + spawn_dir * 12.0
	else:
		_boss.global_position = Vector3(0.0, 0.0, -12.0)

	# Connexion des signaux
	_boss.boss_hp_changed.connect(_on_boss_hp_changed)
	_boss.boss_died.connect(_on_boss_died)

	# Afficher un message d'annonce
	var message_label: Label = hud.get_node_or_null("%MessageLabel")
	var panel: Control       = hud.get_node_or_null("%PanelContainer")
	if panel:
		panel.visible = true
	if message_label:
		message_label.text = tr("BOSS_LION_ANNOUNCE")
	await get_tree().create_timer(2.5).timeout
	if panel:
		panel.visible = false


func _on_boss_hp_changed(_current_hp: int, _max_hp: int) -> void:
	pass


func _on_boss_died() -> void:
	MusicManager.play("gameplay")
	# Activer la sortie et afficher le message de fin
	var exit_zone = $LevelExit
	exit_zone.activate()

	var message_label: Label = hud.get_node_or_null("%MessageLabel")
	if message_label:
		message_label.text = tr("MISSION_ACCOMPLISHED")
