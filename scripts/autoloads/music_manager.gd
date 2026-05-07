# =============================================================
# MusicManager — Autoload singleton
# Gère la musique de fond avec crossfade entre les pistes.
#
# UTILISATION :
#   MusicManager.play("menu")      # joue la piste "menu"
#   MusicManager.play("gameplay")  # crossfade vers "gameplay"
#   MusicManager.play("boss")      # crossfade vers "boss"
#   MusicManager.stop()            # fondu vers silence
#
# AJOUTER UNE PISTE :
#   1. Mets ton fichier .ogg dans audio/music/
#   2. Ajoute une entrée dans _TRACKS ci-dessous
#   3. "volume_db" permet d'équilibrer le volume entre pistes
#      (0.0 = neutre, +6.0 = deux fois plus fort, -6.0 = moitié)
# =============================================================
extends Node

const FADE_DURATION := 1.5

# --- Catalogue des pistes ---
# stream    : le fichier audio
# volume_db : offset en dB pour équilibrer les volumes entre pistes
const _TRACKS: Dictionary = {
	"menu": {
		"stream":      preload("res://audio/music/menu.ogg"),
		"volume_db":   0.0,
		"pitch_scale": 1.0,
	},
	"gameplay": {
		"stream":      preload("res://audio/music/gameplay.ogg"),
		"volume_db":   6.0,
		"pitch_scale": 1.0,
	},
	"boss": {
		"stream":      preload("res://audio/music/boss.ogg"),
		"volume_db":   6.0,
		"pitch_scale": 1.0,
	},
	"game_over": {
		"stream":      preload("res://audio/music/game_over.wav"),
		"volume_db":   0.0,
		"pitch_scale": 1.0,
		"loop":        true,
	},
}

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active:   AudioStreamPlayer

var _current_track:    String = ""
var _current_volume_db: float  = 0.0
var _fading:            bool   = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_ensure_buses()
	Settings.apply_saved_settings()

	_player_a = _make_player()
	_player_b = _make_player()
	_active   = _player_a


# =============================================================
# API PUBLIQUE
# =============================================================

func play(track_name: String) -> void:
	if track_name == _current_track:
		return

	var entry: Dictionary = _TRACKS.get(track_name, {})
	if entry.is_empty():
		push_warning("MusicManager: piste inconnue '%s'." % track_name)
		return

	var stream: AudioStream = entry.get("stream", null)
	if stream == null:
		push_warning("MusicManager: piste '%s' non chargée (null)." % track_name)
		return

	_current_track     = track_name
	_current_volume_db = entry.get("volume_db", 0.0)
	var pitch: float   = entry.get("pitch_scale", 1.0)
	var loop:  bool    = entry.get("loop", false)
	_crossfade_to(stream, _current_volume_db, pitch, loop)


func stop() -> void:
	_current_track = ""
	_fade_out(_active)


# =============================================================
# INTERNE
# =============================================================

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus          = "Music"
	p.volume_db    = -80.0
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


func _crossfade_to(stream: AudioStream, target_db: float, pitch: float = 1.0, loop: bool = false) -> void:
	var incoming: AudioStreamPlayer = _player_b if _active == _player_a else _player_a

	# Déconnecter l'ancien signal de loop s'il existe
	if incoming.finished.is_connected(_on_loop_finished.bind(incoming)):
		incoming.finished.disconnect(_on_loop_finished.bind(incoming))

	incoming.stream      = stream
	incoming.pitch_scale = pitch
	incoming.volume_db   = -80.0
	incoming.play()

	if loop:
		incoming.finished.connect(_on_loop_finished.bind(incoming))

	var tween := create_tween().set_parallel()
	tween.tween_property(_active,  "volume_db", -80.0,     FADE_DURATION)
	tween.tween_property(incoming, "volume_db", target_db, FADE_DURATION)

	var outgoing := _active
	_active = incoming
	_fading = true

	await tween.finished
	outgoing.stop()
	_fading = false


func _on_loop_finished(player: AudioStreamPlayer) -> void:
	if player == _active:
		player.play()


func _fade_out(player: AudioStreamPlayer) -> void:
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -80.0, FADE_DURATION)
	await tween.finished
	player.stop()


func _ensure_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		var idx := AudioServer.get_bus_count()
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")

	if AudioServer.get_bus_index("SFX") == -1:
		var idx := AudioServer.get_bus_count()
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")
