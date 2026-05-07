# =============================================================
# WeaponTrap.gd — Arme qui pose des mines au sol
# Rebound Protocol
# =============================================================
# Pose une TrapMine à la position actuelle de l'ennemi toutes les
# (1 / fire_rate) secondes, dans la limite de max_mines simultanées.
#
# Différence avec WeaponBullet / WeaponMortar :
#   • Pas de vérification de portée — pose toujours une mine
#   • Gère un tableau de références pour ne pas dépasser max_mines
#
# Usage : attacher à un Node3D enfant du WeaponMount.
# =============================================================
class_name WeaponTrap
extends WeaponComponent

# --- Exports ----------------------------------------------------
@export var max_mines:    int   = 5     # max de mines actives en même temps
@export var mine_lifetime: float = 25.0 # durée de vie de chaque mine (secondes)

# --- État interne -----------------------------------------------
var _mines: Array = []  # Array[TrapMine] — nettoyé automatiquement

# --- Audio ------------------------------------------------------
const _SFX_DEPLOY: AudioStream = preload("res://audio/sfx/enemies/mine_deploy.wav")
var _sfx_player: AudioStreamPlayer = null


func _ready() -> void:
	_sfx_player     = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)


# =============================================================
# SURCHARGE DE _process — pas de vérification de portée
# =============================================================

func _process(delta: float) -> void:
	if not _active or _target == null:
		return

	# Nettoyer les références invalidées (mines détruites)
	_mines = _mines.filter(func(m): return is_instance_valid(m))

	if _cooldown > 0.0:
		_cooldown -= delta
		return

	# Ne pas poser de mine s'il y en a déjà trop
	if _mines.size() >= max_mines:
		return

	_fire()
	fired.emit()
	_cooldown = 1.0 / fire_rate


# =============================================================
# TIR — pose une mine à la position courante
# =============================================================

func _fire() -> void:
	var mine := TrapMine.new()
	get_tree().current_scene.add_child(mine)
	mine.init(global_position, damage, mine_lifetime)
	_mines.append(mine)

	if _sfx_player and _SFX_DEPLOY:
		_sfx_player.stream      = _SFX_DEPLOY
		_sfx_player.volume_db   = -14.0
		_sfx_player.pitch_scale = randf_range(0.97, 1.03)
		_sfx_player.play()
