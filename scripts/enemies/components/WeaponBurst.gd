# =============================================================
# WeaponBurst.gd — Arme à tir en rafale
# Rebound Protocol
# =============================================================
# Tire burst_count balles en succession rapide (burst_interval),
# puis recharge pendant burst_cooldown avant le prochain burst.
# Hérite de WeaponComponent.
#
# Paramètres typiques pour le Chat :
#   burst_count    = 3
#   burst_interval = 0.12   (temps entre chaque balle du burst)
#   burst_cooldown = 2.2    (pause de recharge après le burst)
# =============================================================
class_name WeaponBurst
extends WeaponComponent

# --- Exports propres à ce type ----------------------------------
@export var burst_count:    int   = 3
@export var burst_interval: float = 0.12  # secondes entre chaque balle
@export var burst_cooldown: float = 2.2   # pause après un burst complet
@export var bullet_speed:   float = 12.0
@export var bullet_scene:   PackedScene = preload("res://scenes/enemies/bullet_enemy.tscn")

# --- État interne du burst --------------------------------------
var _in_burst:    bool  = false
var _shots_fired: int   = 0
var _burst_timer: float = 0.0

# --- Audio ------------------------------------------------------
const _SFX_SHOOT: AudioStream = preload("res://audio/sfx/enemies/bullet_shoot.wav")
var _sfx_player: AudioStreamPlayer = null


func _ready() -> void:
	_sfx_player     = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)


# =============================================================
# SURCHARGE COMPLÈTE de _process (logique burst spécifique)
# =============================================================

func _process(delta: float) -> void:
	if not _active or _target == null:
		return

	# --- Phase intra-burst : attendre avant la prochaine balle ---
	if _in_burst:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fire()
			fired.emit()
			_shots_fired += 1

			if _shots_fired >= burst_count:
				# Burst terminé → recharge
				_in_burst    = false
				_shots_fired = 0
				_cooldown    = burst_cooldown
			else:
				# Prochaine balle du burst
				_burst_timer = burst_interval
		return

	# --- Phase de recharge : décrémenter le cooldown --------------
	if _cooldown > 0.0:
		_cooldown -= delta
		return

	# --- Prêt à tirer : vérifier la portée ----------------------
	if global_position.distance_to(_target.global_position) > shoot_range:
		return

	# Premier tir du burst — immédiat
	_fire()
	fired.emit()
	_shots_fired = 1

	if burst_count <= 1:
		# Burst d'une seule balle → recharge directe
		_cooldown    = burst_cooldown
		_shots_fired = 0
	else:
		_in_burst    = true
		_burst_timer = burst_interval


# =============================================================
# TIR — instancie une balle standard
# =============================================================

func _fire() -> void:
	if _target == null or bullet_scene == null:
		return

	var bullet: Bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)

	bullet.speed  = bullet_speed
	bullet.damage = damage

	var dir := _target.global_position - global_position
	dir.y = 0.0

	bullet.init(global_position, dir)

	if _sfx_player and _SFX_SHOOT:
		_sfx_player.stream      = _SFX_SHOOT
		_sfx_player.volume_db   = -8.0 + randf_range(-1.0, 1.0)
		_sfx_player.pitch_scale = randf_range(0.95, 1.05)
		_sfx_player.play()
