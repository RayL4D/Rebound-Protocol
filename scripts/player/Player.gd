# =============================================================
# Player.gd — Contrôleur principal du joueur
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Player
extends CharacterBody3D

# --- Exports (modifiables dans l'inspector Godot) ----------------
@export var move_speed: float     = 5.0
@export var jump_force: float     = 8.0
@export var fall_multiplier: float = 2.5  # Gravité multipliée pendant la chute
@export var max_hp: int           = 100
@export var rotation_speed: float    = 15.0  # Vitesse d'interpolation de la rotation
@export var cam_orbit_speed: float   = 90.0  # Degrés/seconde pour l'orbite Q/E
@export var iframe_duration: float   = 0.8   # Secondes d'invincibilité après un dégât

# --- Caméra ------------------------------------------------------
@export var zoom_min: float        = 3.0    # Distance minimale (zoom max)
@export var zoom_max: float        = 15.0   # Distance maximale (zoom min)
@export var zoom_speed: float      = 1.2    # Pas par cran de molette
@export var cam_pitch_min: float   = -85.0  # Angle le plus plongeant (presque top-down)
@export var cam_pitch_max: float   = -20.0  # Angle le plus rasant (quasi TPS)
@export var cam_sensitivity: float = 0.25   # Sensibilité du clic droit

# --- Références nœuds --------------------------------------------
@onready var spring_arm: SpringArm3D  = $SpringArm3D
@onready var shield: Node3D           = $Shield
@onready var robot_model: Node3D      = $RobotModel
@onready var camera: Camera3D         = $SpringArm3D/Camera3D
@onready var anim_tree: AnimationTree = $AnimationTree

# Texture du modèle — chargée une seule fois au démarrage
var _player_texture: Texture2D = preload("res://assets/textures/player/texture-g.png")

# --- Variables d'état --------------------------------------------
var current_hp: int
var is_dead: bool          = false
var _parry_requested: bool = false
var _was_on_floor: bool       = true   # Pour détecter l'atterrissage
var _land_sfx_anticipated: bool = false  # Vrai si le son de land a déjà été joué en anticipation

# --- Combo parry SFX -----------------------------------------------
const _PARRY_COMBO_WINDOW: float = 0.6   # Secondes avant que le combo reset
const _PARRY_COMBO_MAX:    int   = 5     # Nombre de hits max pour la montée de pitch
var _parry_combo:       int   = 0
var _parry_combo_timer: float = 0.0

# --- Pas de course -------------------------------------------------
# Intervalle entre deux pas — à ajuster selon la cadence de l'animation sprint
const _STEP_INTERVAL: float = 0.38
var _step_timer: float = 0.0   # Temps restant avant le prochain pas
var _step_foot:  bool  = false # false = step_a, true = step_b (alternance)
var _model_base_scale: Vector3     # Scale originale du RobotModel (lue dans _ready)
var _model_base_y: float = 0.0     # Offset Y du modèle dans l'éditeur (pour éviter le flottement)
var _invincible: bool    = false    # True pendant les iframes
var _iframe_tween: Tween = null     # Tween du clignotement

# --- Caméra runtime ----------------------------------------------
var _rmb_held:         bool  = false
var _cam_pitch:        float = -60.0  # Initialisé depuis le SpringArm dans _ready
var _cam_yaw:          float = 0.0    # Yaw courant (interpolé)
var _target_snap_yaw:  float = 0.0    # Yaw cible (multiple de 90°, accumule sans modulo)
var _target_pitch:     float = -60.0  # Pitch cible (interpolé vers _cam_pitch)
var _target_zoom:      float = 8.0    # Initialisé depuis le SpringArm dans _ready

# --- Mobile : direction du joystick droit (espace caméra) --------
var _joystick_aim_dir: Vector2 = Vector2.ZERO

# --- Cache pré-slide pour le stomp --------------------------------
# move_and_slide() modifie velocity.y quand on atterrit → on sauvegarde
# la valeur AVANT pour pouvoir vérifier la vitesse de chute réelle.
var _pre_slide_velocity_y: float = 0.0

# --- Mobile jump flag --------------------------------------------
# Posé par MobileControls._on_jump_pressed() entre deux physics frames.
# Consommé (reset) au début de _handle_jump() — évite tout problème de timing
# avec is_action_just_pressed qui peut rater un frame via parse_input_event.
var _mobile_jump_requested: bool = false

## Appelé par JumpButton quand le bouton JUMP est pressé.
func request_jump() -> void:
	_mobile_jump_requested = true

# --- Mobile parry flag -------------------------------------------
var _mobile_parry_requested: bool = false

## Appelé par ParryButton quand le bouton PARRY est pressé.
func request_parry() -> void:
	_mobile_parry_requested = true
	# Notifier le ParryTimer directement — bypasse Input.is_action_just_pressed
	# qui ne voit pas les appuis mobiles.
	var s := shield as Shield
	if s != null and s.parry_timer != null:
		s.parry_timer.notify_mobile_press()

# --- Stomp -------------------------------------------------------
const STOMP_DAMAGE:         int   = 25
const STOMP_FALL_THRESHOLD: float = -4.0   # vitesse Y min pour déclencher
const STOMP_BOUNCE:         float = 7.0    # rebond vertical après stomp
var   _stomp_hit_this_jump: bool  = false  # 1 stomp max par mise en l'air — reset à l'atterrissage sol

