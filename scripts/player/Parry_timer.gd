# =============================================================
# ParryTimer.gd — Fenêtre de timing de la parade
# =============================================================
class_name ParryTimer
extends Node

# --- Exports (tweakables sans recompiler) ------------------------
# Fenêtre critique : temps en secondes pour déclencher un CRITICAL
@export var perfect_window: float  = 0.12  # était 0.15
# Durée maximale de validité d'un clic gauche.
# Si la balle arrive après ce délai, le clic est ignoré → ABSORB.
@export var max_parry_window: float = 0.25  # était 0.4
# Durée pendant laquelle le clic est ignoré après une parade
@export var parry_cooldown: float  = 0.15  # fenêtre pour attraper les balles d'une même volée

# --- Enum des états de parade -----------------------------------
enum ParryState {
	IDLE,
	ABSORB,    # Balle reçue sans clic gauche
	STANDARD,  # Clic gauche pressé, hors fenêtre parfaite
	CRITICAL   # Clic gauche pressé dans la fenêtre parfaite
}

# --- Variables internes ------------------------------------------
var _state: ParryState        = ParryState.IDLE
var _bullet_incoming: bool    = false
var _impact_time: float       = 0.0  # Temps prévu d'impact (en secondes)
var _parry_pressed: bool      = false
var _parry_press_time: float  = 0.0
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

	# Détecter clic gauche (action "parry")
	if Input.is_action_just_pressed("parry"):
		_parry_pressed    = true
		_parry_press_time = _get_time()

	# Expirer automatiquement le clic s'il est trop vieux —
	# sans ça, un clic bien avant l'impact compte quand même comme parade.
	if _parry_pressed and (_get_time() - _parry_press_time) > max_parry_window:
		_parry_pressed = false


# =============================================================
# API PUBLIQUE — appelée par Shield.gd
# =============================================================

# Appelé quand une balle touche le bouclier
func on_bullet_impact() -> void:
	if _cooldown_timer > 0.0:
		return

	_impact_time = _get_time()

	if not _parry_pressed:
		# Aucune action → absorption
		_resolve(ParryState.ABSORB)
		return

	# Clic gauche détecté — calculer l'écart avec l'impact
	var time_diff: float = abs(_impact_time - _parry_press_time)

	if time_diff <= perfect_window:
		_resolve(ParryState.CRITICAL)
	else:
		_resolve(ParryState.STANDARD)


# =============================================================
# INTERNE
# =============================================================

var _last_resolved: ParryState = ParryState.ABSORB  # dernier état résolu, conservé pour le cooldown

func _resolve(state: ParryState) -> void:
	_state         = state
	_last_resolved = state
	parry_resolved.emit(state)
	_reset()


func _reset() -> void:
	_bullet_incoming  = false
	_parry_pressed    = false
	_parry_press_time = 0.0
	_cooldown_timer   = parry_cooldown
	_state            = ParryState.IDLE


func _get_time() -> float:
	return Time.get_ticks_msec() / 1000.0


func is_on_cooldown() -> bool:
	return _cooldown_timer > 0.0


func get_last_resolved_state() -> ParryState:
	return _last_resolved


## Appelé par Player.request_parry() sur mobile — équivalent à
## is_action_just_pressed("parry") mais sans passer par l'Input singleton.
func notify_mobile_press() -> void:
	if _cooldown_timer > 0.0:
		return
	_parry_pressed    = true
	_parry_press_time = _get_time()
