# =============================================================
# boss_key.gd — Clé droppée par le boss à sa mort
# Rebound Protocol
#
# Usage : instancié depuis BossLion._die().
# Kevin : connecte le signal "key_collected" depuis le portail
# pour déclencher l'ouverture vers la prochaine map.
# =============================================================
extends Node3D

## Émis quand le joueur récupère la clé.
signal key_collected

const KEY_MODEL    := preload("res://assets/models/platformerkit/key.glb")
const KEY_TEXTURE  := preload("res://assets/textures/platformerkit/colormap.png")

var _area:      Area3D  = null
var _bob_t:     float   = 0.0
var _base_y:    float   = 0.0
var _collected: bool    = false


func _ready() -> void:
	# ── Modèle 3D ────────────────────────────────────────────
	var model: Node3D = KEY_MODEL.instantiate()
	model.scale       = Vector3(1.4, 1.4, 1.4)
	add_child(model)
	_apply_texture(model)

	# ── Lumière dorée ─────────────────────────────────────────
	var light             := OmniLight3D.new()
	light.light_color      = Color(1.0, 0.82, 0.2)
	light.light_energy     = 2.5
	light.omni_range       = 3.0
	light.shadow_enabled   = false
	add_child(light)

	# ── Zone de détection joueur ──────────────────────────────
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask  = 1   # layer "player"
	var shape             := CollisionShape3D.new()
	var sphere            := SphereShape3D.new()
	sphere.radius          = 1.2
	shape.shape            = sphere
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)

	# ── Mémorise la hauteur de base pour le bob ───────────────
	# global_position est déjà positionné par BossLion AVANT add_child,
	# donc on calcule _base_y depuis la vraie position de spawn.
	_base_y = global_position.y + 0.6   # légèrement au-dessus du sol

	# ── Apparition : monte depuis le sol ──────────────────────
	global_position.y = _base_y - 0.6   # part légèrement sous le point de spawn
	var tw := create_tween()
	tw.tween_property(self, "global_position:y", _base_y, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply_texture(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = KEY_TEXTURE
		(node as MeshInstance3D).set_surface_override_material(0, mat)
	for child in node.get_children():
		_apply_texture(child)


func _process(delta: float) -> void:
	if _collected:
		return
	_bob_t += delta
	# Bob et rotation — utilise global_position.y pour rester cohérent
	# quel que soit la position de spawn (boss manuel ou via WaveManager).
	global_position.y = _base_y + sin(_bob_t * 1.8) * 0.12
	rotation.y += delta * 1.2   # rotation lente


func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return
	if not body.is_in_group("player"):
		return
	_collected = true

	# Signal pour Kevin / le portail
	key_collected.emit()

	# Effet de collecte : monte et disparaît
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", position.y + 1.2, 0.35).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "scale",      Vector3.ZERO,     0.35).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(func(): queue_free())