# --- Dash-bouclier -----------------------------------------------
const DASH_SPEED:     float = 20.0
const DASH_DURATION:  float = 0.20   # secondes
const DASH_COOLDOWN:  float = 1.20   # secondes
const DASH_DAMAGE:    int   = 12
const DASH_KNOCKBACK: float = 9.0

var _is_dashing:           bool  = false
var _dash_timer:           float = 0.0
var _dash_cooldown_timer:  float = 0.0
var _dash_dir:             Vector3 = Vector3.ZERO
var _dash_hit_enemies:     Array  = []   # ennemis déjà touchés dans ce dash
var _dash_ghost_timer:     float = 0.0   # timer pour l'espacement des afterimages
const DASH_GHOST_INTERVAL: float = 0.04  # une afterimage toutes les 40 ms

# Gravité récupérée depuis les paramètres projet Godot
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Valeurs de base avant application des upgrades (pour recalcul idempotent)
var _base_max_hp:     int   = 0
var _base_move_speed: float = 0.0

# Régénération HP passive (upgrade "hp_regen")
const _REGEN_INTERVALS: Array = [0.0, 30.0, 20.0, 12.0]  # index = palier
var _regen_timer:    float = 0.0
var _regen_interval: float = 0.0

# --- Sons joueur (null = pas encore chargé, pas de crash) --------
const _SFX_JUMP      : AudioStream = preload("res://audio/sfx/player/jump.wav")
const _SFX_LAND      : AudioStream = preload("res://audio/sfx/player/land.wav")
const _SFX_DASH      : AudioStream = preload("res://audio/sfx/player/dash.wav")
const _SFX_PARRY     : AudioStream = preload("res://audio/sfx/player/parry.wav")
const _SFX_HURT      : AudioStream = preload("res://audio/sfx/player/hurt.wav")
const _SFX_DIE       : AudioStream = preload("res://audio/sfx/player/die.wav")
const _SFX_STEP_A    : AudioStream = preload("res://audio/sfx/player/step_a.ogg")
const _SFX_STEP_B    : AudioStream = preload("res://audio/sfx/player/step_b.ogg")
const _SFX_STOMP_HIT : AudioStream = preload("res://audio/sfx/player/stomp_hit.wav")
const _SFX_DASH_HIT  : AudioStream = preload("res://audio/sfx/player/dash_hit.wav")

var _sfx:        AudioStreamPlayer = null   # Jump et effets généraux
var _sfx_land:   AudioStreamPlayer = null   # Land — séparé pour ne pas couper le jump
var _sfx_dash:   AudioStreamPlayer = null   # Dash — séparé pour ne pas couper le jump
var _sfx_parry:  AudioStreamPlayer = null   # Parry — séparé pour ne pas couper les autres
var _sfx_hurt:   AudioStreamPlayer = null   # Hurt — séparé pour ne pas couper les autres
var _sfx_step:   AudioStreamPlayer = null   # Pas de course (step_a / step_b)
var _sfx_impact: AudioStreamPlayer = null   # Stomp sur ennemi + dash hit

# --- Signaux -----------------------------------------------------
signal player_died
signal hp_changed(new_hp: int)
signal jumped          # Émis à chaque saut (clavier ET mobile)
signal parried         # Émis à chaque appui parade (clavier ET mobile)


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# ── Stocker les valeurs de base AVANT d'appliquer les upgrades ──
	_base_max_hp     = max_hp
	_base_move_speed = move_speed

	_apply_save_upgrades()

	current_hp = max_hp
	floor_snap_length = 0.3
	spring_arm.set_as_top_level(true)
	add_to_group("player")
	_apply_texture_recursive(robot_model)

	# Ajouter le layer des ennemis (16 = layer 5) au collision mask
	# pour que move_and_slide() détecte les collisions avec eux
	# (nécessaire pour le stomp et le dash-bouclier).
	collision_mask |= 16

	_model_base_scale = robot_model.scale      # Mémoriser la scale réelle du modèle
	_model_base_y     = robot_model.position.y # Mémoriser le Y offset configuré dans l'éditeur

	# Lire les valeurs initiales depuis le SpringArm configuré dans l'éditeur
	_cam_pitch        = spring_arm.rotation_degrees.x
	_target_pitch     = _cam_pitch   # Sync la cible pour éviter un lerp parasite au démarrage
	_cam_yaw          = spring_arm.rotation_degrees.y
	_target_snap_yaw  = _cam_yaw   # Synchroniser la cible sur l'angle initial
	_target_zoom      = spring_arm.spring_length

	# Restaurer la position du checkpoint IMMÉDIATEMENT, avant le premier frame
	# de physique. Sans ça, le joueur spawne à la position par défaut de la scène
	# pendant au moins un frame avant d'être téléporté.
	if SaveData.active_slot >= 0:
		var saved_pos := SaveData.get_player_position()
		if saved_pos != Vector3.ZERO:
			global_position = saved_pos

	# Positionner le spring arm sur la position finale du joueur (checkpoint ou défaut).
	# Évite que la caméra soit dans le corps du joueur pendant le premier frame rendu.
	spring_arm.global_position  = global_position + Vector3(0, 0.9, 0)
	spring_arm.rotation_degrees = Vector3(_cam_pitch, _cam_yaw, 0.0)
	spring_arm.spring_length    = _target_zoom

	# Stoppe l'AnimationPlayer brut du GLB — c'est l'AnimationTree qui prend
	# le relais pour piloter les états (idle/sprint/parry/die).
	var anim_player := robot_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		anim_player.stop()

	# AudioStreamPlayer pour les SFX joueur (bus SFX, polyphonie simple)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)

	# Player dédié au land — indépendant pour ne pas couper le son de jump
	_sfx_land = AudioStreamPlayer.new()
	_sfx_land.bus = "SFX"
	add_child(_sfx_land)

	# Player dédié au dash — indépendant pour ne pas couper le son de jump
	_sfx_dash = AudioStreamPlayer.new()
	_sfx_dash.bus = "SFX"
	add_child(_sfx_dash)

	# Player dédié au parry — AudioStreamPolyphonic pour le spam sans coupure
	_sfx_parry = AudioStreamPlayer.new()
	_sfx_parry.bus = "SFX"
	var _parry_poly := AudioStreamPolyphonic.new()
	_parry_poly.polyphony = 6
	_sfx_parry.stream = _parry_poly
	add_child(_sfx_parry)
	_sfx_parry.play()   # Lance le moteur polyphonique (silencieux en lui-même)

	# Player dédié au hurt
	_sfx_hurt = AudioStreamPlayer.new()
	_sfx_hurt.bus = "SFX"
	add_child(_sfx_hurt)

	# Player dédié aux pas de course
	_sfx_step = AudioStreamPlayer.new()
	_sfx_step.bus = "SFX"
	add_child(_sfx_step)

	# Player dédié aux impacts (stomp sur ennemi + dash hit)
	_sfx_impact = AudioStreamPlayer.new()
	_sfx_impact.bus = "SFX"
	add_child(_sfx_impact)

	# Restaurer les HP en deferred : le HUD (qui écoute hp_changed) n'est pas
	# encore connecté pendant _ready(), on attend la fin du frame.
	call_deferred("_restore_hp_from_save")


