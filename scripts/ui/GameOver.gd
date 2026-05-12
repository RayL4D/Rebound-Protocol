# =============================================================
# GameOver.gd — Écran de fin de partie
# =============================================================
# Séquence de mort :
#   1. Flash blanc (impact)
#   2. Désaturation progressive de l'écran (style GTA)
#   3. Panneau Game Over avec effet glitch
# =============================================================
extends CanvasLayer

const COLOR_CYAN  := Color(0.0,  0.85, 1.0)
const COLOR_RED   := Color(1.0,  0.15, 0.15)
const COLOR_GOLD  := Color(1.0,  0.82, 0.0)
const COLOR_DARK  := Color(0.02, 0.04, 0.08, 0.96)
const CORNER_LEN  := 12.0
const CORNER_THK  := 2.0

# Shader de désaturation — appliqué sur un ColorRect plein écran
const DESAT_SHADER := """
shader_type canvas_item;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float darken     : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4  screen = texture(SCREEN_TEXTURE, SCREEN_UV);
	float gray   = dot(screen.rgb, vec3(0.299, 0.587, 0.114));
	vec3  result = mix(screen.rgb, vec3(gray), desaturate);
	result      *= 1.0 - darken * 0.55;
	COLOR        = vec4(result, 1.0);
}
"""

var _desat_rect:    ColorRect       # Plein écran — désaturation shader
var _desat_mat:     ShaderMaterial
var _flash_rect:    ColorRect       # Flash blanc à l'impact
var _overlay:       ColorRect       # Fond sombre derrière le panneau
var _panel:         Control
var _title:         Label
var _subtitle:      Label
var _btn_retry:     Button
var _btn_quit:      Button

var _glitch_timer:  float  = 0.0
var _is_glitching:  bool   = false
var _accent_color:  Color  = COLOR_RED
var _panel_visible: bool   = false

# --- Audio ------------------------------------------------------
const _SFX_HOVER:  AudioStream = preload("res://audio/sfx/ui/btn_hover.wav")
const _SFX_CLICK:  AudioStream = preload("res://audio/sfx/ui/btn_click.wav")
var _sfx_player: AudioStreamPlayer = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sfx_player              = AudioStreamPlayer.new()
	_sfx_player.bus          = "SFX"
	_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx_player)
	_build_ui()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		player.player_died.connect(show_game_over)


func _process(delta: float) -> void:
	if not _panel_visible:
		return
	_glitch_timer -= delta
	if _glitch_timer <= 0.0:
		_is_glitching  = !_is_glitching
		_glitch_timer   = 0.07 if _is_glitching else randf_range(1.2, 3.0)
	if _is_glitching:
		_title.position.x = randf_range(-4.0, 4.0)
		_title.add_theme_color_override("font_color",
			_accent_color.lerp(Color.WHITE, randf_range(0.0, 0.5)))
	else:
		_title.position.x = 0.0
		_title.add_theme_color_override("font_color", _accent_color)


# =============================================================
# API PUBLIQUE
# =============================================================

func show_game_over() -> void:
	_accent_color   = COLOR_RED
	_title.text     = tr("UI_GAME_OVER")
	_subtitle.text  = tr("UI_SYS_NEUTRALIZED")
	_btn_retry.text = tr("UI_RETRY")
	AmbientManager.stop()
	_play_death_sequence()


func show_victory() -> void:
	_accent_color   = COLOR_GOLD
	_title.text     = tr("UI_VICTORY")
	_subtitle.text  = tr("UI_THREAT_CLEARED")
	_btn_retry.text = tr("UI_PLAY_AGAIN")
	_play_death_sequence()


# =============================================================
# SÉQUENCE DE MORT
# =============================================================

