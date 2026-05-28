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
@onready var _dash_btn:   Control         = $DashButton
@onready var _zoom_in:    Control         = $ZoomInButton
@onready var _zoom_out:    Control         = $ZoomOutButton
@onready var _settings_btn: Control         = $SettingsButton

var _player: Player = null

# Mettre à true uniquement pour tester les joysticks sur PC en développement
const DEBUG_FORCE_MOBILE := false

# Layout auto-target : sauvegarde des rects d'origine
var _parry_orig_pos:    Vector2 = Vector2.ZERO
var _parry_orig_size:   Vector2 = Vector2.ZERO
var _right_joy_orig_pos:  Vector2 = Vector2.ZERO
var _right_joy_orig_size: Vector2 = Vector2.ZERO
var _auto_target_layout_active: bool = false

# --- Swipe caméra ---
## Sensibilité de la rotation yaw par pixel glissé (degrés/px).
const CAM_YAW_SENSITIVITY   := 0.35
## Sensibilité du pitch par pixel glissé (degrés/px).
const CAM_PITCH_SENSITIVITY := 0.25
## Distance minimale (px) avant de verrouiller l'axe du swipe.
const SWIPE_AXIS_THRESHOLD  := 14.0

# Dictionnaires indexés par finger_index
var _swipe_start : Dictionary = {}  # index -> Vector2 position de départ
var _swipe_used  : Dictionary = {}  # index -> bool  (swipe déjà consommé ce contact — sert au tap-detect)
var _swipe_axis  : Dictionary = {}  # index -> String "h" ou "v" (axe verrouillé)
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

	# S'assurer que le layout est appliqué APRÈS que les nœuds ont fini leur disposition
	call_deferred("_store_and_apply_layout")


func _process(_delta: float) -> void:
	if _player == null or _right_joy == null:
		return
	# Met à jour la direction uniquement quand le joystick est actif.
	# Au relâchement on NE remet PAS à zéro : le joueur et le bouclier
	# conservent leur dernière direction jusqu'au prochain mouvement.
	if _right_joy.is_pressed:
		_player._joystick_aim_dir = _right_joy.output

	# Surveiller les changements de l'option auto-target (modifiable depuis la pause)
	var want_auto := Settings.auto_target_enabled
	if want_auto != _auto_target_layout_active:
		_apply_layout()


# =============================================================
# LAYOUT AUTO-TARGET
# =============================================================

## Appelée en deferred après _ready() — à ce moment les nœuds ont leur taille réelle.
func _store_and_apply_layout() -> void:
	if _parry_btn != null:
		_parry_orig_pos  = _parry_btn.position
		_parry_orig_size = _parry_btn.size
	if _right_joy != null:
		_right_joy_orig_pos  = _right_joy.position
		_right_joy_orig_size = _right_joy.size
	_apply_layout()


## Adapte l'interface selon l'option auto-target :
##   • auto-target ON  → joystick droit masqué, bouton parry grand (bas-droite)
##   • auto-target OFF → joystick droit affiché, bouton parry taille normale
func _apply_layout() -> void:
	_auto_target_layout_active = Settings.auto_target_enabled

	if Settings.auto_target_enabled:
		# Désactiver complètement le joystick droit (visible + traitement input)
		# pour éviter qu'il intercepte les touches du bouton Parry superposé.
		if _right_joy != null:
			_right_joy.visible      = false
			_right_joy.process_mode = Node.PROCESS_MODE_DISABLED
		# Le bouton Parry prend la position et la taille de la BASE VISUELLE du joystick
		# (nœud enfant "Base" = cercle de 280 px) et non la zone d'interaction complète.
		if _parry_btn != null and _right_joy != null:
			var base_node := _right_joy.get_node_or_null("Base") as Control
			if base_node != null:
				var r := base_node.get_global_rect()
				_parry_btn.global_position = r.position
				_parry_btn.size            = r.size
			elif _right_joy_orig_size != Vector2.ZERO:
				# Fallback : zone d'interaction centrée avec taille réduite
				var center := _right_joy_orig_pos + _right_joy_orig_size * 0.5
				var sz     := 280.0
				_parry_btn.size     = Vector2(sz, sz)
				_parry_btn.position = center - Vector2(sz * 0.5, sz * 0.5)
	else:
		if _right_joy != null:
			_right_joy.visible      = true
			_right_joy.process_mode = Node.PROCESS_MODE_INHERIT
		if _parry_btn != null and _parry_orig_size != Vector2.ZERO:
			_parry_btn.position = _parry_orig_pos
			_parry_btn.size     = _parry_orig_size


# =============================================================
# SWIPE CAMÉRA
# =============================================================

func _input(event: InputEvent) -> void:
	if _player == null:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			# Détecter si ce doigt atterrit dans une zone joystick ou bouton
			if _is_in_joystick_area(event.position):
				_joy_fingers[event.index] = true
			else:
				_swipe_start[event.index] = event.position
				_swipe_used[event.index]  = false
		else:
			# Tap rapide hors zone bouton → changer de cible (auto-target activé)
			if Settings.auto_target_enabled and _player != null:
				if _swipe_start.has(event.index) and not _swipe_used.get(event.index, false):
					var start: Vector2 = _swipe_start[event.index]
					var moved: float   = start.distance_to(event.position)
					# Seuil < 20 px = tap, pas swipe
					if moved < 20.0 and not _is_in_joystick_area(start):
						_player.cycle_auto_target()
			# Nettoyage au relâchement
			_joy_fingers.erase(event.index)
			_swipe_start.erase(event.index)
			_swipe_used.erase(event.index)
			_swipe_axis.erase(event.index)

	elif event is InputEventScreenDrag:
		# Ignorer les doigts capturés par un joystick
		if _joy_fingers.get(event.index, false):
			return
		if not _swipe_start.has(event.index):
			return

		# Verrouillage d'axe : dès que le doigt a bougé assez, on choisit H ou V
		if not _swipe_axis.has(event.index):
			var total : Vector2 = event.position - _swipe_start[event.index]
			if abs(total.x) >= SWIPE_AXIS_THRESHOLD or abs(total.y) >= SWIPE_AXIS_THRESHOLD:
				_swipe_axis[event.index] = "h" if abs(total.x) >= abs(total.y) else "v"
		if not _swipe_axis.has(event.index):
			return  # Axe pas encore déterminé

		var rel  : Vector2 = event.relative
		var axis : String  = _swipe_axis[event.index]

		if axis == "h":
			# Glissement horizontal → rotation yaw fluide
			# Droite = orbite caméra gauche (sens Q), Gauche = orbite droite (sens E)
			_player._target_snap_yaw += rel.x * CAM_YAW_SENSITIVITY
		else:
			# Glissement vertical → pitch fluide
			# Vers le haut (rel.y < 0) → caméra remonte ; vers le bas → plonge
			_player._target_pitch = clamp(
				_player._target_pitch - rel.y * CAM_PITCH_SENSITIVITY,
				_player.cam_pitch_min,
				_player.cam_pitch_max
			)

		# Marquer comme utilisé pour le tap-detect (exclure du cycle de cible)
		_swipe_used[event.index] = true


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
	if _dash_btn  != null and _dash_btn.get_global_rect().has_point(pos):
		return true
	if _zoom_in   != null and _zoom_in.get_global_rect().has_point(pos):
		return true
	if _zoom_out     != null and _zoom_out.get_global_rect().has_point(pos):
		return true
	if _settings_btn != null and _settings_btn.get_global_rect().has_point(pos):
		return true
	return false
