# =============================================================
# BossLion.gd — Mini-boss niveau 1 : Lion Commandant
# Rebound Protocol
# =============================================================
# Deux phases de combat :
#   Phase 1 (100 % → 50 % HP) : blaster-h — tirs lourds uniques
#   Phase 2 (50 % →   0 % HP) : blaster-e — éventail de balles
#
# Invoque 2 PetDog toutes les 20 secondes.
# Taille : 1,5× le joueur (model_scale = 1.4)
#
# Hiérarchie de scène attendue :
#   BossLion (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [animal-lion.glb]
#   ├── WeaponMountRight (Node3D)  ← arme droite : blaster-h
#   │   └── WeaponBullet           ← phase 1
#   ├── WeaponMountLeft (Node3D)   ← arme gauche : blaster-e
#   │   └── WeaponShotgun          ← phase 2
#   └── SummonTimer (Timer)
# =============================================================
@tool
class_name BossLion
extends Enemy

# --- Signaux ----------------------------------------------------
signal boss_died
signal boss_hp_changed(current_hp: int, max_hp: int)
## Émis depuis _die() juste après avoir instancié la clé.
## Permet aux niveaux de connecter key.key_collected sans référence directe au boss.
signal key_spawned(key: Node3D)

# --- Seuil de transition de phase (50 % HP) -------------------
const PHASE2_THRESHOLD := 0.5

# --- Shader agressif activé à la phase 2 ----------------------
const BOSS_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform float darkness    : hint_range(0.0, 1.0) = 0.28;
uniform float tint_amount : hint_range(0.0, 1.0) = 0.50;
uniform vec3  tint_color                         = vec3(0.9, 0.15, 0.04);
uniform float rim_power   : hint_range(0.5, 8.0) = 2.5;
uniform float rim_amount  : hint_range(0.0, 2.0) = 0.8;
uniform vec3  rim_color                          = vec3(1.0, 0.08, 0.0);

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 col = tex.rgb * (1.0 - darkness);
	col = mix(col, col * tint_color, tint_amount);
	ALBEDO    = col;
	ROUGHNESS = 0.7;
	SPECULAR  = 0.25;
}

