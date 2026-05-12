# =============================================================
# Shield.gd — Rotation du bouclier + logique de parade + visuel
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
# Le visuel (MeshInstance3D + ShaderMaterial) est configuré dans
# l'éditeur sur le nœud enfant "ShieldMesh". Le script récupère
# le matériau au démarrage pour gérer les flashes de parade.
# =============================================================
class_name Shield
extends Node3D

# --- Exports -----------------------------------------------------
@export var orbit_radius: float = 0.8

# --- Références nœuds --------------------------------------------
@onready var parry_timer:    ParryTimer      = $ParryTimer
@onready var hit_area:       Area3D          = $HitArea
@onready var _mesh_instance: MeshInstance3D  = $ShieldMesh

# --- Scène de la balle renvoyée ----------------------------------
var _bullet_reflected_scene: PackedScene = preload("res://scenes/enemies/bullet_reflected.tscn")

# --- Sons bouclier -----------------------------------------------
const _SFX_BLOCK:   AudioStream = preload("res://audio/sfx/shield/block.wav")   # Balle bloquée
const _SFX_REFLECT: AudioStream = preload("res://audio/sfx/shield/reflect.wav") # Balle renvoyée
var _sfx_shield: AudioStreamPlayer = null

# Combo : chaque balle successive dans la fenêtre fait monter le pitch
const _COMBO_WINDOW:    float = 0.55   # secondes avant reset du combo
const _COMBO_MAX:       int   = 6      # pitch plafonné à ce nombre de hits
var _block_combo:       int   = 0
var _block_combo_timer: float = 0.0
var _reflect_combo:     int   = 0
var _reflect_combo_timer: float = 0.0

# --- Variables d'état --------------------------------------------
var player: CharacterBody3D
var camera: Camera3D
var _shield_direction: Vector3 = Vector3.FORWARD
var _pending_bullet: Bullet = null

# Valeurs de base avant upgrades (pour recalcul idempotent)
var _base_orbit_radius:      float   = 0.0
var _base_mesh_scale:        Vector3 = Vector3.ONE
var _base_parry_window:      float   = 0.0
var _base_max_parry_window:  float   = 0.0

# --- Matériau (lu depuis ShieldMesh dans l'éditeur) --------------
var _shield_mat: ShaderMaterial
var _base_color: Color


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	player = get_parent()
	camera = get_viewport().get_camera_3d()

	# Player polyphonique pour les sons bouclier (block + reflect)
	_sfx_shield = AudioStreamPlayer.new()
	_sfx_shield.bus = "SFX"
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 4
	_sfx_shield.stream = poly
	add_child(_sfx_shield)
	_sfx_shield.play()

	hit_area.area_entered.connect(_on_bullet_entered)
	parry_timer.parry_resolved.connect(_on_parry_resolved)

	# Chercher le ShaderMaterial : d'abord en Material Override, sinon en surface 0
	_shield_mat = _mesh_instance.material_override as ShaderMaterial
	if _shield_mat == null:
		_shield_mat = _mesh_instance.get_surface_override_material(0) as ShaderMaterial
	if _shield_mat == null:
		push_error("Shield: aucun ShaderMaterial trouvé sur ShieldMesh — vérifie l'éditeur.")
		return

	# Lire la couleur de base depuis le matériau (définie dans l'inspector)
	_base_color = _shield_mat.get_shader_parameter("shield_color")

	# ── Stocker les valeurs de base AVANT d'appliquer les upgrades ──
	_base_orbit_radius     = orbit_radius
	_base_mesh_scale       = _mesh_instance.scale
	_base_parry_window     = parry_timer.perfect_window
	_base_max_parry_window = parry_timer.max_parry_window
	_apply_save_upgrades()


