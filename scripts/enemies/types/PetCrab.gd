# =============================================================
# PetCrab.gd — Pet tank blindé avec bouclier périodique (crabe)
# Rebound Protocol
# =============================================================
# Comportement :
#   • Avance lentement vers le joueur — très robuste (80 HP)
#   • S'arrête à courte portée et tire des balles lourdes
#   • Active un bouclier toutes les 8 s → immunité totale pendant 3 s
#   • Le bouclier est une sphère bleue semi-transparente visible
#   • Cible prioritaire : difficile à abattre, dangereux de l'ignorer
#
# Design : force le joueur à gérer un ennemi-tank imprévisible.
#   Le bouclier périodique oblige à adapter le rythme d'attaque.
#
# Hiérarchie de scène attendue :
#   PetCrab (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-crab.glb]
#   ├── WeaponMount (Node3D)
#   │   ├── [Modèle blaster-f.glb]
#   │   └── WeaponBullet (Node3D) ← tir lent, fort, courte portée
# =============================================================
class_name PetCrab
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var stop_distance:   float = 3.5   # distance à laquelle il s'arrête
@export var shield_cooldown: float = 8.0   # secondes entre deux boucliers
@export var shield_duration: float = 3.0   # durée du bouclier
@export var shield_radius:   float = 1.2   # rayon de la sphère visuelle

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponBullet = $WeaponMount/WeaponBullet

# --- État du bouclier -------------------------------------------
var _shield_active: bool        = false
var _shield_timer:  float       = 0.0
var _shield_mesh:   MeshInstance3D = null


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	_shield_timer = shield_cooldown   # premier bouclier après X secondes
	_create_shield_mesh()

	if weapon == null:
		push_error("PetCrab: nœud WeaponBullet introuvable — vérifie $WeaponMount/WeaponBullet")
		return
	if player == null:
		return
	weapon.activate(player)


func _create_shield_mesh() -> void:
	_shield_mesh = MeshInstance3D.new()

	var sph          := SphereMesh.new()
	sph.radius        = shield_radius
	sph.height        = shield_radius * 2.0
	_shield_mesh.mesh = sph

	var mat                        := StandardMaterial3D.new()
	mat.albedo_color                = Color(0.3, 0.6, 1.0, 0.35)
	mat.transparency                = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled            = true
	mat.emission                    = Color(0.2, 0.5, 1.0)
	mat.emission_energy_multiplier  = 2.5
	mat.cull_mode                   = BaseMaterial3D.CULL_DISABLED
	_shield_mesh.set_surface_override_material(0, mat)

	_shield_mesh.position.y = 0.7   # centré sur le corps du pet
	_shield_mesh.visible    = false
	add_child(_shield_mesh)


# =============================================================
# OVERRIDE _physics_process — gestion du bouclier chaque frame
# =============================================================

func _physics_process(delta: float) -> void:
	_update_shield(delta)
	super._physics_process(delta)


func _update_shield(delta: float) -> void:
	_shield_timer -= delta

	if not _shield_active:
		if _shield_timer <= 0.0:
			_shield_active       = true
			_shield_timer        = shield_duration
			if _shield_mesh:
				_shield_mesh.visible = true
	else:
		if _shield_timer <= 0.0:
			_shield_active       = false
			_shield_timer        = shield_cooldown
			if _shield_mesh:
				_shield_mesh.visible = false


# =============================================================
# SANTÉ — immunité totale pendant le bouclier
# =============================================================

func take_damage(amount: int, silent_hurt: bool = false) -> void:
	if _shield_active:
		return   # bouclier actif → aucun dégât
	super.take_damage(amount, silent_hurt)


# =============================================================
# MOUVEMENT — charge lente, s'arrête à courte portée
# =============================================================

func _update_movement(_delta: float) -> void:
	var dir  := player.global_position - global_position
	dir.y     = 0.0
	var dist  := dir.length()

	if dist <= stop_distance:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	dir = dir.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
