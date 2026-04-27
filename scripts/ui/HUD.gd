# =============================================================
# HUD.gd — Interface joueur (barre de vie holographique + Pointeur)
# =============================================================
extends CanvasLayer

const BAR_WIDTH  := 120.0
const BAR_HEIGHT := 8.0
const CORNER_LEN := 6.0
const CORNER_THK := 1.5

var _container:  Control
var _bg:         ColorRect
var _fill:       ColorRect
var _highlight:  ColorRect
var _hp_label:   Label
var _corners:    Array[ColorRect] = []

var _player:        Player   = null
var _camera:        Camera3D = null
var _current_fill:  float    = 1.0
var _target_fill:   float    = 1.0
var _pulse_time:    float    = 0.0

const WORLD_OFFSET := Vector3(0.0, 2.4, 0.0)
const COLOR_CYAN   := Color(0.0, 0.85, 1.0)

# --- Vignette de dégât -------------------------------------------
var _vignette_rect: ColorRect      = null
var _vignette_mat:  ShaderMaterial = null
var _vignette_tween: Tween         = null

# --- Pointeur de fin de niveau -----------------------------------
var _guide_icon: TextureRect = null
var guide_target: Node3D = null

# --- Barre HP du boss -------------------------------------------
var _boss_bar_container: Control  = null
var _boss_bar_bg:        ColorRect = null
var _boss_bar_fill:      ColorRect = null
var _boss_name_label:    Label     = null
var _boss_hp_label:      Label     = null
var _boss_max_hp:        int       = 1
var _boss_target_fill:   float     = 1.0
var _boss_current_fill:  float     = 1.0

const BOSS_BAR_WIDTH  := 320.0
const BOSS_BAR_HEIGHT := 14.0