void light() {
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim   = pow(1.0 - ndotv, rim_power);
	DIFFUSE_LIGHT += rim_color * rim * rim_amount * ATTENUATION;
}
"""

# --- Distance de combat (s'arrête et orbite) ------------------
@export var combat_distance: float = 7.0

# --- Charge (phase 2 uniquement) ------------------------------
enum ChargeState { IDLE, WINDUP, CHARGING, ATTACKING, RECOVERING }

const CHARGE_SPEED     := 15.0   # vitesse de charge (px/s)
const WINDUP_DURATION  := 0.45   # pause avant de foncer (telegraphe)
const CHARGE_DURATION  := 0.80   # durée max de la charge
const MELEE_RANGE      := 1.8    # distance pour déclencher l'attaque
const MELEE_DAMAGE     := 18
const ATTACK_DURATION  := 0.85   # durée de l'animation "eat"
const RECOVER_DURATION := 0.70   # pause après la charge
const CHARGE_CD_MIN    := 3.5    # cooldown min entre deux charges
const CHARGE_CD_MAX    := 6.0    # cooldown max entre deux charges

var _charge_state: ChargeState = ChargeState.IDLE
var _charge_dir:   Vector3     = Vector3.ZERO
var _charge_timer: float       = 0.0
var _charge_cd:    float       = 3.0   # premier délai avant charge

# --- Double charge --------------------------------------------
const DOUBLE_CHARGE_CHANCE := 0.50   # 50 % de chance d'enchaîner
var _double_charge_pending: bool = false

# --- Dash d'esquive (phase 1) ---------------------------------
const DASH_SPEED      := 10.0
const DASH_DURATION   := 0.22
const DASH_CD_MIN     := 4.0
const DASH_CD_MAX     := 7.0
var _dash_cd:     float = 3.0
var _dash_timer:  float = 0.0
var _is_dashing:  bool  = false
var _dash_dir:    Vector3 = Vector3.ZERO

# --- Rugissement (phase 1) ------------------------------------
const ROAR_CD       := 18.0
const ROAR_DURATION :=  1.2
const ROAR_BUFF_DUR :=  5.0
var _roar_cd:     float = 10.0
var _roar_timer:  float = 0.0
var _is_roaring:  bool  = false

# --- Invocation d'urgence (25 % HP) ---------------------------
const PHASE3_THRESHOLD := 0.25
var _phase3_triggered: bool = false

# --- État interne ---------------------------------------------
var _phase: int = 1
var _phase2_triggered: bool = false

# --- Références armes -----------------------------------------
@onready var weapon_bullet:  WeaponBullet  = $WeaponMountRight/WeaponBullet
@onready var weapon_shotgun: WeaponShotgun = $WeaponMountLeft/WeaponShotgun
@onready var summon_timer:   Timer         = $SummonTimer
@onready var _health_bar:    BossHealthBar = $BossHealthBar

# --- Scène des chiens invoqués --------------------------------
var dog_scene: PackedScene = preload("res://scenes/enemies/pet_dog.tscn")


# --- Audio ----------------------------------------------------
const _SFX_BOSS_DIE:    AudioStream = preload("res://audio/sfx/enemies/boss_die.wav")
const _SFX_BOSS_SUMMON: AudioStream = preload("res://audio/sfx/enemies/boss_summon.wav")
const _SFX_BOSS_CHARGE: AudioStream = preload("res://audio/sfx/enemies/boss_charge.wav")
const _SFX_BOSS_MELEE:  AudioStream = preload("res://audio/sfx/enemies/boss_melee.wav")


# =============================================================
# SETUP MODÈLE — surcharge pour appliquer la texture sur les
# deux mounts (Enemy ne cherche que "WeaponMount" par défaut)
# =============================================================

func _setup_model() -> void:
	super._setup_model()
	var mount_right := get_node_or_null("WeaponMountRight")
	if mount_right:
		_apply_texture_recursive(mount_right, _weapon_texture)
	var mount_left := get_node_or_null("WeaponMountLeft")
	if mount_left:
		_apply_texture_recursive(mount_left, _weapon_texture)


# =============================================================
# HOOK D'INITIALISATION (appelé depuis Enemy._ready)
# =============================================================

func _on_ready() -> void:
	xp_reward    = 60   # Mini-boss — récompense généreuse
	stomp_immune = true

	if player == null:
		push_warning("BossLion : joueur introuvable.")
		return

	# Phase 1 active, phase 2 en veille
	if weapon_bullet:
		weapon_bullet.activate(player)
	if weapon_shotgun:
		weapon_shotgun.deactivate()

	# Barre de vie 3D au-dessus de la tête
	if _health_bar:
		boss_hp_changed.connect(_health_bar.update_hp)
		_health_bar.setup(tr("BOSS_LION_NAME"), max_hp)

	# Timer d'invocation
	if summon_timer:
		summon_timer.wait_time = 20.0
		summon_timer.autostart = false
		summon_timer.one_shot  = false
		summon_timer.timeout.connect(_summon_dogs)
		summon_timer.start()


# =============================================================
# MOUVEMENT
# =============================================================

func _update_movement(delta: float) -> void:
	if player == null:
		return
	if _phase == 1:
		_move_phase1(delta)
	else:
		_move_phase2(delta)


# =============================================================
# PHASE 1 : orbite + dash d'esquive + rugissement
# =============================================================

func _move_phase1(delta: float) -> void:
	# Rugissement
	_roar_cd -= delta
	if _roar_cd <= 0.0 and not _is_roaring:
		_begin_roar()

	if _is_roaring:
		_roar_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _roar_timer <= 0.0:
			_is_roaring = false
			_roar_cd    = ROAR_CD
		return

	# Dash d'esquive latéral
	_dash_cd -= delta
	if _is_dashing:
		_dash_timer -= delta
		velocity.x = _dash_dir.x * DASH_SPEED
		velocity.z = _dash_dir.z * DASH_SPEED
		if _dash_timer <= 0.0:
			_is_dashing = false
			_dash_cd    = randf_range(DASH_CD_MIN, DASH_CD_MAX)
		return

	if _dash_cd <= 0.0:
		_begin_dash()
		return

	_move_orbit()


# Approche via navmesh puis orbite latérale
func _move_orbit() -> void:
	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	var dist      := to_player.length()

	if dist > combat_distance:
		var nav_dir := _get_move_direction()
		if nav_dir == Vector3.ZERO:
			velocity.x = 0.0
			velocity.z = 0.0
			return
		velocity.x = nav_dir.x * move_speed
		velocity.z = nav_dir.z * move_speed
	else:
		var lateral := to_player.normalized().rotated(Vector3.UP, PI * 0.5)
		velocity.x   = lateral.x * move_speed * 0.4
		velocity.z   = lateral.z * move_speed * 0.4


func _begin_dash() -> void:
	_is_dashing  = true
	_dash_timer  = DASH_DURATION
	# Dash perpendiculaire au joueur — esquive sans s'éloigner
	var to_player := (player.global_position - global_position)
	to_player.y   = 0.0
	var perp      := to_player.normalized().rotated(Vector3.UP, PI * 0.5)
	_dash_dir      = perp if randf() > 0.5 else -perp


func _begin_roar() -> void:
	_is_roaring = true
	_roar_timer = ROAR_DURATION
	if _anim_player and _anim_player.has_animation("gesture-taunt"):
		_anim_player.play("gesture-taunt")
	# Accélérer tous les chiens présents dans la scène
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is not BossLion and node.has_method("_get_move_direction"):
			var enemy := node as Enemy
			# Buff temporaire : +50 % vitesse pendant ROAR_BUFF_DUR secondes
			var base_speed := enemy.move_speed
			enemy.move_speed *= 1.5
			get_tree().create_timer(ROAR_BUFF_DUR).timeout.connect(
				func(): if is_instance_valid(enemy): enemy.move_speed = base_speed
			)


# =============================================================
# PHASE 2 : orbite + charge de taureau + double charge
# =============================================================

func _move_phase2(delta: float) -> void:
	match _charge_state:

		ChargeState.IDLE:
			_move_orbit()
			_charge_cd -= delta
			if _charge_cd <= 0.0:
				_begin_windup()

		ChargeState.WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_begin_charge()

		ChargeState.CHARGING:
			# Légère correction de trajectoire vers le joueur (charge en arc)
			var to_player := player.global_position - global_position
			to_player.y   = 0.0
			_charge_dir = _charge_dir.lerp(to_player.normalized(), 0.04)
			velocity.x = _charge_dir.x * CHARGE_SPEED
			velocity.z = _charge_dir.z * CHARGE_SPEED
			_charge_timer -= delta

			var dist_to_player := to_player.length()
			if dist_to_player <= MELEE_RANGE:
				_begin_attack()
				return

			if _charge_timer <= 0.0:
				_begin_recover()

		ChargeState.ATTACKING:
			velocity.x = 0.0
			velocity.z = 0.0
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_begin_recover()

		ChargeState.RECOVERING:
			velocity.x = 0.0
			velocity.z = 0.0
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				# Double charge : enchaîne une 2e charge immédiatement
				if _double_charge_pending:
					_double_charge_pending = false
					_begin_windup()
				else:
					_charge_state   = ChargeState.IDLE
					_charge_cd      = randf_range(CHARGE_CD_MIN, CHARGE_CD_MAX)
					_gesture_active = false


# --- Transitions d'état ----------------------------------------

func _begin_windup() -> void:
	_charge_state = ChargeState.WINDUP
	_charge_timer = WINDUP_DURATION
	# Verrouille la direction au moment du windup
	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	_charge_dir   = to_player.normalized()

	if _sfx_player and _SFX_BOSS_CHARGE:
		_sfx_player.stream      = _SFX_BOSS_CHARGE
		_sfx_player.volume_db   = -4.0
		_sfx_player.pitch_scale = 1.0
		_sfx_player.play()


func _begin_charge() -> void:
	_charge_state = ChargeState.CHARGING
	_charge_timer = CHARGE_DURATION
	# Décide maintenant si une double charge suivra
	_double_charge_pending = randf() < DOUBLE_CHARGE_CHANCE


func _begin_attack() -> void:
	_charge_state   = ChargeState.ATTACKING
	_charge_timer   = ATTACK_DURATION
	_gesture_active = true
	if _anim_player:
		_anim_player.play("eat")
	# Dégâts au joueur si méthode disponible
	if player.has_method("take_damage"):
		player.take_damage(MELEE_DAMAGE)

	if _sfx_player and _SFX_BOSS_MELEE:
		_sfx_player.stream      = _SFX_BOSS_MELEE
		_sfx_player.volume_db   = -4.0
		_sfx_player.pitch_scale = randf_range(0.95, 1.05)
		_sfx_player.play()


func _begin_recover() -> void:
	_charge_state   = ChargeState.RECOVERING
	_charge_timer   = RECOVER_DURATION
	_gesture_active = false


# =============================================================
# SANTÉ — détection de la transition de phase
# =============================================================

func take_damage(amount: int, silent_hurt: bool = false) -> void:
	super.take_damage(amount, silent_hurt)
	boss_hp_changed.emit(current_hp, max_hp)
	if current_hp > 0:
		_check_phase_transition()
		_check_phase3()


func _check_phase_transition() -> void:
	if _phase2_triggered:
		return
	if float(current_hp) / float(max_hp) <= PHASE2_THRESHOLD:
		_enter_phase2()


func _check_phase3() -> void:
	if _phase3_triggered:
		return
	if float(current_hp) / float(max_hp) <= PHASE3_THRESHOLD:
		_phase3_triggered = true
		_summon_dogs_emergency()


func _enter_phase2() -> void:
	_phase2_triggered = true
	_phase = 2

	if weapon_bullet:
		weapon_bullet.deactivate()
	if weapon_shotgun:
		weapon_shotgun.activate(player)

	# Attendre la fin du flash de dégâts (0.12 s) avant d'appliquer le shader —
	# sinon le tween du flash restaure l'ancien matériau et écrase le shader phase 2.
	await get_tree().create_timer(0.15).timeout

	if not is_inside_tree():
		return
	if _model != null:
		_apply_phase2_shader(_model)


func _apply_phase2_shader(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var shader := Shader.new()
		shader.code = BOSS_SHADER_CODE
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("albedo_tex", _enemy_texture)
		var count := mi.mesh.get_surface_count() if mi.mesh else 1
		for i in count:
			mi.set_surface_override_material(i, mat)
		# Mettre à jour _orig_mats (Array) pour que _flash_hit restaure le shader
		# de phase 2 (et non le colormap d'origine enregistré au démarrage).
		var mats: Array = []
		for i in count:
			mats.append(mat)
		_orig_mats[node] = mats
	for child in node.get_children():
		_apply_phase2_shader(child)


# =============================================================
# MORT
# =============================================================

func _die() -> void:
	if summon_timer:
		summon_timer.stop()
	boss_died.emit()

	# ── Drop de la clé de boss ────────────────────────────────
	# IMPORTANT : positionner la clé AVANT add_child.
	# _ready() de boss_key.gd calcule _base_y depuis global_position.
	# Si on fait add_child() en premier, global_position vaut (0,0,0)
	# et la clé finit spawner à l'origine de la scène au lieu d'ici.
	var key_script: GDScript = load("res://scripts/pickups/boss_key.gd")
	var key: Node3D = key_script.new()
	key.position = global_position        # ← positionner AVANT add_child
	get_tree().current_scene.add_child(key)
	key_spawned.emit(key)                 # ← signal pour que le niveau ouvre le portail

	# Player flottant — survit au queue_free du boss
	if _SFX_BOSS_DIE != null:
		var p := AudioStreamPlayer.new()
		p.stream    = _SFX_BOSS_DIE
		p.bus       = "SFX"
		p.volume_db = -4.0
		get_tree().root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)

	super()


# =============================================================
# INVOCATION DES CHIENS
# =============================================================

func _summon_dogs_emergency() -> void:
	if not is_inside_tree() or dog_scene == null:
		return
	if _sfx_player and _SFX_BOSS_SUMMON:
		_sfx_player.stream      = _SFX_BOSS_SUMMON
		_sfx_player.volume_db   = -2.0   # plus fort — signal de danger
		_sfx_player.pitch_scale = 0.85   # plus grave — rugissement d'urgence
		_sfx_player.play()
	for i in range(3):   # 3 chiens au lieu de 2
		var dog: CharacterBody3D = dog_scene.instantiate()
		get_tree().current_scene.add_child(dog)
		dog.coin_drop_min = 1
		dog.coin_drop_max = 2
		dog.xp_reward     = 5
		var angle  := (TAU / 3.0) * float(i) + randf_range(-0.3, 0.3)
		var radius := randf_range(2.0, 3.5)
		dog.global_position = global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _summon_dogs() -> void:
	if not is_inside_tree() or dog_scene == null:
		return

	if _sfx_player and _SFX_BOSS_SUMMON:
		_sfx_player.stream      = _SFX_BOSS_SUMMON
		_sfx_player.volume_db   = -5.0
		_sfx_player.pitch_scale = 1.0
		_sfx_player.play()

	for i in range(2):
		var dog: CharacterBody3D = dog_scene.instantiate()
		get_tree().current_scene.add_child(dog)

		# Drop limité pour les chiens du boss (anti-farm)
		dog.coin_drop_min = 1
		dog.coin_drop_max = 2
		dog.xp_reward     = 5   # XP réduit — anti-farm de level-ups

		# Placer les chiens de part et d'autre du boss
		var angle  := (PI * float(i)) + randf_range(-0.5, 0.5)
		var radius := randf_range(2.0, 4.0)
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		dog.global_position = global_position + offset
