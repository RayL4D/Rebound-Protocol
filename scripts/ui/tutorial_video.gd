# =============================================================
# tutorial_video.gd — Lecteur de vidéos tutoriel en séquence
# Rebound Protocol
# =============================================================
extends Control

# ── Liste de tes vidéos dans l'ordre ──────────────────────────
const VIDEOS: Array[String] = [
	"res://assets/videos/tutorial_01.ogv",
	"res://assets/videos/tutorial_02.ogv",
	"res://assets/videos/tutorial_03.ogv",
	"res://assets/videos/tutorial_04.ogv",
]

# La scène à charger une fois toutes les vidéos terminées
const NEXT_LEVEL := "res://scenes/levels/arena_base.tscn"

var _video_player: VideoStreamPlayer
var _skip_label: Label
var _current_index: int = 0

func _ready() -> void:
	MusicManager.stop()    # fondu vers silence en 1.5s (FADE_DURATION)
	AmbientManager.stop()  # fondu vers silence en 2.0s (FADE_OUT_DURATION)
	# Fond noir
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Lecteur vidéo centré, plein écran
	_video_player = VideoStreamPlayer.new()
	_video_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video_player.expand = true
	add_child(_video_player)

	# ── Bouton "Passer toutes les vidéos" — caché au départ ──
	var skip_all_btn := Button.new()
	skip_all_btn.name = "SkipBtn"
	skip_all_btn.text = tr("UI_TUTO_SKIP_ALL")
	skip_all_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	skip_all_btn.offset_left   = -200
	skip_all_btn.offset_top    = 18
	skip_all_btn.offset_right  = -18
	skip_all_btn.offset_bottom = 52
	skip_all_btn.pressed.connect(_finish_tutorial)
	skip_all_btn.modulate.a = 0.0  # invisible au départ
	skip_all_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE  # non cliquable au départ
	add_child(skip_all_btn)

	# ── Timer : affiche le bouton après 3 secondes ──
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(_show_skip_button)

	_play_video(_current_index)

func _show_skip_button() -> void:
	var btn := get_node_or_null("SkipBtn")
	if btn == null:
		return
	btn.mouse_filter = Control.MOUSE_FILTER_STOP  # redevient cliquable
	var tw := create_tween()
	tw.tween_property(btn, "modulate:a", 1.0, 0.5)  # fondu d'apparition en 0.5s
	
func _play_video(index: int) -> void:
	if index >= VIDEOS.size():
		_finish_tutorial()
		return

	var path := VIDEOS[index]
	if not ResourceLoader.exists(path):
		push_warning("Vidéo introuvable : " + path)
		_next_video()
		return

	var stream := load(path) as VideoStream
	if stream == null:
		push_warning("Impossible de charger la vidéo : " + path)
		_next_video()
		return

	_video_player.stream = stream
	_video_player.play()

	# Quand la vidéo se termine → vidéo suivante
	if not _video_player.finished.is_connected(_next_video):
		_video_player.finished.connect(_next_video)


func _next_video() -> void:
	_current_index += 1
	_play_video(_current_index)


func _finish_tutorial() -> void:
	_video_player.stop()
	# Pas besoin de remettre la musique ici :
	# arena_base.tscn appellera MusicManager.play("gameplay")
	# et AmbientManager.play("arena") dans son propre _ready()
	SceneManager.load_level(NEXT_LEVEL)	