# =============================================================
# UPGRADES PERMANENTES (SaveData)
# =============================================================

## Lit les upgrades achetées dans SaveData et modifie les stats du joueur.
## Appelée une seule fois dans _ready(), avant l'initialisation des HP.
func _apply_save_upgrades() -> void:
	if SaveData.active_slot < 0:
		return   # Pas de slot actif (ex. lancement direct depuis l'éditeur)

	# HP maximum : +1 HP par palier (à partir de la base)
	max_hp = _base_max_hp + int(SaveData.get_upgrade_value("hp_max"))

	# Vitesse : +5 % par palier — toujours depuis _base_move_speed pour éviter
	# les multiplications en cascade si la fonction est rappelée
	move_speed = _base_move_speed * (1.0 + SaveData.get_upgrade_value("move_speed"))

	# Régénération HP passive — initialiser le timer au démarrage
	_update_regen_timer()


## Rappelée depuis la boutique après chaque achat pour appliquer l'effet immédiatement.
func refresh_upgrades() -> void:
	if SaveData.active_slot < 0:
		return

	var old_max_hp := max_hp

	# Recalcul idempotent depuis les valeurs de base
	max_hp     = _base_max_hp + int(SaveData.get_upgrade_value("hp_max"))
	move_speed = _base_move_speed * (1.0 + SaveData.get_upgrade_value("move_speed"))

	# Si max_hp a augmenté, les HP supplémentaires sont donnés au joueur directement
	if max_hp > old_max_hp:
		current_hp = min(current_hp + (max_hp - old_max_hp), max_hp)
		hp_changed.emit(current_hp)

	# Propager au bouclier (shield_size, shield_duration, parry_window)
	var s := shield as Shield
	if s:
		s.refresh_upgrades()

	# Mettre à jour le timer de régénération HP
	_update_regen_timer()


func _update_regen_timer() -> void:
	var tier := SaveData.get_upgrade_tier("hp_regen")
	if tier <= 0 or tier >= _REGEN_INTERVALS.size():
		_regen_interval = 0.0
	else:
		_regen_interval = _REGEN_INTERVALS[tier]
		if _regen_timer <= 0.0 or _regen_timer > _regen_interval:
			_regen_timer = _regen_interval   # Réinitialiser le timer


## Restaure les HP depuis la dernière sauvegarde.
## Appelée en deferred depuis _ready() — attend que le HUD soit connecté.
## La position est déjà restaurée directement dans _ready().
func _restore_hp_from_save() -> void:
	if SaveData.active_slot < 0:
		return

	var saved_hp := SaveData.get_player_hp()
	if saved_hp > 0:
		current_hp = min(saved_hp, max_hp)

	# Toujours émettre pour que le HUD affiche le bon HP dès le départ.
	hp_changed.emit(current_hp)

	# Si aucun checkpoint n'a encore été activé (HP sauvegardé = 0),
	# écrire le HP de départ sur disque pour que le slot affiche une valeur correcte.
	# Pièces et upgrades ne sont PAS sauvegardées ici — uniquement aux checkpoints.
	if SaveData.get_player_hp() == 0:
		SaveData.set_player_hp(current_hp)
		SaveData.save_current()

# Applique la texture sur tous les MeshInstance3D du modèle (tête, torse,
# bras, jambes) en un seul appel.
func _apply_texture_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _player_texture
		node.set_surface_override_material(0, mat)
	for child in node.get_children():
		_apply_texture_recursive(child)