func _apply_save_upgrades() -> void:
	if SaveData.active_slot < 0:
		return

	# Taille du bouclier : +8 % de rayon par palier — toujours depuis la base
	var size_mult := 1.0 + SaveData.get_upgrade_value("shield_size")
	orbit_radius         = _base_orbit_radius * size_mult
	_mesh_instance.scale = _base_mesh_scale   * size_mult

	# Durée parade active : +10 % de max_parry_window par palier
	var dur_mult := 1.0 + SaveData.get_upgrade_value("shield_duration")
	parry_timer.max_parry_window = _base_max_parry_window * dur_mult

	# Fenêtre critique : +1 frame (1/60 s) par palier
	var extra_frames := SaveData.get_upgrade_value("parry_window")
	parry_timer.perfect_window = _base_parry_window + extra_frames / 60.0


## Rappelée depuis Player.refresh_upgrades() après un achat en boutique.
func refresh_upgrades() -> void:
	_apply_save_upgrades()   # Idempotent grâce aux valeurs de base


func _process(delta: float) -> void:
	_orbit_toward_mouse()
	# Décrémenter les timers de combo — reset quand la fenêtre expire
	if _block_combo_timer > 0.0:
		_block_combo_timer -= delta
		if _block_combo_timer <= 0.0:
			_block_combo = 0
	if _reflect_combo_timer > 0.0:
		_reflect_combo_timer -= delta
		if _reflect_combo_timer <= 0.0:
			_reflect_combo = 0


# =============================================================
# ROTATION ORBITALE
# =============================================================

func _orbit_toward_mouse() -> void:
	if camera == null:
		return

	var dir := Vector3.ZERO

	# --- Joystick mobile prioritaire ---
	var p := player as Player
	if p != null and p._joystick_aim_dir.length_squared() > 0.04:
		var cb        := camera.global_transform.basis
		var cam_right := Vector3(cb.x.x, 0.0, cb.x.z).normalized()
		var cam_fwd   := -Vector3(cb.z.x, 0.0, cb.z.z).normalized()
		dir = cam_right * p._joystick_aim_dir.x - cam_fwd * p._joystick_aim_dir.y
		dir.y = 0.0
	else:
		# --- Souris (desktop) ---
		var mouse_pos := get_viewport().get_mouse_position()
		var ray_orig  := camera.project_ray_origin(mouse_pos)
		var ray_dir   := camera.project_ray_normal(mouse_pos)
		var plane_y   := player.global_position.y

		if abs(ray_dir.y) > 0.001:
			var t := (plane_y - ray_orig.y) / ray_dir.y
			if t > 0.0:
				var world_pos := ray_orig + ray_dir * t
				dir = (world_pos - player.global_position)
				dir.y = 0.0

		# Souris vers le ciel (t ≤ 0) → projection horizontale du rayon
		if dir.length() < 0.01:
			dir = Vector3(ray_dir.x, 0.0, ray_dir.z)

	if dir.length() < 0.01:
		return

	dir               = dir.normalized()
	_shield_direction  = dir
	global_position    = player.global_position + dir * orbit_radius
	global_position.y  = player.global_position.y
	global_rotation.y  = atan2(dir.x, dir.z)


# =============================================================
# DÉTECTION BALLE
# =============================================================

func _on_bullet_entered(area: Area3D) -> void:
	if not area is Bullet:
		return
	# Si le cooldown est actif (parade vient de se résoudre), absorber
	# la balle directement — sans ça elle passe à travers car on_bullet_impact()
	# ignore les appels pendant le cooldown.
	if parry_timer.is_on_cooldown():
		# Appliquer le même état que la parade précédente (lu directement depuis le timer)
		match parry_timer.get_last_resolved_state():
			ParryTimer.ParryState.STANDARD:
				_spawn_reflected_bullet(10, false)
				_flash_shield(Color(1.0, 1.0, 1.0, 1.0), 0.2)
				_play_reflect_sfx()
			ParryTimer.ParryState.CRITICAL:
				_spawn_reflected_bullet(25, true)
				_flash_shield(Color(1.0, 0.75, 0.0, 1.0), 0.3)
				_play_reflect_sfx()
			_:
				_flash_shield(Color(0.5, 0.6, 0.8, 0.6), 0.15)
				_play_block_sfx()
		area.queue_free()
		return
	_pending_bullet = area
	parry_timer.on_bullet_impact()


# =============================================================
# RÉSOLUTION DE LA PARADE
# =============================================================

