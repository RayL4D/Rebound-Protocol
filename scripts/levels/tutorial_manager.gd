class_name TutorialManager
extends Node

signal tutorial_completed

# --- Références ---
var _player:        Player  = null
var _message_label: Label   = null
var _step_label:    Label   = null
var _panel:         Control = null

const TOTAL_STEPS := 5

# --- Flags ---
var _moved:   bool = false
var _jumped:  bool = false
var _parried: bool = false


func setup(player: Player, panel: Control, message_label: Label, step_label: Label) -> void:
	_player        = player
	_panel         = panel
	_message_label = message_label
	_step_label    = step_label
	_hide()


func start() -> void:
	_run_tutorial()


func _process(_delta: float) -> void:
	if not _player: return

	if not _moved:
		var horiz := Vector2(_player.velocity.x, _player.velocity.z)
		if horiz.length_squared() > 0.5: _moved = true

	if not _jumped and Input.is_action_just_pressed("jump"):
		_jumped = true

	if not _parried and Input.is_action_just_pressed("parry"):
		_parried = true


func _run_tutorial() -> void:
	# Étape 1 : Mouvement
	_moved = false
	_show(1, tr("TUTO_STEP_1"))
	while not _moved: await get_tree().process_frame
	_show(1, tr("TUTO_PERFECT"))
	await _pause(1.0)

	# Étape 2 : Caméra (Simple pause car pas de détection logicielle ici)
	_show(2, tr("TUTO_STEP_2"))
	await _pause(3.5)

	# Étape 3 : Saut
	_jumped = false
	_show(3, tr("TUTO_STEP_3"))
	while not _jumped: await get_tree().process_frame
	_show(3, tr("TUTO_GOOD_JOB"))
	await _pause(1.0)

	# Étape 4 : Parade
	_parried = false
	_show(4, tr("TUTO_STEP_4"))
	while not _parried: await get_tree().process_frame
	_show(4, tr("TUTO_EXCELLENT"))
	await _pause(1.0)

	# Étape 5 : Fin
	_show(5, tr("TUTO_STEP_5"))
	await _pause(2.5)

	_hide()
	tutorial_completed.emit()


func _pause(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _show(step: int, msg: String) -> void:
	if _panel: _panel.visible = true
	if _step_label: _step_label.text = tr("HUD_WAVE_COUNT") % [step, TOTAL_STEPS]
	if _message_label: _message_label.text = msg


func _hide() -> void:
	if _panel: _panel.visible = false
