# =============================================================
# MobileControls.gd — Contrôles tactiles
# Rebound Protocol
# =============================================================
# Attaché au nœud MobileControls dans mobile_controls.tscn.
# Les deux joysticks sont configurés directement dans l'éditeur
# Godot (positions, tailles, actions) — ce script ne fait
# qu'alimenter Player._joystick_aim_dir depuis le joystick droit.
#
# Swipe caméra :
#   • Horizontal → rotation de ±90° (même logique que Q / E clavier)
#   • Vertical   → ajustement du pitch de ±SWIPE_PITCH_STEP degrés,
#                  clampé entre cam_pitch_min et cam_pitch_max.
#   Le premier axe à dépasser son seuil remporte le geste.
#
# Bouton JUMP :
#   Géré directement dans JumpButton.gd via _gui_input — auto-suffisant,
#   trouve et appelle Player.request_jump() lui-même.
# =============================================================
class_name MobileControls
extends CanvasLayer

@onready var _left_joy:   VirtualJoystick = $LeftJoystick
@onready var _right_joy:  VirtualJoystick = $RightJoystick
@onready var _jump_btn:   Control         = $JumpButton
@onready var _parry_btn:  Control         = $ParryButton

var _player: Player = null

# Mettre à true uniquement pour tester les joysticks sur PC en développement
const DEBUG_FORCE_MOBILE := false

# --- Swipe caméra ---
## Distance horizontale minimale (pixels) pour valider un swipe de rotation yaw.
const SWIPE_MIN_X      := 40.0
## Distance verticale minimale (pixels) pour valider un swipe de pitch.
const SWIPE_MIN_Y      := 30.0
## Ratio minimal : le geste doit être dominé par l'axe qu'il cible.
const SWIPE_AXIS_RATIO := 1.5
## Pas de pitch par swipe vertical (degrés).
const SWIPE_PITCH_STEP := 15.0

# Dictionnaires indexés par finger_index
var _swipe_start : Dictionary = {}  # index -> Vector2 position de départ
var _swipe_used  : Dictionary = {}  # index -> bool  (swipe déjà consommé ce contact)
var _joy_fingers : Dictionary = {}  # index -> bool  (doigt appartenant à un joystick)


func _ready() -> void:
	# OS.has_feature("mobile") = true uniquement sur Android / iOS (build exporté)
	# On supprime le nœud entier sur toute autre plateforme sauf debug
	if not DEBUG_FORCE_MOBILE and not OS.has_feature("mobile"):
		queue_free()
		return

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


# =============================================================
# SWIPE CAMÉRA
# =============================================================

func _input(event: InputEvent) -> void:
	if _player == null:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			# Détecter si ce doigt atterrit dans une zone joystick
			if _is_in_joystick_area(event.position):
				_joy_fingers[event.index] = true
			else:
				_swipe_start[event.index] = event.position
				_swipe_used[event.index]  = false
		else:
			# Nettoyage au relâchement
			_joy_fingers.erase(event.index)
			_swipe_start.erase(event.index)
			_swipe_used.erase(event.index)

	elif event is InputEventScreenDrag:
		# Ignorer les doigts capturés par un joystick
		if _joy_fingers.get(event.index, false):
			return
		if not _swipe_start.has(event.index):
			return
		if _swipe_used.get(event.index, false):
			return

		var delta : Vector2 = event.position - _swipe_start[event.index]
		var abs_x : float   = abs(delta.x)
		var abs_y : float   = abs(delta.y)

		# --- Swipe horizontal : rotation yaw ±90° ---
		if abs_x >= SWIPE_MIN_X and abs_x > abs_y * SWIPE_AXIS_RATIO:
			_swipe_used[event.index] = true
			if delta.x > 0.0:
				# Glissement vers la droite → orbite caméra gauche (sens Q)
				_player._target_snap_yaw += 90.0
			else:
				# Glissement vers la gauche → orbite caméra droite (sens E)
				_player._target_snap_yaw -= 90.0

		# --- Swipe vertical : ajustement pitch ---
		elif abs_y >= SWIPE_MIN_Y and abs_y > abs_x * SWIPE_AXIS_RATIO:
			_swipe_used[event.index] = true
			if delta.y < 0.0:
				# Glissement vers le haut → caméra remonte (angle moins plongeant)
				_player._target_pitch = clamp(
					_player._target_pitch + SWIPE_PITCH_STEP,
					_player.cam_pitch_min,
					_player.cam_pitch_max
				)
			else:
				# Glissement vers le bas → caméra plonge (angle plus top-down)
				_player._target_pitch = clamp(
					_player._target_pitch - SWIPE_PITCH_STEP,
					_player.cam_pitch_min,
					_player.cam_pitch_max
				)


# Retourne true si la position écran appartient à un joystick ou au bouton JUMP.
# Ces zones sont exclues du swipe caméra.
func _is_in_joystick_area(pos: Vector2) -> bool:
	if _left_joy  != null and _left_joy.get_global_rect().has_point(pos):
		return true
	if _right_joy != null and _right_joy.get_global_rect().has_point(pos):
		return true
	if _jump_btn  != null and _jump_btn.get_global_rect().has_point(pos):
		return true
	if _parry_btn != null and _parry_btn.get_global_rect().has_point(pos):
		return true
	return false
