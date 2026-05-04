# =============================================================
# HUD.gd — Interface joueur
# Rebound Protocol
# =============================================================
# Barre HP fixe en haut à gauche — style cyberpunk RPG.
# • Panel semi-transparent avec coins décoratifs
# • Header « SYS · INTEGRITY »
# • Barre segmentée avec glow et highlight
# • Couleur : cyan → orange → rouge selon les HP
# • Pulsation rouge quand HP < 30 %
# • Vignette de dégât plein écran
# • Barre de boss en bas de l'écran
# • Pointeur d'objectif
# =============================================================
extends CanvasLayer

# --- Dimensions du panel HP -----------------------------------
const PANEL_W    := 260.0
const PANEL_H    := 74.0
const PANEL_X    := 16.0
const PANEL_Y    := 16.0
const BAR_W      := 228.0
const BAR_H      := 14.0
const BAR_X      := 16.0          # offset X dans le panel
const BAR_Y      := 34.0          # offset Y dans le panel
const SEGMENTS   := 8             # séparateurs dans la barre
const CORNER_LEN := 9.0
const CORNER_THK := 2.0

# --- Dimensions barre boss ------------------------------------
const BOSS_BAR_WIDTH  := 320.0
const BOSS_BAR_HEIGHT := 14.0

# --- Palette --------------------------------------------------
const COLOR_CYAN   := Color(0.00, 0.85, 1.00)
const COLOR_BG     := Color(0.012, 0.040, 0.090, 0.92)
const COLOR_BORDER := Color(0.00, 0.80, 1.00, 0.80)
const COLOR_SEP    := Color(0.00, 0.80, 1.00, 0.22)
const COLOR_HEADER := Color(0.55, 0.97, 1.00, 0.70)
const COLOR_HPNUM  := Color(0.85, 1.00, 1.00, 0.90)