func _physics_process(delta: float) -> void:
	if is_dead:
		# Garder la caméra orientée et en place pendant l'animation de mort.
		# On force spring_length = _target_zoom chaque frame : même si le spring arm
		# se contracte un instant (collision transitoire au moment de la mort avant
		# que collision_mask = 0 soit pris en compte), il est rétabli immédiatement.
		# Assignation atomique Vector3 pour éviter les artefacts Euler inter-composantes.
		_handle_camera_orbit(delta)
		spring_arm.global_position  = global_position + Vector3(0, 0.9, 0)
		spring_arm.rotation_degrees = Vector3(_cam_pitch, _cam_yaw, 0.0)
		spring_arm.spring_length    = _target_zoom
		return

	# Régénération HP passive
	if _regen_interval > 0.0:
		_regen_timer -= delta
		if _regen_timer <= 0.0:
			_regen_timer = _regen_interval
			if current_hp < max_hp:
				heal(1)

	_apply_gravity(delta)
	_check_land_anticipation()
	_handle_jump()
	_handle_camera_orbit(delta)
	_handle_movement()
	_handle_dash(delta)

	# Sauvegarder velocity.y avant toute modification (stomp / snap)
	_pre_slide_velocity_y = velocity.y

	# Stomp : raycast AVANT move_and_slide() pour que le rebond soit appliqué
	# en amont — Jolt Physics ne retourne pas toujours les CharacterBody3D
	# dans get_slide_collision() lors d'atterrissages successifs sur le même ennemi.
	_check_stomp()

	# Désactiver le snap sol si le joueur remonte (saut, rebond stomp…)
	if velocity.y > 0.0:
		floor_snap_length = 0.0

	move_and_slide()

	_check_dash_hits()

	# Spring arm mis à jour AVANT _rotate_toward_mouse : le raycast souris
	# utilise ainsi l'orientation de caméra du frame courant (et non du précédent).
	spring_arm.global_position  = global_position + Vector3(0, 0.9, 0)
	spring_arm.rotation_degrees = Vector3(_cam_pitch, _cam_yaw, 0.0)
	spring_arm.spring_length    = lerp(spring_arm.spring_length, _target_zoom, 10.0 * delta)

	_rotate_toward_mouse()

	# Déclenche l'animation de parade (clavier/gamepad ou bouton mobile)
	var mobile_parry := _mobile_parry_requested
	_mobile_parry_requested = false
	# Sur mobile, on n'accepte QUE le bouton dédié (mobile_parry).
	# is_action_just_pressed("parry") est ignoré car "Emulate Mouse From Touch"
	# le déclencherait sur chaque tap d'écran (parry = left mouse button).
	var keyboard_parry := Input.is_action_just_pressed("parry") and not OS.has_feature("mobile")
	if keyboard_parry or mobile_parry:
		_parry_requested = true
		parried.emit()
		_trigger_parry_sfx_combo()
		var pb := anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		pb.travel("parry")

	robot_model.position.x = 0.0
	robot_model.position.z = 0.0
	# robot_model.position.y est géré par _update_lean + l'offset éditeur
	_update_lean(delta)
	_update_animation()
	_tick_footstep(delta)

	# Décrémenter le timer du combo parry
	if _parry_combo_timer > 0.0:
		_parry_combo_timer -= delta
		if _parry_combo_timer <= 0.0:
			_parry_combo = 0


# =============================================================
# CAMÉRA
# =============================================================

