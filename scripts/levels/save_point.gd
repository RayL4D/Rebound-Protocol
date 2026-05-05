# =============================================================
# save_point.gd — Point de sauvegarde avec flag.glb
# Rebound Protocol
# =============================================================
# Glisse scenes/levels/save_point.tscn dans ton niveau.
#
# Exports (Inspector) :
#   checkpoint_id — identifiant unique (ex. "level1_a")
#   level_name    — vide = détection auto depuis le chemin de scène
#   zone_radius   — rayon de la zone de détection (défaut 2.0 m)
#
# Sauvegarde à chaque passage : position, HP, niveau, checkpoint.
# Pièces et améliorations boutique sont déjà persistantes en continu.
# =============================================================

extends Node3D

@export var checkpoint_id: String = "checkpoint_default"
@export var level_name:    String = ""
@export var zone_radius:   float  = 2.0

signal save_triggered

const FLAG_PATH   := "res://assets/models/platformerkit/flag.glb"
const SHADER_PATH := "res://assets/shaders/save_point_ring.gdshader"

var _activated:  bool             = false
var _ring_mat:   ShaderMaterial   = null
var _pulse_time: float            = 0.0
var _flag_model: Node3D           = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_build_flag()
	_build_zone_ring()
	_build_trigger()


func _process(delta: float) -> void:
	_pulse_time += delta
	if _ring_mat:
		var p := sin(_pulse_time * 2.2) * 0.5 + 0.5
		_ring_mat.set_shader_parameter("pulse", p * 0.4)


# =============================================================
# CONSTRUCTION DU VISUEL
# =============================================================

func _build_flag() -> void:
	if not ResourceLoader.exists(FLAG_PATH):
		push_warning("SavePoint: flag.glb introuvable — " + FLAG_PATH)
		return
	var packed: PackedScene = load(FLAG_PATH)
	_flag_model = packed.instantiate()
	_flag_model.scale = Vector3(1.2, 1.2, 1.2)
	add_child(_flag_model)


func _build_zone_ring() -> void:
	var mesh_inst      := MeshInstance3D.new()
	var cyl            := CylinderMesh.new()
	cyl.top_radius      = zone_radius
	cyl.bottom_radius   = zone_radius
	cyl.height          = 0.02
	cyl.radial_segments = 48
	cyl.rings           = 1
	mesh_inst.mesh      = cyl
	mesh_inst.position.y = 0.01

	if ResourceLoader.exists(SHADER_PATH):
		var shader: Shader = load(SHADER_PATH)
		_ring_mat          = ShaderMaterial.new()
		_ring_mat.shader   = shader
		mesh_inst.material_override = _ring_mat
	else:
		# Fallback si le shader est absent : disque cyan uni
		var mat            := StandardMaterial3D.new()
		mat.albedo_color    = Color(0.0, 0.85, 1.0, 0.3)
		mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission        = Color(0.0, 0.85, 1.0)
		mat.emission_energy_multiplier = 0.8
		mesh_inst.material_override = mat

	add_child(mesh_inst)


func _build_trigger() -> void:
	var area            := Area3D.new()
	area.collision_layer = 0
	area.collision_mask  = 1
	area.monitoring      = true

	var shape           := CylinderShape3D.new()
	shape.radius         = zone_radius
	shape.height         = 2.0
	var col             := CollisionShape3D.new()
	col.shape            = shape
	col.position.y       = 1.0
	area.add_child(col)

	area.body_entered.connect(_on_player_entered)
	add_child(area)


# =============================================================
# DÉTECTION ET SAUVEGARDE
# =============================================================

func _on_player_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	_do_save(body)

	if not _activated:
		_activated = true
		_play_activate_animation()
	else:
		_play_repulse_animation()


func _do_save(player_node: Node3D) -> void:
	if SaveData.active_slot < 0:
		return

	var lname: String = level_name
	if lname == "":
		lname = get_tree().current_scene.scene_file_path.get_file().get_basename()

	SaveData.set_checkpoint(checkpoint_id)
	SaveData.set_current_level(lname)
	SaveData.set_player_position(player_node.global_position)

	# HP : accès sûr via get() sur le nœud
	if player_node.get("current_hp") != null:
		SaveData.set_player_hp(int(player_node.get("current_hp")))

	save_triggered.emit()


# =============================================================
# ANIMATIONS
# =============================================================

func _play_activate_animation() -> void:
	if _ring_mat:
		var tw := create_tween()
		tw.tween_method(
			func(c: Color): _ring_mat.set_shader_parameter("ring_color", c),
			Color(0.0, 0.85, 1.0, 0.55),
			Color(1.0, 0.85, 0.1, 0.80),
			0.35
		)

	if _flag_model:
		var tw2 := create_tween()
		tw2.tween_property(_flag_model, "position:y", 0.3, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_flag_model, "position:y", 0.0, 0.28) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	_spawn_burst(Color(0.3, 0.85, 1.0), 12)


func _play_repulse_animation() -> void:
	if _ring_mat:
		var tw := create_tween()
		tw.tween_method(
			func(v: float): _ring_mat.set_shader_parameter("pulse", v),
			1.0, 0.0, 0.4
		)


func _spawn_burst(color: Color, count: int) -> void:
	var origin := global_position + Vector3(0, 0.8, 0)
	var parent  := get_tree().current_scene

	for i in count:
		var angle := TAU * float(i) / float(count)
		var dir   := Vector3(cos(angle), randf_range(0.4, 1.2), sin(angle)).normalized()

		var sphere     := SphereMesh.new()
		sphere.radius   = 0.045
		sphere.height   = 0.09
		sphere.radial_segments = 4

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission    = color
		mat.emission_energy_multiplier = 2.2

		var mi         := MeshInstance3D.new()
		mi.mesh         = sphere
		mi.set_surface_override_material(0, mat)
		parent.add_child(mi)
		mi.global_position = origin

		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position",
			origin + dir * randf_range(0.6, 1.4), 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(
			func(a: float): mat.albedo_color = Color(color.r, color.g, color.b, a),
			1.0, 0.0, 0.55)
		tw.tween_callback(mi.queue_free)
