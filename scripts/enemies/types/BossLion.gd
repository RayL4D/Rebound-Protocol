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
class_name BossLion
extends Enemy

# --- Signal émis à la mort (connecté par arena_base) ----------
signal boss_died
signal boss_hp_changed(current_hp: int, max_hp: int)

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
	# Mini-boss : immunisé au stomp du joueur
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
		_move_orbit(delta)
	else:
		_move_phase2(delta)


# Phase 1 : approche jusqu'à combat_distance, puis orbite
func _move_orbit(_delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	var dist      := to_player.length()

	if dist > combat_distance:
		var dir    := to_player.normalized()
		velocity.x  = dir.x * move_speed
		velocity.z  = dir.z * move_speed
	else:
		var lateral := to_player.normalized().rotated(Vector3.UP, PI * 0.5)
		velocity.x   = lateral.x * move_speed * 0.4
		velocity.z   = lateral.z * move_speed * 0.4


# Phase 2 : orbite + charge de taureau périodique
func _move_phase2(delta: float) -> void:
	match _charge_state:

		ChargeState.IDLE:
			_move_orbit(delta)
			_charge_cd -= delta
			if _charge_cd <= 0.0:
				_begin_windup()

		ChargeState.WINDUP:
			# S'arrête et vise le joueur — telegraphe la charge
			velocity.x = 0.0
			velocity.z = 0.0
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_begin_charge()

		ChargeState.CHARGING:
			velocity.x = _charge_dir.x * CHARGE_SPEED
			velocity.z = _charge_dir.z * CHARGE_SPEED
			_charge_timer -= delta

			# Contact mêlée ?
			var dist := (player.global_position - global_position)
			dist.y    = 0.0
			if dist.length() <= MELEE_RANGE:
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
				_charge_state = ChargeState.IDLE
				_charge_cd    = randf_range(CHARGE_CD_MIN, CHARGE_CD_MAX)
				_gesture_active = false


# --- Transitions d'état ----------------------------------------

func _begin_windup() -> void:
	_charge_state = ChargeState.WINDUP
	_charge_timer = WINDUP_DURATION
	# Verrouille la direction au moment du windup
	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	_charge_dir   = to_player.normalized()


func _begin_charge() -> void:
	_charge_state = ChargeState.CHARGING
	_charge_timer = CHARGE_DURATION


func _begin_attack() -> void:
	_charge_state   = ChargeState.ATTACKING
	_charge_timer   = ATTACK_DURATION
	_gesture_active = true
	if _anim_player:
		_anim_player.play("eat")
	# Dégâts au joueur si méthode disponible
	if player.has_method("take_damage"):
		player.take_damage(MELEE_DAMAGE)


func _begin_recover() -> void:
	_charge_state   = ChargeState.RECOVERING
	_charge_timer   = RECOVER_DURATION
	_gesture_active = false


# =============================================================
# SANTÉ — détection de la transition de phase
# =============================================================

func take_damage(amount: int) -> void:
	super.take_damage(amount)
	boss_hp_changed.emit(current_hp, max_hp)
	if current_hp > 0:
		_check_phase_transition()


func _check_phase_transition() -> void:
	if _phase2_triggered:
		return
	if float(current_hp) / float(max_hp) <= PHASE2_THRESHOLD:
		_enter_phase2()


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
		var shader := Shader.new()
		shader.code = BOSS_SHADER_CODE
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("albedo_tex", _enemy_texture)
		(node as MeshInstance3D).set_surface_override_material(0, mat)
		# Mettre à jour _orig_mats pour que _flash_hit restaure le shader
		# de phase 2 (et non le colormap d'origine enregistré au démarrage).
		_orig_mats[node] = mat
	for child in node.get_children():
		_apply_phase2_shader(child)


# =============================================================
# MORT
# =============================================================

func _die() -> void:
	if summon_timer:
		summon_timer.stop()
	boss_died.emit()
	queue_free()


# =============================================================
# INVOCATION DES CHIENS
# =============================================================

func _summon_dogs() -> void:
	if not is_inside_tree() or dog_scene == null:
		return

	for i in range(2):
		var dog: CharacterBody3D = dog_scene.instantiate()
		get_tree().current_scene.add_child(dog)

		# Placer les chiens de part et d'autre du boss
		var angle  := (PI * float(i)) + randf_range(-0.5, 0.5)
		var radius := randf_range(2.0, 4.0)
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		dog.global_position = global_position + offset
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          