func _input(event: InputEvent) -> void:
	if is_dead:
		return   # Bloquer tout input caméra/zoom pendant l'animation de mort

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				# Zoom avant — réduire la longueur du bras
				_target_zoom = clamp(_target_zoom - zoom_speed, zoom_min, zoom_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				# Zoom arrière — allonger le bras
				_target_zoom = clamp(_target_zoom + zoom_speed, zoom_min, zoom_max)
			MOUSE_BUTTON_RIGHT:
				# Mémoriser l'état du clic droit pour le drag
				_rmb_held = event.pressed

	# Pitch de la caméra avec clic droit maintenu (vertical seulement)
	if event is InputEventMouseMotion and _rmb_held:
		_target_pitch -= event.relative.y * cam_sensitivity
		_target_pitch  = clamp(_target_pitch, cam_pitch_min, cam_pitch_max)

	# Orbite par snap de 90° — détection ici pour éviter la répétition du held
	if event is InputEventKey and event.pressed and not event.echo:
		if Input.is_action_just_pressed("cam_orbit_left"):
			_target_snap_yaw += 90.0
		elif Input.is_action_just_pressed("cam_orbit_right"):
			_target_snap_yaw -= 90.0


# =============================================================
# ORBITE CAMÉRA (Q / E)
# =============================================================

func _handle_camera_orbit(delta: float) -> void:
	# Interpolation fluide vers les angles cibles
	# Le yaw accumule sans modulo pour éviter les sauts 359° → 0°
	_cam_yaw   = lerp(_cam_yaw,   _target_snap_yaw, 10.0 * delta)
	_cam_pitch = lerp(_cam_pitch, _target_pitch,    10.0 * delta)


# =============================================================
# MOUVEMENT
# =============================================================

func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		# Sol : annuler uniquement si le joueur ne remonte pas déjà
		# (un stomp ou un saut vient de fixer velocity.y > 0 → ne pas l'écraser)
		velocity.y = 0.0
	elif velocity.y < 0.0:
		# Chute : gravité renforcée pour éviter le flottement
		velocity.y -= gravity * fall_multiplier * delta
	else:
		# Montée : gravité normale
		velocity.y -= gravity * delta


func _handle_jump() -> void:
	var on_floor    := is_on_floor()
	var mobile_jump := _mobile_jump_requested
	_mobile_jump_requested = false   # consommé immédiatement, même si le saut échoue

	if (Input.is_action_just_pressed("jump") or mobile_jump) and on_floor:
		velocity.y             = jump_force
		floor_snap_length      = 0.0
		_land_sfx_anticipated  = false   # Réinitialiser pour le prochain atterrissage
		jumped.emit()
		_play_sfx(_SFX_JUMP, -9.0, randf_range(0.96, 1.04))
		_squash_stretch_jump()
	elif on_floor and not _was_on_floor:
		floor_snap_length = 0.3
		# Recharger le stomp seulement si on atterrit sur le sol réel,
		# pas sur la tête d'un ennemi.
		if not _standing_on_enemy():
			_stomp_hit_this_jump = false
			if not _land_sfx_anticipated:   # Ne pas rejouer si déjà déclenché en anticipation
				_play_land_sfx()
			_land_sfx_anticipated = false   # Réinitialiser pour le prochain saut
			_squash_stretch_land()
	elif on_floor:
		floor_snap_length = 0.3

	_was_on_floor = on_floor


# Retourne true si la surface sous le joueur (collisions du frame précédent)
# est la tête d'un ennemi plutôt que le sol de la géométrie.
func _standing_on_enemy() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y > 0.5 and col.get_collider() is Enemy:
			return true
	return false


# Tilt du modèle selon la vélocité verticale — donne l'impression d'un arc
func _update_lean(delta: float) -> void:
	# velocity.y positif = montée → penche en arrière
	# velocity.y négatif = chute → penche en avant
	var target_tilt: float = clamp(-velocity.y * 0.03, -0.3, 0.3)
	robot_model.rotation.x   = lerp(robot_model.rotation.x,   target_tilt,    12.0 * delta)
	robot_model.position.y   = lerp(robot_model.position.y,   _model_base_y,  12.0 * delta)


# Squash & stretch au décollage
func _squash_stretch_jump() -> void:
	var b := _model_base_scale
	var tween := create_tween()
	tween.tween_property(robot_model, "scale", Vector3(b.x * 1.2, b.y * 0.7,  b.z * 1.2),  0.07)
	tween.tween_property(robot_model, "scale", Vector3(b.x * 0.85, b.y * 1.3, b.z * 0.85), 0.12)
	tween.tween_property(robot_model, "scale", b,                                            0.18)


# Squash & stretch à l'atterrissage
func _squash_stretch_land() -> void:
	var b := _model_base_scale
	var tween := create_tween()
	tween.tween_property(robot_model, "scale", Vector3(b.x * 1.3,  b.y * 0.65, b.z * 1.3),  0.06)
	tween.tween_property(robot_model, "scale", Vector3(b.x * 0.92, b.y * 1.1,  b.z * 0.92), 0.09)
	tween.tween_property(robot_model, "scale", b,                                             0.1)


func _handle_movement() -> void:
	var input_x: float = Input.get_axis("move_left", "move_right")
	var input_z: float = Input.get_axis("move_forward", "move_backward")

	var input_dir := Vector2(input_x, input_z)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	# Déplacement relatif à la caméra — on lit directement la base de la caméra
	# plutôt que de recalculer depuis le yaw, pour éviter tout désalignement.
	var cb        := camera.global_transform.basis
	var cam_fwd   := -Vector3(cb.z.x, 0.0, cb.z.z).normalized()   # -Z local projeté au sol
	var cam_right :=  Vector3(cb.x.x, 0.0, cb.x.z).normalized()   # +X local projeté au sol

	# input_dir.y est négatif quand "move_forward" est pressé (convention get_axis)
	# → on l'inverse pour que cam_fwd corresponde bien à "avancer"
	var move := cam_right * input_dir.x - cam_fwd * input_dir.y
	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed


# =============================================================
# ROTATION VERS LA SOURIS
# =============================================================

func _rotate_toward_mouse() -> void:
	# --- Joystick mobile prioritaire ---
	if _joystick_aim_dir.length_squared() > 0.04:
		var cb        := camera.global_transform.basis
		var cam_right := Vector3(cb.x.x, 0.0, cb.x.z).normalized()
		var cam_fwd   := -Vector3(cb.z.x, 0.0, cb.z.z).normalized()
		var world_dir := cam_right * _joystick_aim_dir.x - cam_fwd * _joystick_aim_dir.y
		world_dir.y   = 0.0
		if world_dir.length_squared() > 0.01:
			robot_model.global_rotation.y = atan2(world_dir.x, world_dir.z)
		return

	# --- Souris (desktop) ---
	var mouse_pos     := get_viewport().get_mouse_position()
	var ray_origin    := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)

	var look_dir := Vector3.ZERO

	if abs(ray_direction.y) > 0.001:
		var t := (global_position.y - ray_origin.y) / ray_direction.y
		if t > 0.0:
			# Intersection normale avec le plan du sol → on tourne vers ce point
			var target_point := ray_origin + ray_direction * t
			look_dir = (target_point - global_position)
			look_dir.y = 0.0

	# Souris vers le ciel (t ≤ 0) → projection horizontale du rayon :
	# si la souris est en haut à droite, le rayon pointe en haut à droite en 3D,
	# on ignore juste son Y pour garder la direction latérale correcte.
	if look_dir.length_squared() < 0.01:
		look_dir = Vector3(ray_direction.x, 0.0, ray_direction.z)

	if look_dir.length_squared() < 0.01:
		return

	# Assigner directement en global_rotation.y (espace monde),
	# identique à ce que fait le bouclier — pas de lag, pas d'offset.
	robot_model.global_rotation.y = atan2(look_dir.x, look_dir.z)


