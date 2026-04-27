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

# --- Distance de combat (s'arrête et orbite) ------------------
@export var combat_distance: float = 7.0

# --- État interne ---------------------------------------------
var _phase: int = 1
var _phase2_triggered: bool = false

# --- Références armes -----------------------------------------
@onready var weapon_bullet:  WeaponBullet  = $WeaponMountRight/WeaponBullet
@onready var weapon_shotgun: WeaponShotgun = $WeaponMountLeft/WeaponShotgun
@onready var summon_timer:   Timer         = $SummonTimer

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
	if player == null:
		push_warning("BossLion : joueur introuvable.")
		return

	# Phase 1 active, phase 2 en veille
	if weapon_bullet:
		weapon_bullet.activate(player)
	if weapon_shotgun:
		weapon_shotgun.deactivate()

	# Timer d'invocation
	if summon_timer:
		summon_timer.wait_time = 20.0
		summon_timer.autostart = false
		summon_timer.one_shot  = false
		summon_timer.timeout.connect(_summon_dogs)
		summon_timer.start()


# =============================================================
# MOUVEMENT — approche jusqu'à combat_distance, puis orbite
# =============================================================

func _update_movement(_delta: float) -> void:
	if player == null:
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist > combat_distance:
		# Foncer vers le joueur
		var dir := to_player.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	else:
		# Déplacement orbital (strafe latéral)
		var lateral := to_player.normalized().rotated(Vector3.UP, PI * 0.5)
		velocity.x = lateral.x * move_speed * 0.4
		velocity.z = lateral.z * move_speed * 0.4


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
