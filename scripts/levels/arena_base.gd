# =============================================================
# arena_base.gd — Arène tutoriel / arène de base
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
extends Node

@onready var wave_manager: Node = $WaveManager
@onready var tutorial_manager: TutorialManager = $TutorialManager
@onready var hud: Node = $HUD
@onready var hidden_save_point_1 = $SavePoint


func _ready() -> void:
	_prewarm_bullet_shaders()
	MusicManager.play("gameplay")
	AmbientManager.play("arena")
	TranslationServer.set_locale(SceneManager.current_lang)
	CollisionManager.add_missing_collisions(self)

	# --- Labels HUD ---
	var wave_label:    Label   = hud.get_node_or_null("%WaveLabel")
	var message_label: Label   = hud.get_node_or_null("%MessageLabel")
	var enemies_label: Label   = hud.get_node_or_null("%EnemiesLabel")
	var step_label:    Label   = hud.get_node_or_null("%StepLabel")
	var panel:         Control = hud.get_node_or_null("%PanelContainer")
	

	wave_manager.setup_ui(wave_label, message_label, enemies_label, panel)
	
	if hidden_save_point_1:
		hidden_save_point_1.visible = false
		hidden_save_point_1.process_mode = Node.PROCESS_MODE_DISABLED

	# --- Vagues ---
	var waves: Array[WaveManager.WaveData] = [
		WaveManager.WaveData.new(1, 1, tr("TUTO_STEP_5")),
		WaveManager.WaveData.new(2, 1, tr("WAVE_MSG_1")),
		WaveManager.WaveData.new(3, 2, tr("WAVE_MSG_FINAL")),
	]
	wave_manager.setup_waves(waves)

	# --- Tutoriel ---
	var player: Player = get_tree().get_first_node_in_group("player")
	tutorial_manager.setup(player, panel, message_label, step_label)
	tutorial_manager.tutorial_completed.connect(_on_tutorial_completed)
	tutorial_manager.start()
		
	wave_manager.all_waves_finished.connect(func():
		message_label.text = tr("MISSION_ACCOMPLISHED")
		var exit_zone = $Hangar_exit
		if hidden_save_point_1:
			hidden_save_point_1.visible = true
			hidden_save_point_1.process_mode = Node.PROCESS_MODE_INHERIT
		exit_zone.activate()
	)

	call_deferred("_deferred_restore_player")


## Force la compilation des shaders de balles dès le chargement de l'arène.
## Sans ça, la 1ère balle tirée provoque un freeze sur les PC moins puissants
## (Godot compile le shader StandardMaterial3D → émission + transparence à la volée).
## Un dummy bullet est ajouté hors-champ (Y=-500), rendu un frame, puis supprimé.
func _prewarm_bullet_shaders() -> void:
	const SCENE = preload("res://scenes/projectiles/bullet_enemy.tscn")
	var dummy: Node3D = SCENE.instantiate() as Node3D
	dummy.position = Vector3(0.0, -500.0, 0.0)
	add_child(dummy)
	await get_tree().process_frame
	if is_instance_valid(dummy):
		dummy.queue_free()


func _on_tutorial_completed() -> void:
	wave_manager.start()


# =============================================================
# RESTAURATION CHECKPOINT (filet de sécurité)
# =============================================================
func _deferred_restore_player() -> void:
	if SaveData.active_slot < 0:
		return  # Mode co-op ou aucun slot chargé — pas de restauration checkpoint
	var player: Player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	print("[ArenaBase] _deferred_restore_player — appel restore_from_checkpoint()")
	player.restore_from_checkpoint()
