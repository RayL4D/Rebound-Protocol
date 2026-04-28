# =============================================================
# BossHealthBar.gd — Barre de vie 3D flottante (mini-boss)
# Rebound Protocol
# =============================================================
# Le remplissage est géré par un shader (paramètre fill_ratio)
# plutôt que par scale/position → aucune manipulation de géométrie,
# aucun désalignement possible.
# =============================================================
class_name BossHealthBar
extends Node3D

const BAR_WIDTH  := 2.4
const BAR_HEIGHT := 0.18
const Y_OFFSET   := 3.4

# Shader : clip les pixels dont UV.x > fill_ratio (barre alignée à gauche)
const FILL_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec4  bar_color  : source_color          = vec4(0.15, 0.85, 0.25, 1.0);

void fragment() {
	if (UV.x > fill_ratio) discard;
	ALBEDO = bar_color.rgb;
	ALPHA  = bar_color.a;
}
"""

var _fill_shader_mat: ShaderMaterial = null
var _name_label:      Label3D        = null
var _hp_label:        Label3D        = null

var _target_ratio:  float = 1.0
var _current_ratio: float = 1.0
var _pulse_time:    float = 0.0
var _camera:        Camera3D = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	set_as_top_level(true)
	_build()


func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()

	# Suivre le boss
	var parent := get_parent()
	if parent is Node3D:
		global_position = (parent as Node3D).global_position + Vector3(0.0, Y_OFFSET, 0.0)

	# Orienter +Z vers la caméra
	if _camera != null:
		var dir := _camera.global_position - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			global_rotation.y = atan2(dir.x, dir.z)

	# Interpolation du ratio
	_current_ratio = lerpf(_current_ratio, _target_ratio, 10.0 * delta)

	if _fill_shader_mat == null:
		return

	# Pousser fill_ratio dans le shader
	_fill_shader_mat.set_shader_parameter("fill_ratio", _current_ratio)

	# Couleur dynamique (couleurs vives)
	var col: Color
	if _current_ratio > 0.5:
		# Vert vif → Orange vif
		col = Color(0.1, 1.0, 0.3).lerp(Color(1.0, 0.55, 0.0), (1.0 - _current_ratio) * 2.0)
	else:
		# Rouge vif → Violet vif (phase 2)
		col = Color(1.0, 0.1, 0.15).lerp(Color(0.85, 0.1, 1.0), (0.5 - _current_ratio) * 2.0)

	# Pulsation blanche sous 25 %
	if _current_ratio < 0.25:
		_pulse_time += delta * 7.0
		col = col.lerp(Color(1.0, 1.0, 1.0), abs(sin(_pulse_time)) * 0.55)

	_fill_shader_mat.set_shader_parameter("bar_color", col)


# =============================================================
# API PUBLIQUE
# =============================================================

func setup(boss_name: String, max_hp: int) -> void:
	if _name_label != null:
		_name_label.text = boss_name
	update_hp(max_hp, max_hp)


func update_hp(current: int, max_hp: int) -> void:
	_target_ratio = float(max(0, current)) / float(max_hp)
	if _hp_label != null:
		_hp_label.text = "%d / %d" % [current, max_hp]


# =============================================================
# CONSTRUCTION
# =============================================================

func _build() -> void:
	# Fond — priorité 1 (dessiné en premier, derrière tout)
	_add_quad(
		Vector2(BAR_WIDTH + 0.10, BAR_HEIGHT + 0.10),
		Vector3(0.0, 0.0, 0.0),
		Color(0.03, 0.03, 0.06, 0.92),
		1
	)

	# Remplissage via shader
	var shader     := Shader.new()
	shader.code     = FILL_SHADER
	_fill_shader_mat = ShaderMaterial.new()
	_fill_shader_mat.shader = shader
	_fill_shader_mat.render_priority = 2   # > fond (1) → rendu par-dessus
	_fill_shader_mat.set_shader_parameter("fill_ratio", 1.0)
	_fill_shader_mat.set_shader_parameter("bar_color",  Color(0.1, 1.0, 0.3, 1.0))

	var fill_mi   := MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	fill_mi.mesh   = fill_mesh
	fill_mi.position = Vector3(0.0, 0.0, 0.001)
	fill_mi.set_surface_override_material(0, _fill_shader_mat)
	add_child(fill_mi)

	# Marqueur de phase à 50 % (trait blanc au centre)
	_add_quad(
		Vector2(0.03, BAR_HEIGHT + 0.06),
		Vector3(0.0, 0.0, 0.003),
		Color(1.0, 1.0, 1.0, 0.8)
	)

	# Bordures cyan gauche / droite
	_add_quad(
		Vector2(0.04, BAR_HEIGHT + 0.10),
		Vector3(-(BAR_WIDTH * 0.5 + 0.05), 0.0, 0.003),
		Color(0.0, 0.85, 1.0, 1.0)
	)
	_add_quad(
		Vector2(0.04, BAR_HEIGHT + 0.10),
		Vector3( (BAR_WIDTH * 0.5 + 0.05), 0.0, 0.003),
		Color(0.0, 0.85, 1.0, 1.0)
	)

	# Nom du boss (au-dessus)
	_name_label                  = Label3D.new()
	_name_label.font_size        = 26
	_name_label.modulate         = Color(0.0, 0.85, 1.0)
	_name_label.outline_size     = 8
	_name_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_name_label.no_depth_test    = true
	_name_label.position         = Vector3(0.0, BAR_HEIGHT + 0.20, 0.003)
	add_child(_name_label)

	# HP numérique (en dessous)
	_hp_label                  = Label3D.new()
	_hp_label.font_size        = 18
	_hp_label.modulate         = Color(1.0, 1.0, 1.0)
	_hp_label.outline_size     = 5
	_hp_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_hp_label.no_depth_test    = true
	_hp_label.position         = Vector3(0.0, -(BAR_HEIGHT + 0.18), 0.003)
	add_child(_hp_label)


func _add_quad(size: Vector2, pos: Vector3, color: Color, priority: int = 3) -> MeshInstance3D:
	var mi     := MeshInstance3D.new()
	var quad   := QuadMesh.new()
	quad.size   = size
	mi.mesh     = quad
	mi.position = pos

	var mat            := StandardMaterial3D.new()
	mat.albedo_color    = color
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test   = true
	mat.render_priority = priority
	mi.set_surface_override_material(0, mat)

	add_child(mi)
	return mi