func _play_death_sequence() -> void:
	# 1. Flash blanc immédiat
	var flash_tween := create_tween()
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.85)
	flash_tween.tween_property(_flash_rect, "color", Color(1.0, 1.0, 1.0, 0.0), 0.4)

	# 2. Désaturation progressive sur 2 secondes
	var desat_tween := create_tween().set_parallel(true)
	desat_tween.tween_method(
		func(v: float): _desat_mat.set_shader_parameter("desaturate", v),
		0.0, 1.0, 2.0
	)
	desat_tween.tween_method(
		func(v: float): _desat_mat.set_shader_parameter("darken", v),
		0.0, 0.4, 2.0
	)

	# 3. Attendre la fin de l'animation de mort (~2 s) avant le panneau
	await get_tree().create_timer(2.0).timeout

	# 4. Afficher le panneau + musique game over + pauser
	_panel.visible   = true
	_panel_visible   = true
	_animate_panel_in()
	MusicManager.play("game_over")
	get_tree().paused = true


# =============================================================
# BUILD UI
# =============================================================

func _build_ui() -> void:
	# Shader de désaturation plein écran
	var shader      := Shader.new()
	shader.code      = DESAT_SHADER
	_desat_mat       = ShaderMaterial.new()
	_desat_mat.shader = shader
	_desat_rect      = ColorRect.new()
	_desat_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_desat_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desat_rect.material     = _desat_mat
	add_child(_desat_rect)

	# Flash blanc
	_flash_rect      = ColorRect.new()
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	# Overlay sombre derrière le panneau
	# MOUSE_FILTER_IGNORE : ne doit pas bloquer les clics sur les boutons du panneau
	_overlay              = ColorRect.new()
	_overlay.color        = Color(0.0, 0.0, 0.0, 0.65)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible      = false
	add_child(_overlay)

	# Panneau central
	# PROCESS_MODE_WHEN_PAUSED : doit répondre aux inputs même pendant la pause
	_panel                = Control.new()
	_panel.size           = Vector2(380.0, 260.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position      -= _panel.size * 0.5
	_panel.process_mode   = Node.PROCESS_MODE_WHEN_PAUSED
	_panel.visible        = false
	add_child(_panel)

	var bg := ColorRect.new()
	bg.color = COLOR_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)

	# Scan lines
	_add_scan_lines(_panel)

	# Séparateurs
	for y in [75.0, 148.0]:
		var sep       := ColorRect.new()
		sep.color      = Color(COLOR_CYAN, 0.25)
		sep.size       = Vector2(380.0, 1.0)
		sep.position   = Vector2(0.0, y)
		_panel.add_child(sep)

	# Coins décoratifs
	for r in _make_corners(Vector2.ZERO, _panel.size, COLOR_CYAN):
		_panel.add_child(r)

	# Titre
	_title = Label.new()
	_title.size     = Vector2(380.0, 75.0)
	_title.position = Vector2(0.0, 0.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 42)
	_title.add_theme_color_override("font_color", COLOR_RED)
	_title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_title.add_theme_constant_override("outline_size", 3)
	_panel.add_child(_title)

	# Sous-titre
	_subtitle = Label.new()
	_subtitle.size     = Vector2(380.0, 30.0)
	_subtitle.position = Vector2(0.0, 88.0)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 11)
	_subtitle.add_theme_color_override("font_color", Color(0.45, 0.75, 0.85, 0.9))
	_panel.add_child(_subtitle)

	# Watermark
	var tip := Label.new()
	tip.text     = "REBOUND PROTOCOL"
	tip.size     = Vector2(380.0, 20.0)
	tip.position = Vector2(0.0, 122.0)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 8)
	tip.add_theme_color_override("font_color", Color(0.3, 0.5, 0.6, 0.5))
	_panel.add_child(tip)

	# Boutons
	_btn_retry = _make_button(tr("UI_RETRY"), Vector2(90.0, 163.0), Vector2(200.0, 38.0), true)
	_btn_retry.pressed.connect(_on_retry)
	_btn_retry.process_mode = Node.PROCESS_MODE_ALWAYS   # fonctionne paused ou non
	_panel.add_child(_btn_retry)

	_btn_quit = _make_button(tr("UI_QUIT"), Vector2(90.0, 210.0), Vector2(200.0, 30.0), false)
	_btn_quit.pressed.connect(_on_quit)
	_btn_quit.process_mode = Node.PROCESS_MODE_ALWAYS    # fonctionne paused ou non
	_panel.add_child(_btn_quit)


