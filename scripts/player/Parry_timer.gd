# =============================================================
# ParryTimer.gd — Fenêtre de timing de la parade
# =============================================================
class_name ParryTimer
extends Node

# --- Exports (tweakables sans recompiler) ------------------------
# Fenêtre critique : temps en secondes pour déclencher un CRITICAL
@export var perfect_window: float  = 0.15
# Durée maximale de validité d'un appui SPACE.
# Si la balle arrive après ce délai, le SPACE est ignoré → ABSORB.
@export var max_parry_window: float = 0.4
# Durée pendant laquelle SPACE est ignoré après une parade
@export var parry_cooldown: float  = 0.3

# --- Enum des états de parade -----------------------------------
enum ParryState {
	IDLE,
	ABSORB,    # Balle reçue sans appui SPACE
	STANDARD,  # SPACE pressé, hors fenêtre parfaite
	CRITICAL   # SPACE pressé dans la fenêtre parfaite
}

# --- Variables internes ------------------------------------------
var _state: ParryState        = ParryState.IDLE
var _bullet_incoming: bool    = false
var _impact_time: float       = 0.0  # Temps prévu d'impact (en secondes)
var _space_pressed: bool      = false
var _space_press_time: float  = 0.0
var _cooldown_timer: float    = 0.0

# --- Signaux -----------------------------------------------------
# Émis dès qu'une parade est résolue — Shield.gd écoute ce signal
signal parry_resolved(state: ParryState)


# =============================================================
# LIFECYCLE
# =============================================================

func _process(delta: float) -> void:
	# Décrémenter le cooldown
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		return

	# Détecter appui SPACE
	if Input.is_action_just_pressed("parry"):
		_space_pressed    = true
		_space_press_time = _get_time()

	# Expirer automatiquement le SPACE s'il est trop vieux —
	# sans ça, un appui bien avant l'impact compte quand même comme parade.
	if _space_pressed and (_get_time() - _space_press_time) > max_parry_window:
		_space_pressed = false


# =============================================================
# API PUBLIQUE — appelée par Bullet.gd
# =============================================================

# Appelé par la balle ennemie quand elle va toucher le bouclier
func on_bullet_impact() -> void:
	if _cooldown_timer > 0.0:
		return

	_impact_time = _get_time()

	if not _space_pressed:
		# Aucune action → absorption
		_resolve(ParryState.ABSORB)
		return

	# SPACE a été pressé — calculer l'écart avec l'impact
	var time_diff: float = abs(_impact_time - _space_press_time)

	if time_diff <= perfect_window:
		_resolve(ParryState.CRITICAL)
	else:
		_resolve(ParryState.STANDARD)


# =============================================================
# INTERNE
# =============================================================

func _resolve(state: ParryState) -> void:
	_state = state
	parry_resolved.emit(state)
	_reset()


func _reset() -> void:
	_bullet_incoming   = false
	_space_pressed     = false
	_space_press_time  = 0.0
	_cooldown_timer    = parry_cooldown
	_state             = ParryState.IDLE


func _get_time() -> float:
	return Time.get_ticks_msec() / 1000.0