# --- Shader vignette dégât ------------------------------------
const DAMAGE_VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float edge = min(1.0 - abs(uv.x), 1.0 - abs(uv.y));
	float rim   = smoothstep(0.18, 0.0,  edge);
	float glow  = smoothstep(0.38, 0.10, edge) * 0.18;
	float alpha = clamp(rim * 0.7 + glow, 0.0, 1.0) * intensity;
	vec3 col = mix(vec3(0.55, 0.0, 0.0), vec3(1.0, 0.12, 0.12), rim);
	COLOR = vec4(col, alpha);
}
"""

# --- Refs UI --------------------------------------------------
var _container:    Control
var _fill:         ColorRect
var _highlight:    ColorRect
var _glow1:        ColorRect
var _glow2:        ColorRect
var _hp_label:     Label
var _corners:      Array[ColorRect] = []

# --- État animation -------------------------------------------
var _player:       Player   = null
var _camera:       Camera3D = null
var _current_fill: float    = 1.0
var _target_fill:  float    = 1.0
var _pulse_time:   float    = 0.0

# --- Vignette dégât -------------------------------------------
var _vignette_rect: ColorRect      = null
var _vignette_mat:  ShaderMaterial = null
var _vignette_tween: Tween         = null

# --- Pointeur objectif ----------------------------------------
var _guide_icon:  TextureRect = null
var guide_target: Node3D      = null

# --- Barre boss -----------------------------------------------
var _boss_bar_container: Control   = null
var _boss_bar_bg:        ColorRect = null
var _boss_bar_fill:      ColorRect = null
var _boss_name_label:    Label     = null
var _boss_hp_label:      Label     = null
var _boss_max_hp:        int       = 1
var _boss_target_fill:   float     = 1.0
var _boss_current_fill:  float     = 1.0


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_build_ui()
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		push_warning("HUD: joueur introuvable.")
		return
	_camera       = get_viewport().get_camera_3d()
	_target_fill  = float(_player.current_hp) / float(_player.max_hp)
	_current_fill = _target_fill
	_refresh_bar(_current_fill)
	_update_label(_player.current_hp)
	_player.hp_changed.connect(_on_hp_changed)
	_player.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	if _player == null:
		return

	# --- Barre HP boss (interpolée) ---
	if _boss_bar_container != null and _boss_bar_container.visible:
		_boss_current_fill = lerp(_boss_current_fill, _boss_target_fill, 10.0 * delta)
		_boss_bar_fill.size.x = BOSS_BAR_WIDTH * _boss_current_fill
		var bc: Color
		if _boss_current_fill > 0.5:
			bc = Color(1.0, 0.2, 0.2).lerp(Color(1.0, 0.55, 0.0), (_boss_current_fill - 0.5) * 2.0)
		else:
			bc = Color(0.5, 0.0, 0.8).lerp(Color(1.0, 0.2, 0.2), _boss_current_fill * 2.0)
		_boss_bar_fill.color = bc

	# --- Barre HP joueur (interpolée, fixe en haut à gauche) ---
	_current_fill = lerp(_current_fill, _target_fill, 12.0 * delta)
	_refresh_bar(_current_fill)

	if _target_fill < 0.3:
		_pulse_time += delta * 5.0
		var p := sin(_pulse_time) * 0.5 + 0.5
		var pulse_col := Color(1.0, 0.08 + p * 0.15, 0.08)
		_fill.color  = pulse_col
		_glow1.color = Color(pulse_col.r, pulse_col.g, pulse_col.b, 0.30)
		_glow2.color = Color(pulse_col.r, pulse_col.g, pulse_col.b, 0.14)
		for c in _corners:
			c.color = pulse_col
	else:
		_pulse_time = 0.0

	# --- Pointeur objectif ---
	if _camera != null and guide_target != null and is_instance_valid(guide_target):
		if _camera.is_position_behind(guide_target.global_position):
			_guide_icon.hide()
		else:
			var tp := _camera.unproject_position(guide_target.global_position)
			var ts := _guide_icon.texture.get_size() if _guide_icon.texture else Vector2(32, 32)
			_guide_icon.position = tp - ts * 0.5
			_guide_icon.show()
	elif _guide_icon != null and _guide_icon.visible:
		_guide_icon.hide()


# =============================================================
# BUILD UI
# =============================================================

func _build_ui() -> void:
	# --- Vignette dégât (plein écran, derrière tout) ---
	var shader         := Shader.new()
	shader.code         = DAMAGE_VIGNETTE_SHADER
	_vignette_mat       = ShaderMaterial.new()
	_vignette_mat.shader = shader
	_vignette_rect      = ColorRect.new()
	_vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.material     = _vignette_mat
	add_child(_vignette_rect)

	# --- Pointeur objectif ---
	_guide_icon = TextureRect.new()
	_guide_icon.texture      = preload("res://ui_theme/png/cursor/cursor_pointer3D.png")
	_guide_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_icon.hide()
	add_child(_guide_icon)

	# --- Panel HP (haut gauche) ---
	_container              = Control.new()
	_container.name         = "HPPanel"
	_container.size         = Vector2(PANEL_W, PANEL_H)
	_container.position     = Vector2(PANEL_X, PANEL_Y)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	# Fond sombre
	var bg             := ColorRect.new()
	bg.color            = COLOR_BG
	bg.size             = Vector2(PANEL_W, PANEL_H)
	bg.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	_container.add_child(bg)

	# Ligne décorative verticale gauche (accent)
	var accent_line        := ColorRect.new()
	accent_line.color       = Color(COLOR_CYAN, 0.80)
	accent_line.position    = Vector2(0.0, 0.0)
	accent_line.size        = Vector2(3.0, PANEL_H)
	accent_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(accent_line)

	# Header « SYS · INTEGRITY »
	var header              := Label.new()
	header.text              = "SYS · INTEGRITY"
	header.position          = Vector2(BAR_X, 7.0)
	header.size              = Vector2(160.0, 14.0)
	header.add_theme_font_size_override("font_size", 9)
	header.add_theme_color_override("font_color", COLOR_HEADER)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(header)

	# Icône ◈ + "HP" à droite du header
	var icon_label              := Label.new()
	icon_label.text              = "◈  HP"
	icon_label.position          = Vector2(PANEL_W - 58.0, 7.0)
	icon_label.size              = Vector2(50.0, 14.0)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	icon_label.add_theme_font_size_override("font_size", 9)
	icon_label.add_theme_color_override("font_color", Color(COLOR_CYAN, 0.55))
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(icon_label)

	# Séparateur fin
	var sep            := ColorRect.new()
	sep.color           = COLOR_SEP
	sep.position        = Vector2(BAR_X, 24.0)
	sep.size            = Vector2(PANEL_W - BAR_X * 2.0, 1.0)
	sep.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	_container.add_child(sep)

	# --- Barre ---

	# Fond de la barre
	var bar_bg         := ColorRect.new()
	bar_bg.color        = Color(0.0, 0.03, 0.07, 1.0)
	bar_bg.position     = Vector2(BAR_X, BAR_Y)
	bar_bg.size         = Vector2(BAR_W, BAR_H)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(bar_bg)

	# Glow bas (simulé avec deux rects semi-transparents sous la barre)
	_glow2              = ColorRect.new()
	_glow2.color        = Color(COLOR_CYAN, 0.10)
	_glow2.position     = Vector2(BAR_X, BAR_Y + BAR_H + 2.0)
	_glow2.size         = Vector2(BAR_W, 4.0)
	_glow2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_glow2)

	_glow1              = ColorRect.new()
	_glow1.color        = Color(COLOR_CYAN, 0.22)
	_glow1.position     = Vector2(BAR_X, BAR_Y + BAR_H)
	_glow1.size         = Vector2(BAR_W, 3.0)
	_glow1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_glow1)

	# Remplissage principal
	_fill               = ColorRect.new()
	_fill.color         = COLOR_CYAN
	_fill.position      = Vector2(BAR_X, BAR_Y)
	_fill.size          = Vector2(BAR_W, BAR_H)
	_fill.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_fill)

	# Highlight (ligne brillante en haut de la barre)
	_highlight              = ColorRect.new()
	_highlight.color         = Color(1.0, 1.0, 1.0, 0.28)
	_highlight.position      = Vector2(BAR_X, BAR_Y)
	_highlight.size          = Vector2(BAR_W, 3.0)
	_highlight.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_highlight)

	# Séparateurs de segments
	for i in SEGMENTS:
		var dx         := BAR_X + BAR_W * float(i + 1) / float(SEGMENTS + 1)
		var seg        := ColorRect.new()
		seg.color       = Color(0.0, 0.0, 0.0, 0.45)
		seg.position    = Vector2(dx, BAR_Y)
		seg.size        = Vector2(1.5, BAR_H)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_container.add_child(seg)

	# Label HP numérique
	_hp_label               = Label.new()
	_hp_label.position       = Vector2(BAR_X, BAR_Y + BAR_H + 8.0)
	_hp_label.size           = Vector2(BAR_W, 14.0)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.add_theme_font_size_override("font_size", 9)
	_hp_label.add_theme_color_override("font_color", COLOR_HPNUM)
	_hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_hp_label.add_theme_constant_override("outline_size", 2)
	_hp_label.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_hp_label)

	# Coins décoratifs (sur tout le panel)
	_corners = _make_corners(Vector2.ZERO, Vector2(PANEL_W, PANEL_H), COLOR_BORDER)
	for c in _corners:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_container.add_child(c)


func _make_corners(origin: Vector2, sz: Vector2, color: Color) -> Array[ColorRect]:
	var result: Array[ColorRect] = []
	var positions := [
		[origin,                                              Vector2(CORNER_LEN, CORNER_THK)],
		[origin,                                              Vector2(CORNER_THK, CORNER_LEN)],
		[origin + Vector2(sz.x - CORNER_LEN, 0),              Vector2(CORNER_LEN, CORNER_THK)],
		[origin + Vector2(sz.x - CORNER_THK, 0),              Vector2(CORNER_THK, CORNER_LEN)],
		[origin + Vector2(0, sz.y - CORNER_THK),              Vector2(CORNER_LEN, CORNER_THK)],
		[origin + Vector2(0, sz.y - CORNER_LEN),              Vector2(CORNER_THK, CORNER_LEN)],
		[origin + Vector2(sz.x - CORNER_LEN, sz.y - CORNER_THK), Vector2(CORNER_LEN, CORNER_THK)],
		[origin + Vector2(sz.x - CORNER_THK, sz.y - CORNER_LEN), Vector2(CORNER_THK, CORNER_LEN)],
	]
	for p in positions:
		var r         := ColorRect.new()
		r.color        = color
		r.position     = p[0]
		r.size         = p[1]
		result.append(r)
	return result


# =============================================================
# REFRESH
# =============================================================

func _refresh_bar(fill: float) -> void:
	var w := BAR_W * fill
	_fill.size.x      = w
	_highlight.size.x = w
	_glow1.size.x     = w
	_glow2.size.x     = w

	# Couleur selon le niveau de vie
	var col: Color
	if fill > 0.5:
		col = COLOR_CYAN.lerp(Color(1.0, 0.60, 0.0), (1.0 - fill) * 2.0)
	else:
		col = Color(1.0, 0.60, 0.0).lerp(Color(1.0, 0.08, 0.08), (0.5 - fill) * 2.0)

	if _target_fill >= 0.3:
		_fill.color  = col
		_glow1.color = Color(col.r, col.g, col.b, 0.30)
		_glow2.color = Color(col.r, col.g, col.b, 0.14)
		for c in _corners:
			c.color = Color(col.r * 0.6 + 0.0 * 0.4,
							col.g * 0.4 + 0.8 * 0.6,
							col.b * 0.3 + 1.0 * 0.7,
							COLOR_BORDER.a)


# =============================================================
# CALLBACKS
# =============================================================

func _on_hp_changed(new_hp: int) -> void:
	_target_fill = float(new_hp) / float(_player.max_hp)
	_update_label(new_hp)
	_flash_damage_vignette()


func _on_player_died() -> void:
	_target_fill = 0.0
	_update_label(0)


func _update_label(hp: int) -> void:
	_hp_label.text = "%d / %d" % [hp, _player.max_hp]


func _flash_damage_vignette() -> void:
	if _vignette_mat == null:
		return
	if _vignette_tween:
		_vignette_tween.kill()
	_vignette_mat.set_shader_parameter("intensity", 1.0)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(
		func(v: float): _vignette_mat.set_shader_parameter("intensity", v),
		1.0, 0.0, 0.7
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


# =============================================================
# BARRE HP DU BOSS
# =============================================================

func _build_boss_bar() -> void:
	var panel_h := BOSS_BAR_HEIGHT + 36.0

	_boss_bar_container            = Control.new()
	_boss_bar_container.name       = "BossHPContainer"
	_boss_bar_container.size       = Vector2(BOSS_BAR_WIDTH + 20.0, panel_h)
	_boss_bar_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_boss_bar_container.anchor_top    = 1.0
	_boss_bar_container.anchor_bottom = 1.0
	_boss_bar_container.offset_top    = -panel_h - 18.0
	_boss_bar_container.offset_bottom = -18.0
	_boss_bar_container.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_bar_container)

	_boss_name_label = Label.new()
	_boss_name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_boss_name_label.size = Vector2(BOSS_BAR_WIDTH + 20.0, 20.0)
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_font_size_override("font_size", 12)
	_boss_name_label.add_theme_color_override("font_color", COLOR_CYAN)
	_boss_name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_boss_name_label.add_theme_constant_override("outline_size", 4)
	_boss_bar_container.add_child(_boss_name_label)

	var bar_y := 22.0
	var bar_x := 10.0

	_boss_bar_bg          = ColorRect.new()
	_boss_bar_bg.color    = Color(0.0, 0.05, 0.1, 0.9)
	_boss_bar_bg.position = Vector2(bar_x, bar_y)
	_boss_bar_bg.size     = Vector2(BOSS_BAR_WIDTH, BOSS_BAR_HEIGHT)
	_boss_bar_container.add_child(_boss_bar_bg)

	_boss_bar_fill          = ColorRect.new()
	_boss_bar_fill.color    = Color(1.0, 0.2, 0.2)
	_boss_bar_fill.position = Vector2(bar_x, bar_y)
	_boss_bar_fill.size     = Vector2(BOSS_BAR_WIDTH, BOSS_BAR_HEIGHT)
	_boss_bar_container.add_child(_boss_bar_fill)

	for corner in _make_corners(
		Vector2(bar_x - 2.0, bar_y - 2.0),
		Vector2(BOSS_BAR_WIDTH + 4.0, BOSS_BAR_HEIGHT + 4.0),
		COLOR_CYAN
	):
		_boss_bar_container.add_child(corner)

	_boss_hp_label          = Label.new()
	_boss_hp_label.position = Vector2(bar_x, bar_y)
	_boss_hp_label.size     = Vector2(BOSS_BAR_WIDTH, BOSS_BAR_HEIGHT)
	_boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_hp_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_boss_hp_label.add_theme_font_size_override("font_size", 9)
	_boss_hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_boss_hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_boss_hp_label.add_theme_constant_override("outline_size", 3)
	_boss_bar_container.add_child(_boss_hp_label)

	_boss_bar_container.hide()


func show_boss_bar(boss_name: String, max_hp: int) -> void:
	if _boss_bar_container == null:
		_build_boss_bar()
	_boss_max_hp       = max_hp
	_boss_target_fill  = 1.0
	_boss_current_fill = 1.0
	_boss_name_label.text = boss_name
	_boss_hp_label.text   = "%d / %d" % [max_hp, max_hp]
	_boss_bar_fill.size.x = BOSS_BAR_WIDTH
	_boss_bar_container.show()


func update_boss_hp(current_hp: int, max_hp: int) -> void:
	if _boss_bar_container == null:
		return
	_boss_target_fill   = float(current_hp) / float(max_hp)
	_boss_hp_label.text = "%d / %d" % [current_hp, max_hp]


func hide_boss_bar() -> void:
	if _boss_bar_container != null:
		_boss_bar_container.hide()
