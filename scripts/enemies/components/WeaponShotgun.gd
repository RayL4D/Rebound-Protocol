# =============================================================
# WeaponShotgun.gd — Arme à dispersion (éventail de balles)
# Rebound Protocol
# =============================================================
# Tire bullet_count balles simultanément en éventail centré sur
# la direction du joueur. Portée courte mais difficile d'éviter
# toutes les balles si le joueur est proche.
#
# Usage dans la sous-classe de l'ennemi :
#   @onready var weapon: WeaponShotgun = $WeaponMount/WeaponShotgun
#   func _on_ready(): weapon.activate(player)
# =============================================================
class_name WeaponShotgun
extends WeaponComponent

# --- Exports ----------------------------------------------------
@export var bullet_count:      int   = 4     # nombre de balles par tir
@export var spread_angle_deg:  float = 25.0  # angle total de l'éventail (degrés)
@export var bullet_speed:      float = 9.0
@export var bullet_scene: PackedScene = preload("res://scenes/enemies/bullet_enemy.tscn")

# --- Audio ------------------------------------------------------
const _SFX_SHOOT: AudioStream = preload("res://audio/sfx/enemies/shotgun_shoot.wav")
var _sfx_player: AudioStreamPlayer = null


func _ready() -> void:
	_sfx_player     = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)


# =============================================================
# TIR — éventail de balles centré sur la cible
# =============================================================

func _fire() -> void:
	if _target == null or bullet_scene == null:
		return

	var dir := _target.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()

	# Angle de départ et pas angulaire entre chaque balle
	var half_spread := deg_to_rad(spread_angle_deg * 0.5)
	var step        := deg_to_rad(spread_angle_deg) / float(bullet_count - 1) \
		if bullet_count > 1 else 0.0

	for i in bullet_count:
		var angle      := -half_spread + step * float(i)
		var shot_dir   := dir.rotated(Vector3.UP, angle)

		var bullet: Bullet = bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.speed  = bullet_speed
		bullet.damage = damage
		bullet.init(global_position, shot_dir)

	if _sfx_player and _SFX_SHOOT:
		_sfx_player.stream      = _SFX_SHOOT
		_sfx_player.volume_db   = -4.0 + randf_range(-1.0, 1.0)
		_sfx_player.pitch_scale = randf_range(0.93, 1.07)
		_sfx_player.play()
