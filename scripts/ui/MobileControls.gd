# =============================================================
# MobileControls.gd — Contrôles tactiles
# Rebound Protocol
# =============================================================
# Attaché au nœud MobileControls dans mobile_controls.tscn.
# Les deux joysticks sont configurés directement dans l'éditeur
# Godot (positions, tailles, actions) — ce script ne fait
# qu'alimenter Player._joystick_aim_dir depuis le joystick droit.
# =============================================================
class_name MobileControls
extends CanvasLayer

@onready var _left_joy:  VirtualJoystick = $LeftJoystick
@onready var _right_joy: VirtualJoystick = $RightJoystick

var _player: Player = null


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		push_warning("MobileControls: joueur introuvable.")


func _process(_delta: float) -> void:
	if _player == null or _right_joy == null:
		return
	# Met à jour la direction uniquement quand le joystick est actif.
	# Au relâchement on NE remet PAS à zéro : le joueur et le bouclier
	# conservent leur dernière direction jusqu'au prochain mouvement.
	if _right_joy.is_pressed:
		_player._joystick_aim_dir = _right_joy.output
