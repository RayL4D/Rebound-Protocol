# =============================================================
# AmbientManager — Autoload singleton
# Gère les sons d'ambiance de niveau en parallèle de la musique.
#
# UTILISATION :
#   AmbientManager.play("arena")   # démarre l'ambiance arène
#   AmbientManager.stop()          # fondu vers silence
#
# AJOUTER UNE AMBIANCE :
#   1. Mets ton fichier .ogg dans audio/ambiance/
#   2. Ajoute une entrée dans _TRACKS ci-dessous
#   3. Enregistre le nœud comme Autoload dans Project → Project Settings → Autoload
# =============================================================
extends Node

const FADE_IN_DURATION  := 3.0   # Fondu d'entrée lent pour ne pas surprendre
const FADE_OUT_DURATION := 2.0

const _TRACKS: Dictionary = {
	"arena": {
		"stream":    preload("res://audio/ambiance/arena_ambient.wav"),
		"volume_db": -4.0,   # Ambiance audible sous la musique
	},
}

var _player:         AudioStreamPlayer = null
var _current_track:  String            = ""
var _fade_tween:     Tween             = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()

	_player              = AudioStreamPlayer.new()
	_player.bus          = "Ambiance"
	_player.volume_db    = -80.0
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)


# =============================================================
# API PUBLIQUE
# =============================================================

func play(track_name: String) -> void:
	if track_name == _current_track:
		return

	var entry: Dictionary = _TRACKS.get(track_name, {})
	if entry.is_empty():
		push_warning("AmbientManager: piste inconnue '%s'." % track_name)
		return

	var stream: AudioStream = entry.get("stream", null)
	if stream == null:
		push_warning("AmbientManager: stream null pour '%s'." % track_name)
		return

	_current_track = track_name
	var target_db: float = entry.get("volume_db", -14.0)

	# Déconnecter le loop de l'ancienne piste
	if _player.finished.is_connected(_on_loop):
		_player.finished.disconnect(_on_loop)

	_player.stream    = stream
	_player.volume_db = -80.0
	_player.play()
	_player.finished.connect(_on_loop)

	_fade_to(target_db, FADE_IN_DURATION)


func stop() -> void:
	if _current_track.is_empty():
		return
	_current_track = ""
	if _player.finished.is_connected(_on_loop):
		_player.finished.disconnect(_on_loop)
	_fade_to(-80.0, FADE_OUT_DURATION, true)


# =============================================================
# INTERNE
# =============================================================

func _fade_to(target_db: float, duration: float, stop_after: bool = false) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", target_db, duration)
	if stop_after:
		_fade_tween.tween_callback(_player.stop)


func _on_loop() -> void:
	# Relance la piste en boucle dès qu'elle est terminée
	_player.play()


func _ensure_bus() -> void:
	if AudioServer.get_bus_index("Ambiance") != -1:
		return
	var idx := AudioServer.get_bus_count()
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Ambiance")
	AudioServer.set_bus_send(idx, "Master")