# =============================================================
# ANIMATIONS
# =============================================================

func _update_animation() -> void:
	var playback := anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

	if is_dead:
		playback.travel("die")
		return

	var current := playback.get_current_node()

	# _parry_requested bloque les frames de transition entre l'appel de
	# travel("parry") et le moment où le state machine entre réellement dans
	# cet état — sans ça, _update_animation écrase la demande dès le frame suivant.
	if _parry_requested:
		if current == "parry":
			_parry_requested = false  # Entrée confirmée, le flag n'est plus nécessaire
		return  # Dans tous les cas on attend, qu'on soit en transition ou dedans

	# L'animation de parade joue jusqu'à la fin (transition AtEnd → idle automatique)
	if current == "parry":
		return

	# Déplacement horizontal uniquement (on ignore Y pour ne pas switcher en l'air)
	var is_moving := Vector2(velocity.x, velocity.z).length_squared() > 0.1
	if is_moving:
		playback.travel("sprint")
	else:
		playback.travel("idle")




# =============================================================
# STOMP (saut écrasant)
# =============================================================

# Détecte un ennemi sous le joueur via raycast et applique le rebond
# AVANT move_and_slide() — évite les problèmes de Jolt Physics qui ne retourne
# pas toujours les CharacterBody3D dans get_slide_collision() lors d'atterrissages
# successifs sur le même ennemi.
func _check_stomp() -> void:
	# Pas assez de vitesse descendante → pas un stomp
	if _pre_slide_velocity_y > STOMP_FALL_THRESHOLD:
		return

	# Sphere cast aux pieds du joueur (layer 16 = ennemis uniquement).
	# Plus robuste qu'un rayon unique : couvre les bords et coins de l'ennemi
	# même si le joueur n'est pas parfaitement centré au-dessus.
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4  # Légèrement plus large que la capsule du joueur (r=0.25)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape          = sphere
	query.transform      = Transform3D(Basis.IDENTITY, global_position + Vector3.DOWN * 0.9)
	query.collision_mask = 16
	query.exclude        = [get_rid()]

	var results := space.intersect_shape(query, 1)
	if results.is_empty():
		return

	var body = results[0].get("collider")
	if not (body is Enemy):
		return

	var enemy := body as Enemy
	if enemy.stomp_immune:
		return

	# Rebond — toujours actif, permet de rebondir sur le même ennemi
	velocity.y = STOMP_BOUNCE

	# Son + animation joués à chaque rebond sur un ennemi
	enemy.stomp_squish()
	if _SFX_STOMP_HIT and _sfx_impact:
		_sfx_impact.stream      = _SFX_STOMP_HIT
		_sfx_impact.volume_db   = 6.0
		_sfx_impact.pitch_scale = randf_range(0.95, 1.05)
		_sfx_impact.play()

	# Dégâts uniquement au premier contact depuis le dernier atterrissage sol
	if not _stomp_hit_this_jump:
		_stomp_hit_this_jump = true
		enemy.take_damage(STOMP_DAMAGE, true)   # silent_hurt — le stomp a son propre son


# =============================================================
# DASH-BOUCLIER
# =============================================================

# Gère le cooldown, détecte l'appui Shift et pilote le dash.
# Appelé AVANT move_and_slide() pour que le dash soit actif ce frame.
func _handle_dash(delta: float) -> void:
	# Tick du cooldown
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer -= delta

	# Dash en cours : décompte la durée et écrase velocity horizontale.
	# NOTE : appelé APRÈS _handle_movement(), donc cet override est définitif.
	if _is_dashing:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_is_dashing = false
			_dash_hit_enemies.clear()
		else:
			velocity.x = _dash_dir.x * DASH_SPEED
			velocity.z = _dash_dir.z * DASH_SPEED
			# Afterimages périodiques pendant le dash
			_dash_ghost_timer -= delta
			if _dash_ghost_timer <= 0.0:
				_dash_ghost_timer = DASH_GHOST_INTERVAL
				_spawn_dash_ghost()
		return  # Pendant le dash on n'accepte pas de nouveau déclenchement

	# Déclenchement : touche dash pressée + cooldown écoulé
	if Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
		_start_dash()