func _add_scan_lines(parent: Control) -> void:
	var lines := Control.new()
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lines)
	for i in range(0, 260, 4):
		var line          := ColorRect.new()
		line.color         = Color(0.0, 0.0, 0.0, 0.12)
		line.position      = Vector2(0.0, float(i))
		line.size          = Vector2(380.0, 1.0)
		line.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		lines.add_child(line)


func _make_corners(origin: Vector2, size: Vector2, color: Color) -> Array:
	var result := []
	for p in [
		[origin,                                                       Vector2(CORNER_LEN, CORNER_THK)],
		[origin,                                                       Vector2(CORNER_THK, CORNER_LEN)],
		[origin + Vector2(size.x - CORNER_LEN, 0),                    Vector2(CORNER_LEN, CORNER_THK)],
		[origin + Vector2(size.x - CORNER_THK, 0),                    Vector2(CORNER_THK, CORNER_LEN)],
		[origin + Vector2(0, size.y - CORNER_THK),                    Vector2(CORNER_LEN, CORNER_THK)],
		[origin + Vector2(0, size.y - CORNER_LEN),                    Vector2(CORNER_THK, CORNER_LEN)],
		[origin + Vector2(size.x - CORNER_LEN, size.y - CORNER_THK), Vector2(CORNER_LEN, CORNER_THK)],
		[origin + Vector2(size.x - CORNER_THK, size.y - CORNER_LEN), Vector2(CORNER_THK, CORNER_LEN)],
	]:
		var r      := ColorRect.new()
		r.color     = color
		r.position  = p[0]
		r.size      = p[1]
		result.append(r)
	return result


func _make_button(label: String, pos: Vector2, sz: Vector2, primary: bool) -> Button:
	var btn := Button.new()
	btn.text     = label
	btn.position = pos
	btn.size     = sz
	# process_mode est assigné individuellement après l'appel
	btn.add_theme_font_size_override("font_size", 13 if primary else 11)
	btn.add_theme_color_override("font_color",        COLOR_CYAN if primary else Color(0.4, 0.6, 0.7))
	btn.add_theme_color_override("font_hover_color",  Color.WHITE)
	btn.add_theme_color_override("font_pressed_color",COLOR_CYAN)

	var normal := StyleBoxFlat.new()
	normal.bg_color     = Color(0.0, 0.12, 0.2, 0.85) if primary else Color(0.0,0.0,0.0,0.0)
	normal.border_color = Color(COLOR_CYAN, 0.5)       if primary else Color(COLOR_CYAN, 0.15)
	normal.set_border_width_all(1 if primary else 0)
	btn.add_theme_stylebox_override("normal",  normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color     = Color(0.0, 0.25, 0.4, 0.9)
	hover.border_color = COLOR_CYAN
	hover.set_border_width_all(1)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.mouse_entered.connect(func():
		if _sfx_player and _SFX_HOVER:
			_sfx_player.stream      = _SFX_HOVER
			_sfx_player.volume_db   = 2.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	btn.pressed.connect(func():
		if _sfx_player and _SFX_CLICK:
			_sfx_player.stream      = _SFX_CLICK
			_sfx_player.volume_db   = 5.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	return btn


# =============================================================
# ANIMATION PANNEAU
# =============================================================

func _animate_panel_in() -> void:
	_overlay.visible  = true
	_overlay.color    = Color(0.0, 0.0, 0.0, 0.0)
	_panel.modulate   = Color(1.0, 1.0, 1.0, 0.0)
	_panel.scale      = Vector2(0.93, 0.93)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(_overlay, "color",    Color(0.0,0.0,0.0,0.65), 0.3)
	tween.tween_property(_panel,   "modulate", Color.WHITE,              0.3)
	tween.tween_property(_panel,   "scale",    Vector2(1.0, 1.0),        0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# =============================================================
# BOUTONS
# =============================================================

func _on_retry() -> void:
	get_tree().paused = false
	SaveData.reload_from_disk()   # Restaure les pièces/HP du dernier checkpoint
	# call_deferred obligatoire : reload depuis un signal callback provoque un crash
	get_tree().reload_current_scene.call_deferred()


func _on_quit() -> void:
	get_tree().quit()