func _on_parry_resolved(state: ParryTimer.ParryState) -> void:
	if _pending_bullet == null:
		return

	match state:
		ParryTimer.ParryState.ABSORB:
			_pending_bullet.queue_free()
			_flash_shield(Color(0.5, 0.6, 0.8, 0.6), 0.25)
			_play_block_sfx()

		ParryTimer.ParryState.STANDARD:
			_spawn_reflected_bullet(10, false)
			_pending_bullet.queue_free()
			_flash_shield(Color(1.0, 1.0, 1.0, 1.0), 0.3)
			_play_reflect_sfx()

		ParryTimer.ParryState.CRITICAL:
			_spawn_reflected_bullet(25, true)
			_pending_bullet.queue_free()
			_flash_shield(Color(1.0, 0.75, 0.0, 1.0), 0.45)
			# Critique : pitch plus bas et volume max pour marquer l'impact
			_reflect_combo        = min(_reflect_combo + 1, _COMBO_MAX)
			_reflect_combo_timer  = _COMBO_WINDOW
			_play_shield_sfx(_SFX_REFLECT, 0.0, randf_range(0.88, 0.94))

	_pending_bullet = null


# =============================================================
# FLASH DE PARADE
# =============================================================

func _flash_shield(flash_color: Color, duration: float) -> void:
	if _shield_mat == null:
		return

	_shield_mat.set_shader_parameter("shield_color", flash_color)
	_shield_mat.set_shader_parameter("intensity",    2.5)

	var tween := create_tween().set_parallel(true)
	tween.tween_method(
		func(c: Color): _shield_mat.set_shader_parameter("shield_color", c),
		flash_color, _base_color, duration
	)
	tween.tween_method(
		func(v: float): _shield_mat.set_shader_parameter("intensity", v),
		2.5, 1.5, duration
	)


# =============================================================
# RENVOI DE BALLE
# =============================================================

func _spawn_reflected_bullet(bullet_damage: int, is_critical: bool = false) -> void:
	# Dégâts de renvoi : +10 % par palier "parry_damage"
	var dmg_mult  := 1.0 + (SaveData.get_upgrade_value("parry_damage") if SaveData.active_slot >= 0 else 0.0)
	var final_dmg := int(round(float(bullet_damage) * dmg_mult))

	var bullet: BulletReflected = _bullet_reflected_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.init(global_position, _shield_direction, final_dmg, is_critical)


# =============================================================
# SON DE BLOCK
# =============================================================

func _play_shield_sfx(stream: AudioStream, vol_db: float, pitch: float) -> void:
	if stream == null or _sfx_shield == null:
		return
	var pb := _sfx_shield.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if pb:
		pb.play_stream(stream, 0.0, vol_db, pitch)


## Son de block : pitch monte légèrement à chaque balle successive dans la fenêtre combo.
func _play_block_sfx() -> void:
	_block_combo        = min(_block_combo + 1, _COMBO_MAX)
	_block_combo_timer  = _COMBO_WINDOW
	# Pitch : +0.04 par hit (1.0 → 1.24 max), variation aléatoire réduite
	var pitch: float = 0.95 + (_block_combo - 1) * 0.04 + randf_range(-0.02, 0.02)
	# Volume : légèrement plus présent au fil du combo
	var vol: float   = -9.0 + (_block_combo - 1) * 0.8
	_play_shield_sfx(_SFX_BLOCK, vol, pitch)


## Son de reflect : pitch monte plus franchement — chaîne de renvois très satisfaisante.
func _play_reflect_sfx() -> void:
	_reflect_combo        = min(_reflect_combo + 1, _COMBO_MAX)
	_reflect_combo_timer  = _COMBO_WINDOW
	# Pitch : +0.06 par hit (1.0 → 1.30 max)
	var pitch: float = 1.0 + (_reflect_combo - 1) * 0.06 + randf_range(-0.02, 0.02)
	# Volume : monte avec le combo pour souligner la chaîne
	var vol: float   = -5.0 + (_reflect_combo - 1) * 1.0
	_play_shield_sfx(_SFX_REFLECT, vol, pitch)