# Initialise la direction et les timers du dash.
func _start_dash() -> void:
	# Direction prioritaire : mouvement clavier/joystick courant
	var input_x: float = Input.get_axis("move_left", "move_right")
	var input_z: float = Input.get_axis("move_forward", "move_backward")
	var input_v := Vector2(input_x, input_z)

	var cb        := camera.global_transform.basis
	var cam_fwd   := -Vector3(cb.z.x, 0.0, cb.z.z).normalized()
	var cam_right :=  Vector3(cb.x.x, 0.0, cb.x.z).normalized()

	if input_v.length_squared() > 0.04:
		_dash_dir = (cam_right * input_v.x - cam_fwd * input_v.y).normalized()
	else:
		_dash_dir = -robot_model.global_transform.basis.z

	_dash_dir.y  = 0.0
	_dash_dir    = _dash_dir.normalized()

	_is_dashing          = true
	_dash_timer          = DASH_DURATION
	_dash_cooldown_timer = DASH_COOLDOWN
	_dash_ghost_timer    = 0.0
	_dash_hit_enemies.clear()

	if _SFX_DASH and _sfx_dash:
		_sfx_dash.stream      = _SFX_DASH
		_sfx_dash.volume_db   = -6.0
		_sfx_dash.pitch_scale = randf_range(0.97, 1.03)
		_sfx_dash.play()
	_dash_fx_start()


# Effets visuels au déclenchement du dash.
func _dash_fx_start() -> void:
	# 1. Étirement du modèle dans la direction du dash (squash & stretch)
	var b := _model_base_scale
	var tw := create_tween()
	tw.tween_property(robot_model, "scale",
		Vector3(b.x * 0.65, b.y * 0.65, b.z * 1.55), 0.06)
	tw.tween_property(robot_model, "scale", b, DASH_DURATION + 0.12) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# 2. Bump de FOV de la caméra (sensation de vitesse)
	var orig_fov := camera.fov
	var tw_fov   := create_tween()
	tw_fov.tween_property(camera, "fov", orig_fov + 18.0, 0.06)
	tw_fov.tween_property(camera, "fov", orig_fov,         DASH_DURATION + 0.15) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 3. Première afterimage immédiate
	_spawn_dash_ghost()


# Crée une afterimage fantôme à la position courante du joueur.
func _spawn_dash_ghost() -> void:
	if not is_inside_tree():
		return

	# Matériau partagé pour toutes les meshes de ce fantôme (fade simultané)
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(0.45, 0.85, 1.0, 0.55)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true

	# Conteneur positionné dans la scène (ne suit plus le joueur)
	var container := Node3D.new()
	get_tree().current_scene.add_child(container)
	_ghost_meshes_recursive(robot_model, container, mat)

	# Fondu en 0.25 s puis libération
	var tw := container.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(container.queue_free)


# Duplique récursivement chaque MeshInstance3D du modèle avec sa transform globale.
func _ghost_meshes_recursive(node: Node, container: Node3D, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var src   := node as MeshInstance3D
		var ghost := MeshInstance3D.new()
		ghost.mesh              = src.mesh
		ghost.global_transform  = src.global_transform
		ghost.set_surface_override_material(0, mat)
		container.add_child(ghost)
	for child in node.get_children():
		_ghost_meshes_recursive(child, container, mat)


# Détecte les ennemis touchés pendant le dash via les collisions de move_and_slide().
func _check_dash_hits() -> void:
	if not _is_dashing:
		return

	for i in get_slide_collision_count():
		var col  := get_slide_collision(i)
		var body := col.get_collider()
		if body is Enemy and not _dash_hit_enemies.has(body):
			var enemy := body as Enemy
			_dash_hit_enemies.append(enemy)
			enemy.take_damage(DASH_DAMAGE, true)   # silent_hurt — le dash a son propre son d'impact
			# Knockback dans la direction du dash
			enemy.apply_knockback(_dash_dir, DASH_KNOCKBACK)
			if _SFX_DASH_HIT and _sfx_impact:
				_sfx_impact.stream      = _SFX_DASH_HIT
				_sfx_impact.volume_db   = 0.0
				_sfx_impact.pitch_scale = randf_range(0.95, 1.05)
				_sfx_impact.play()


# =============================================================
# SANTÉ
# =============================================================

func take_damage(amount: int) -> void:
	if is_dead or _invincible:
		return

	# Réduction de dégâts permanente (upgrade "damage_reduction")
	var reduction := SaveData.get_upgrade_value("damage_reduction") if SaveData.active_slot >= 0 else 0.0
	var final_dmg := int(round(float(amount) * (1.0 - reduction)))
	final_dmg      = max(1, final_dmg)   # minimum 1 dégât toujours

	current_hp = max(0, current_hp - final_dmg)
	hp_changed.emit(current_hp)

	if current_hp == 0:
		_die()
	else:
		if _SFX_HURT and _sfx_hurt:
			_sfx_hurt.stream      = _SFX_HURT
			_sfx_hurt.volume_db   = -8.0
			_sfx_hurt.pitch_scale = randf_range(0.94, 1.06)
			_sfx_hurt.play()
		_start_iframes()


# Invincibilité temporaire avec clignotement visuel
func _start_iframes() -> void:
	_invincible = true

	# Clignotement : Node3D n'a pas modulate, on toggle la visibilité
	if _iframe_tween:
		_iframe_tween.kill()
	_iframe_tween = create_tween().set_loops()
	_iframe_tween.tween_callback(func(): robot_model.visible = not robot_model.visible)
	_iframe_tween.tween_interval(0.08)

	# Attendre la fin de la durée d'invincibilité
	await get_tree().create_timer(iframe_duration).timeout

	# Remettre le modèle visible
	_invincible = false
	if _iframe_tween:
		_iframe_tween.kill()
		_iframe_tween = null
	robot_model.visible = true


func heal(amount: int) -> void:
	if is_dead:
		return

	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp)