const DAMAGE_VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float edge = min(1.0 - abs(uv.x), 1.0 - abs(uv.y));
	float rim   = smoothstep(0.18, 0.0,  edge);
	float glow  = smoothstep(0.38, 0.10, edge) * 0.18;
	float line  = smoothstep(0.02, 0.0,  abs(edge - 0.01)) * 0.6;
	float alpha = clamp(rim * 0.7 + glow + line, 0.0, 1.0) * intensity;
	vec3 col = mix(vec3(0.55, 0.0, 0.0), vec3(1.0, 0.12, 0.12), rim);
	COLOR = vec4(col, alpha);
}
"""

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
	if _player == null or _camera == null:
		return

	# --- Barre HP du boss (interpolée) ---
	if _boss_bar_container != null and _boss_bar_container.visible:
		_boss_current_fill = lerp(_boss_current_fill, _boss_target_fill, 10.0 * delta)
		_boss_bar_fill.size.x = BOSS_BAR_WIDTH * _boss_current_fill
		var col: Color
		if _boss_current_fill > 0.5:
			col = Color(1.0, 0.2, 0.2).lerp(Color(1.0, 0.55, 0.0), (_boss_current_fill - 0.5) * 2.0)
		else:
			col = Color(0.5, 0.0, 0.8).lerp(Color(1.0, 0.2, 0.2), _boss_current_fill * 2.0)
		_boss_bar_fill.color = col

	# --- Gestion de la barre de vie ---
	var screen_pos := _camera.unproject_position(_player.global_position + WORLD_OFFSET)
	_container.position = screen_pos - _container.size * 0.5

	_current_fill = lerp(_current_fill, _target_fill, 12.0 * delta)
	_refresh_bar(_current_fill)

	if _target_fill < 0.3:
		_pulse_time += delta * 5.0
		var p := sin(_pulse_time) * 0.5 + 0.5
		var pulse_col := Color(1.0, 0.1 + p * 0.2, 0.1)
		_fill.color = pulse_col
		for c in _corners:
			c.color = pulse_col
	else:
		_pulse_time = 0.0
		
	# --- Gestion du pointeur d'objectif ---
	if guide_target != null and is_instance_valid(guide_target):
		# Si la cible est derrière la caméra, on cache le curseur
		if _camera.is_position_behind(guide_target.global_position):
			_guide_icon.hide()
		else:
			var target_pos2d = _camera.unproject_position(guide_target.global_position)
			var tex_size = _guide_icon.texture.get_size() if _guide_icon.texture else Vector2(32, 32)
			
			# Centre l'icône sur la cible
			_guide_icon.position = target_pos2d - (tex_size / 2.0)
			_guide_icon.show()
	elif _guide_icon.visible:
		_guide_icon.hide()


# =============================================================
# BUILD
# =============================================================

func _build_ui() -> void:
	# Vignette de dégât
	var shader        := Shader.new()
	shader.code        = DAMAGE_VIGNETTE_SHADER
	_vignette_mat      = ShaderMaterial.new()
	_vignette_mat.shader = shader
	_vignette_rect     = ColorRect.new()
	_vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.material     = _vignette_mat
	add_child(_vignette_rect)

	# --- Création de l'icône de guidage ---
	_guide_icon = TextureRect.new()
	# /!\ Vérifiez que le chemin de votre image est bien le bon ici :
	_guide_icon.texture = preload("res://ui_theme/png/cursor/cursor_pointer3D.png") 
	_guide_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_icon.hide()
	add_child(_guide_icon)

	# Conteneur HP
	var total_w := BAR_WIDTH + 24.0   
	var total_h := BAR_HEIGHT + 14.0

	_container      = Control.new()
	_container.name = "HPContainer"
	_container.size = Vector2(total_w, total_h)
	add_child(_container)

	# Label "HP"
	var tag              := Label.new()
	tag.text              = "HP"
	tag.size              = Vector2(20.0, total_h)
	tag.position          = Vector2(0.0, 0.0)
	tag.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 7)
	tag.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0, 0.8))
	_container.add_child(tag)

	var bar_x := 22.0
	var bar_y := (total_h - BAR_HEIGHT) * 0.5

	# Fond sombre
	_bg           = ColorRect.new()
	_bg.color     = Color(0.0, 0.05, 0.1, 0.9)
	_bg.position  = Vector2(bar_x, bar_y)
	_bg.size      = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_container.add_child(_bg)

	# Remplissage
	_fill         = ColorRect.new()
	_fill.position = Vector2(bar_x, bar_y)
	_fill.size    = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_container.add_child(_fill)

	# Ligne brillante (gloss)
	_highlight        = ColorRect.new()
	_highlight.color  = Color(1.0, 1.0, 1.0, 0.45)
	_highlight.position = Vector2(bar_x, bar_y)
	_highlight.size   = Vector2(BAR_WIDTH, 2.0)
	_container.add_child(_highlight)

	# Coins décoratifs autour de la barre
	var bx := bar_x - 2.0
	var by := bar_y - 2.0
	var bw := BAR_WIDTH + 4.0
	var bh := BAR_HEIGHT + 4.0
	_corners = _make_corners(Vector2(bx, by), Vector2(bw, bh), COLOR_CYAN)
	for c in _corners:
		_container.add_child(c)

	# Valeur HP
	_hp_label = Label.new()
	_hp_label.size     = Vector2(total_w, total_h)
	_hp_label.position = Vector2(0.0, 0.0)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 7)
	_hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_hp_label.add_theme_constant_override("outline_size", 3)
	_container.add_child(_hp_label)


func _make_corners(origin: Vector2, size: Vector2, color: Color) -> Array[ColorRect]:
	var result: Array[ColorRect] = []
	var positions := [
		[origin,                                           Vector2(CORNER_LEN, CORNER_THK)],
		[origin,                                           Vector2(CORNER_THK, CORNER_LEN)],
		[origin + Vector2(size.x - CORNER_LEN, 0),         Vector2(CORNER_LEN, CORNER_THK)],
		[origin + Vector2(size.x - CORNER_THK, 0),         Vector2(CORNER_THK, CORNER_LEN)],
		[origin + Vector2(0, size.y - CORNER_THK),         Vector2(CORNER_LEN, CORNER_THK)],
		[origin + Vector2(0, size.y - CORNER_LEN),         Vector2(CORNER_THK, CORNER_LEN)],
		[origin + Vector2(size.x - CORNER_LEN, size.y - CORNER_THK), Vector2(CORNER_LEN, CORNER_THK)],
		[origin + Vector2(size.x - CORNER_THK, size.y - CORNER_LEN), Vector2(CORNER_THK, CORNER_LEN)],
	]
	for p in positions:
		var r         = ColorRect.new()
		r.color        = color
		r.position     = p[0]
		r.size         = p[1]
		result.append(r)
	return result


# =============================================================
# REFRESH
# =============================================================

func _refresh_bar(fill: float) -> void:
	_fill.size.x      = BAR_WIDTH * fill
	_highlight.size.x = BAR_WIDTH * fill

	var col: Color
	if fill > 0.5:
		col = COLOR_CYAN.lerp(Color(1.0, 0.6, 0.0), (1.0 - fill) * 2.0)
	else:
		col = Color(1.0, 0.6, 0.0).lerp(Color(1.0, 0.08, 0.08), (0.5 - fill) * 2.0)

	if _target_fill >= 0.3:
		_fill.color = col
		for c in _corners:
			c.color = col


func _on_hp_changed(new_hp: int) -> void:
	_target_fill = float(new_hp) / float(_player.max_hp)
	_update_label(new_hp)
	_flash_damage_vignette()


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


func _on_player_died() -> void:
	_target_fill = 0.0
	_update_label(0)


func _update_label(hp: int) -> void:
	_hp_label.text = "%d/%d  " % [hp, _player.max_hp]


# =============================================================
# BARRE HP DU BOSS
# =============================================================

func _build_boss_bar() -> void:
	var panel_h := BOSS_BAR_HEIGHT + 36.0

	_boss_bar_container = Control.new()
	_boss_bar_container.name = "BossHPContainer"
	_boss_bar_container.size = Vector2(BOSS_BAR_WIDTH + 20.0, panel_h)
	# Centrer horizontalement, ancrer en bas
	_boss_bar_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_boss_bar_container.anchor_top    = 1.0
	_boss_bar_container.anchor_bottom = 1.0
	_boss_bar_container.offset_top    = -panel_h - 18.0
	_boss_bar_container.offset_bottom = -18.0
	_boss_bar_container.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_bar_container)

	# Nom du boss
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

	# Fond de la barre
	_boss_bar_bg = ColorRect.new()
	_boss_bar_bg.color    = Color(0.0, 0.05, 0.1, 0.9)
	_boss_bar_bg.position = Vector2(bar_x, bar_y)
	_boss_bar_bg.size     = Vector2(BOSS_BAR_WIDTH, BOSS_BAR_HEIGHT)
	_boss_bar_container.add_child(_boss_bar_bg)

	# Remplissage
	_boss_bar_fill = ColorRect.new()
	_boss_bar_fill.color    = Color(1.0, 0.2, 0.2)
	_boss_bar_fill.position = Vector2(bar_x, bar_y)
	_boss_bar_fill.size     = Vector2(BOSS_BAR_WIDTH, BOSS_BAR_HEIGHT)
	_boss_bar_container.add_child(_boss_bar_fill)

	# Bordure décorative
	for corner in _make_corners(
		Vector2(bar_x - 2.0, bar_y - 2.0),
		Vector2(BOSS_BAR_WIDTH + 4.0, BOSS_BAR_HEIGHT + 4.0),
		COLOR_CYAN
	):
		_boss_bar_container.add_child(corner)

	# Label HP
	_boss_hp_label = Label.new()
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
	_boss_max_hp = max_hp
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