func _die() -> void:
	is_dead = true

	# Stopper le clignotement des iframes si actif au moment de la mort
	if _iframe_tween:
		_iframe_tween.kill()
		_iframe_tween = null
	robot_model.visible = true

	# Figer le spring arm à sa longueur courante et désactiver sa détection
	# de collision : sans ça, le mesh de l'animation de mort entre en collision
	# avec le bras, qui se raccourcit à zéro et met la caméra dans le corps.
	spring_arm.spring_length  = _target_zoom
	spring_arm.collision_mask = 0

	# Déclenché ici directement car _physics_process retourne immédiatement
	# quand is_dead est true — _update_animation() ne serait jamais appelée.
	_play_sfx(_SFX_DIE, -4.0)
	var playback := anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	playback.travel("die")
	player_died.emit()


# =============================================================
# SFX HELPER
# =============================================================

## Gère le timer des pas de course : joue step_a / step_b en alternance quand
## le joueur est au sol, en mouvement, et hors dash.
func _tick_footstep(delta: float) -> void:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or horiz_speed < 0.5 or _is_dashing:
		# Réinitialiser le timer pour éviter un double-claquement au retour au sol
		_step_timer = _STEP_INTERVAL * 0.5
		return

	# Intervalle dynamique : plus on va vite, plus les pas sont rapides
	var dynamic_interval: float = clamp(remap(horiz_speed, 0.0, move_speed, 0.45, 0.26), 0.26, 0.45)

	_step_timer -= delta
	if _step_timer > 0.0:
		return

	_step_timer = dynamic_interval

	# Alterner pied gauche / pied droit avec légère variation de pitch
	var stream: AudioStream = _SFX_STEP_B if _step_foot else _SFX_STEP_A
	_step_foot = not _step_foot

	if _sfx_step == null:
		return
	_sfx_step.stream      = stream
	_sfx_step.volume_db   = -16.0 + randf_range(-1.0, 1.0)
	_sfx_step.pitch_scale = 1.0   + randf_range(-0.04, 0.04)
	_sfx_step.play()


## Combo parry : pitch et volume montent à chaque parry consécutif dans la fenêtre de temps.
func _trigger_parry_sfx_combo() -> void:
	_parry_combo       = min(_parry_combo + 1, _PARRY_COMBO_MAX)
	_parry_combo_timer = _PARRY_COMBO_WINDOW
	# Chaque hit dans le combo monte de ~5 % de pitch et +0.8 dB
	var pitch: float = 1.0 + (_parry_combo - 1) * 0.05 + randf_range(-0.02, 0.02)
	var vol:   float = -5.0 + (_parry_combo - 1) * 0.8
	_play_parry_sfx(_SFX_PARRY, vol, pitch)


## Joue un son sur le moteur polyphonique du parry — plusieurs instances simultanées possibles.
func _play_parry_sfx(stream: AudioStream, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null or _sfx_parry == null:
		return
	var pb := _sfx_parry.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if pb:
		pb.play_stream(stream, 0.0, vol_db, pitch)


func _play_sfx(stream: AudioStream, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null or _sfx == null:
		return
	_sfx.stream      = stream
	_sfx.volume_db   = vol_db
	_sfx.pitch_scale = pitch
	_sfx.play()


## Son de land : volume adapté à la vitesse de chute, silencieux pour les micro-atterrissages.
func _play_land_sfx() -> void:
	if _SFX_LAND == null or _sfx_land == null:
		return
	var fall_speed: float = absf(_pre_slide_velocity_y)
	# En dessous de ce seuil (ex. descente d'une légère marche) : pas de son
	if fall_speed < 1.2:
		return
	# Volume qui monte avec la vitesse : chute douce → -14 dB, chute dure → -3 dB
	var vol:   float = clamp(remap(fall_speed, 1.2, 8.0, -14.0, -3.0), -14.0, -3.0)
	# Pitch légèrement plus grave pour les atterrissages lourds
	var pitch: float = clamp(remap(fall_speed, 1.2, 8.0, 1.05, 0.92), 0.92, 1.05)
	_sfx_land.stream      = _SFX_LAND
	_sfx_land.volume_db   = vol
	_sfx_land.pitch_scale = pitch
	_sfx_land.play()


## Joue le son de land légèrement avant l'impact réel pour compenser la latence audio.
## Utilise un raycast vers le bas : si le sol est à moins de ANTICIPATION_DIST mètres
## pendant une chute, le son est déclenché immédiatement.
func _check_land_anticipation() -> void:
	# Ne pas anticiper si déjà joué, déjà au sol, ou vitesse insuffisante
	if _land_sfx_anticipated or is_on_floor() or velocity.y > -1.2:
		return

	# Distance d'anticipation proportionnelle à la vitesse de chute
	# (plus on tombe vite, plus on anticipe tôt pour garder le même décalage temporel)
	var anticipation_dist: float = clamp(absf(velocity.y) * 0.30, 0.05, 0.18)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * anticipation_dist,
		collision_mask
	)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)

	if not result.is_empty():
		_land_sfx_anticipated = true
		_play_land_sfx()
