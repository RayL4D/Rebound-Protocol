# =============================================================
# Enemy.gd — Classe de base pour tous les ennemis
# Rebound Protocol
# =============================================================
# Ne pas attacher directement à une scène — utilise PetDog,
# PetMonkey, ou tout autre type qui hérite de cette classe.
#
# Héritage :  Enemy (ici) → PetDog / PetMonkey / PetCat / ...
# Composition : chaque ennemi a un nœud WeaponComponent enfant
#               qui gère la logique de tir indépendamment.
# =============================================================
@tool
class_name Enemy
extends CharacterBody3D

# --- Exports communs à tous les ennemis -------------------------
@export var max_hp: int        = 30
@export var move_speed: float  = 2.0

# Échelle du modèle visuel (pas de la hitbox).
# Référence joueur : capsule radius 0.25 / height 1.8
#   Pet standard → 0.55  (légèrement plus petit que le joueur)
#   Mini-boss    → 1.1   (deux fois plus gros)
#   Boss final   → 1.8+  (imposant)
@export var model_scale: float = 0.55

# Immunité au stomp (mini-boss, boss) — à activer dans les sous-classes
@export var stomp_immune: bool = false

# Offset Y du modèle pour corriger les modèles dont le pivot
# n'est pas centré sur les pieds. Ajuste dans l'inspector
# jusqu'à ce que le pet repose bien sur le sol.
@export var model_y_offset: float = 0.0

# --- Textures (même principe que Player.gd) ----------------------
var _enemy_texture:  Texture2D = preload("res://assets/textures/enemies/colormap.png")
var _weapon_texture: Texture2D = preload("res://assets/textures/weapons/colormap.png")

# --- Audio ------------------------------------------------------
const _SFX_HURT:       AudioStream = preload("res://audio/sfx/enemies/enemy_hurt.wav")
const _SFX_DIE:        AudioStream = preload("res://audio/sfx/enemies/enemy_die.wav")
const _SFX_COIN_SPAWN: AudioStream = preload("res://audio/sfx/enemies/coin_spawn.wav")
var _sfx_player: AudioStreamPlayer = null

# --- État -------------------------------------------------------
var current_hp: int
var player: Player          = null
var _model: Node3D          = null
var _anim_player: AnimationPlayer = null  # trouvé automatiquement dans _setup_model
var _gesture_active: bool = false         # true pendant une animation de geste (bloque idle/walk/run)
var is_dead: bool = false

# Matériaux originaux mémorisés à l'init — restaurés après chaque flash.
# Clé : MeshInstance3D  Valeur : Material original
# Stocké une seule fois pour éviter la race condition (flash qui capture
# un autre flash comme "original" quand plusieurs balles touchent vite).
var _orig_mats: Dictionary = {}

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- SYSTÈME DE SILHOUETTE (X-RAY) -----------------------------
var _highlight_material: ShaderMaterial = null

# --- Signal (compatible avec EnemyPlaceholder) ------------------
signal enemy_died


var _nav_agent: NavigationAgent3D = null
const NAV_UPDATE_INTERVAL := 0.3  # recalcule le chemin toutes les 0.3s
var _nav_timer: float = 0.0

var _stuck_timer: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# En mode éditeur : uniquement le visuel (texture + scale)
	if Engine.is_editor_hint():
		_setup_model()
		return

	current_hp = max_hp
	add_to_group("enemies")
	collision_layer = 16
	collision_mask  = 21   # 5 (géométrie + joueur) | 16 (autres ennemis)
	player = get_tree().get_first_node_in_group("player")
	_setup_model()
	_sfx_player     = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)

	# NavigationAgent3D — ajouté avant _on_ready pour que les sous-classes
	# puissent déjà appeler _get_move_direction() dans leur _on_ready
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance   = 0.5
	_nav_agent.target_desired_distance = 0.5
	_nav_agent.avoidance_enabled       = true
	add_child(_nav_agent)

	# ⚠️ Attendre un frame que la navmesh soit prête avant le 1er calcul
	await get_tree().physics_frame

	if player != null:
		_nav_agent.target_position = player.global_position

	_on_ready()


# =============================================================
# SETUP DU MODÈLE (scale + offset Y + textures)
# =============================================================

func _setup_model() -> void:
	# Trouver le nœud modèle ennemi (premier Node3D enfant hors CollisionShape et WeaponMount)
	for child in get_children():
		if child is Node3D and not child is CollisionShape3D:
			if child.name != "WeaponMount":
				_model = child
				break

	if _model == null:
		push_warning("Enemy: aucun nœud modèle trouvé — scale/texture non appliqués.")
		return

	# Appliquer l'échelle et l'offset Y (pour sortir le modèle du sol)
	_model.scale      = Vector3.ONE * model_scale
	_model.position.y = model_y_offset

	# Appliquer la texture colormap sur le modèle ennemi
	_apply_texture_recursive(_model, _enemy_texture)

	# Appliquer la texture colormap sur l'arme (WeaponMount)
	var weapon_mount := get_node_or_null("WeaponMount")
	if weapon_mount:
		_apply_texture_recursive(weapon_mount, _weapon_texture)

	# Mémoriser les matériaux originaux APRÈS leur application,
	# pour pouvoir les restaurer correctement même si plusieurs flash
	# se chevauchent (race condition).
	# On stocke un Array de matériaux par mesh (une entrée par surface).
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	for mesh in meshes:
		var surface_count := mesh.mesh.get_surface_count() if mesh.mesh else 1
		var mats: Array = []
		for i in surface_count:
			mats.append(mesh.get_surface_override_material(i))
		_orig_mats[mesh] = mats

	# Trouver l'AnimationPlayer dans le GLB importé (recherche récursive)
	_anim_player = _find_anim_player(_model)
	if _anim_player != null:
		_anim_player.play("idle")


# Recherche récursive de l'AnimationPlayer dans la hiérarchie du modèle.
# Les GLB Kenney l'enfouissent plusieurs niveaux sous la racine.
func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found != null:
			return found
	return null


# Même logique que Player.gd : parcourt tous les MeshInstance3D
# de façon récursive et applique la texture sur chacun.
# On itère sur toutes les surfaces pour éviter les erreurs "material is null"
# sur les meshes multi-surfaces (Kenney GLB en ont souvent plusieurs).
func _apply_texture_recursive(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture
		var count := mi.mesh.get_surface_count() if mi.mesh else 1
		for i in count:
			mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_texture_recursive(child, texture)


# Hook surchargeable dans chaque type d'ennemi.
# Sert à initialiser les composants (arme, timer…) qui nécessitent
# que le nœud soit dans l'arbre de scène (@onready déjà résolu).
func _on_ready() -> void:
	pass


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or player == null:
		return

	_apply_gravity(delta)

	# Mise à jour de la cible de navigation
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = NAV_UPDATE_INTERVAL
		_nav_agent.target_position = player.global_position

	_update_movement(delta)
	move_and_slide()
	_face_player()
	_update_animation()


# =============================================================
# MOUVEMENT — à surcharger dans chaque sous-classe
# =============================================================

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


# Surcharge ce méthode pour définir le pattern de déplacement propre
# à chaque type d'ennemi (foncer, orbiter, reculer…).
func _update_movement(_delta: float) -> void:
	pass


# Rotation vers le joueur (horizontal uniquement)
func _face_player() -> void:
	var dir := player.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		rotation.y = atan2(dir.x, dir.z)


# =============================================================
# ANIMATIONS
# =============================================================

# Choisit idle / walk / run en fonction de la vitesse horizontale.
# Appelée chaque frame depuis _physics_process — aucune sous-classe
# n'a besoin de s'en préoccuper, sauf si elle veut surcharger.
func _update_animation() -> void:
	if _anim_player == null:
		return

	# Un geste est en cours (ex : gesture-positive au tir du mortier) — ne pas interrompre
	if _gesture_active:
		return

	# Vitesse horizontale uniquement (Y ignoré)
	var speed := Vector2(velocity.x, velocity.z).length()

	var anim: String
	if speed > move_speed * 0.6:
		anim = "run"
	elif speed > 0.25:
		anim = "walk"
	else:
		anim = "idle"

	# Ne relance l'animation que si elle change pour éviter les redémarrages
	if _anim_player.current_animation != anim:
		_anim_player.play(anim)


# =============================================================
# SANTÉ
# =============================================================

## silent_hurt : passer true pour supprimer le son hurt (ex. stomp/dash — le joueur a son propre son d'impact)
func take_damage(amount: int, silent_hurt: bool = false) -> void:
	# 🛠️ Si l'ennemi est déjà mort ou hors de l'arbre, on ignore complètement
	if is_dead or not is_inside_tree():
		return
		
	current_hp = max(0, current_hp - amount)
	_spawn_damage_number(amount)
	
	if current_hp <= 0:
		is_dead = true # 🛠️ On verrouille immédiatement avant d'appeler _die()
		_die()
		return

	if not silent_hurt and _sfx_player and _SFX_HURT:
		_sfx_player.stream      = _SFX_HURT
		_sfx_player.volume_db   = -8.0 + randf_range(-1.5, 1.5)
		_sfx_player.pitch_scale = randf_range(0.92, 1.08)
		_sfx_player.play()

	# Flash coloré selon l'intensité du coup
	var flash_col: Color
	if amount >= 20:
		flash_col = Color(1.0, 0.4, 0.0)   # orange — gros dégât
	elif amount >= 10:
		flash_col = Color(1.0, 0.85, 0.2)  # jaune — dégât moyen
	else:
		flash_col = Color(1.0, 1.0, 1.0)   # blanc — dégât léger
	_flash_hit(flash_col, 0.12)
	_hit_jolt()


func _spawn_damage_number(amount: int) -> void:
	if not is_inside_tree():
		return

	var node := Node3D.new()
	node.position = global_position + Vector3(randf_range(-0.3, 0.3), 1.5, randf_range(-0.3, 0.3))
	get_tree().current_scene.add_child(node)

	# Couleur selon l'intensité du coup
	var col: Color
	if amount >= 20:
		col = Color(1.0, 0.35, 0.0)   # orange — gros dégât
	elif amount >= 10:
		col = Color(1.0, 0.9, 0.1)    # jaune — dégât normal
	else:
		col = Color(1.0, 1.0, 1.0)    # blanc — dégât faible

	var label := Label3D.new()
	label.text             = str(amount)
	label.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size        = 52 + mini(amount, 20) * 2   # taille dynamique
	label.modulate         = col
	label.outline_size     = 7
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.no_depth_test    = true
	node.add_child(label)

	# Montée
	var tween := node.create_tween()
	tween.tween_property(node, "position:y", node.position.y + 2.2, 1.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(node.queue_free)

	# Disparition
	var fade := node.create_tween()
	fade.tween_interval(0.25)
	fade.tween_property(label, "modulate:a", 0.0, 0.75)


## Nombre de pièces droppées à la mort.
## Surcharge dans les sous-classes (Boss, mini-boss…) pour des drops plus gros.
@export var coin_drop_min: int = 1
@export var coin_drop_max: int = 2

## XP accordée au joueur à la mort de cet ennemi.
## Valeur par défaut = ennemi commun.
## Surcharge dans les sous-classes ou directement dans l'Inspector.
@export var xp_reward: int = 10


func _die() -> void:
	enemy_died.emit()
	if has_node("/root/ScoreManager"):
		ScoreManager.add_kill()
		print("✅ Enemy died - Score updated")
	_drop_coins()
	# Drop XP — seulement si XpManager est présent (pas toujours en menu)
	if get_tree() != null and get_tree().root.has_node("XpManager"):
		XpManager.add_xp(xp_reward)

	# Player flottant pour que le son survive au queue_free de l'ennemi
	if _SFX_DIE != null:
		var p := AudioStreamPlayer.new()
		p.stream      = _SFX_DIE
		p.bus         = "SFX"
		p.volume_db   = -6.0 + randf_range(-1.5, 1.5)
		p.pitch_scale = randf_range(0.90, 1.10)
		get_tree().root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)

	_play_death_sequence()


# Dans Enemy.gd
func _drop_coins() -> void:
	if not is_inside_tree():
		return
		
	# On récupère la valeur totale voulue (ex: 500)
	var total_value := randi_range(coin_drop_min, coin_drop_max)
	# Bonus pièces (upgrade "coin_bonus") : +1 pièce par palier
	if SaveData.active_slot >= 0:
		total_value += int(SaveData.get_upgrade_value("coin_bonus"))

	# Son de spawn des pièces
	if _SFX_COIN_SPAWN != null:
		var p := AudioStreamPlayer.new()
		p.stream      = _SFX_COIN_SPAWN
		p.bus         = "SFX"
		p.volume_db   = 4.0
		p.pitch_scale = randf_range(0.95, 1.05)
		get_tree().root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)

	var parent  := get_tree().current_scene
	
	# On limite le nombre de pièces physiques générées à 10 maximum pour les perfs
	var physical_coins_to_spawn := mini(total_value, 10)
	
	# On répartit la valeur (ex: 500 / 10 = 50 de valeur par pièce visuelle)
	var value_per_coin := int(float(total_value) / physical_coins_to_spawn)
	var remainder := total_value % physical_coins_to_spawn
	
	for i in physical_coins_to_spawn:
		if i > 0:
			await get_tree().create_timer(0.05).timeout
			
		if not is_inside_tree() or not is_instance_valid(parent):
			break
			
		# La première pièce prend le "reste" de la division au cas où ce n'est pas un chiffre rond
		var current_coin_value = value_per_coin
		if i == 0:
			current_coin_value += remainder
			
		# On passe la valeur correcte à ta méthode spawn
		Coin.spawn(parent, global_position, current_coin_value)

func _play_death_sequence() -> void:
	# Désactiver la physique et les collisions pour que le corps ne bloque plus
	set_physics_process(false)
	set_process(false)
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = true

	# Flash orange intense
	_flash_hit(Color(1.0, 0.3, 0.0), 0.18)

	# Burst de particules procédurales
	_spawn_death_burst()

	if _model == null:
		await get_tree().create_timer(0.55).timeout
		queue_free()
		return

	# Tween de mort : squash → spin → rétrécissement
	var orig_scale := _model.scale
	var tw := create_tween()
	tw.set_parallel(false)

	# 1) Choc initial : s'aplatit et s'élargit (0.07s)
	tw.tween_property(_model, "scale",
		Vector3(orig_scale.x * 1.6, orig_scale.y * 0.25, orig_scale.z * 1.6),
		0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2) Rebond élastique + rotation (0.18s) — en parallèle avec la montée
	tw.set_parallel(true)
	tw.tween_property(_model, "scale", orig_scale * 0.85, 0.18) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_model, "rotation:y",
		_model.rotation.y + TAU * 1.5, 0.38) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 3) Contraction vers zéro (0.25s) — séquentiel
	tw.set_parallel(false)
	tw.tween_interval(0.05)
	tw.tween_property(_model, "scale", Vector3.ZERO, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	tw.tween_callback(queue_free)


func _spawn_death_burst() -> void:
	if not is_inside_tree():
		return

	var origin := global_position + Vector3(0.0, 0.6, 0.0)
	var scene_root := get_tree().current_scene

	# 8 éclats en anneau horizontal
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var dir := Vector3(cos(angle), 0.22, sin(angle)).normalized()
		_spawn_burst_particle(scene_root, origin, dir, randf_range(2.0, 3.5),
			Color(1.0, randf_range(0.3, 0.7), 0.0))   # orange à rouge

	# 3 éclats vers le haut
	for i in 3:
		var dir := Vector3(randf_range(-0.4, 0.4), 1.0, randf_range(-0.4, 0.4)).normalized()
		_spawn_burst_particle(scene_root, origin, dir, randf_range(1.5, 2.5),
			Color(1.0, 0.9, 0.2))   # jaune vif


static func _spawn_burst_particle(parent: Node, origin: Vector3,
		direction: Vector3, speed: float, color: Color) -> void:
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius         = 0.055
	sphere_mesh.height         = 0.11
	sphere_mesh.radial_segments = 4
	sphere_mesh.rings          = 2

	var mat := StandardMaterial3D.new()
	mat.albedo_color         = color
	mat.emission_enabled     = true
	mat.emission             = color
	mat.emission_energy_multiplier = 1.8
	mat.no_depth_test        = true

	var mi := MeshInstance3D.new()
	mi.mesh = sphere_mesh
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)       # Doit être dans l'arbre avant d'accéder à global_position
	mi.global_position = origin

	var duration := randf_range(0.35, 0.6)
	var target   := origin + direction * speed

	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position", target, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(
		func(a: float): mat.albedo_color = Color(color.r, color.g, color.b, a),
		1.0, 0.0, duration)
	tw.tween_method(
		func(s: float): mi.scale = Vector3.ONE * s,
		1.0, 0.0, duration)
	tw.tween_callback(mi.queue_free)


# =============================================================
# SOURCES DE DÉGÂTS ALTERNATIVES
# =============================================================

# Appelé par Player quand il atterrit dessus (stomp).
# Anime un écrasement visuel + flash blanc.
func stomp_squish() -> void:
	if _model == null:
		return
	var orig := _model.scale
	# Aplatissement immédiat
	_model.scale = Vector3(orig.x * 1.5, orig.y * 0.15, orig.z * 1.5)
	# Pause pour profiter de l'écrasement, puis retour élastique
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_property(_model, "scale", orig, 0.6) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# Impulsion horizontale (knockback dash-bouclier).
func apply_knockback(direction: Vector3, force: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	velocity.x += direction.normalized().x * force
	velocity.z += direction.normalized().z * force


# Flash coloré rapide sur le modèle.
# color   : couleur du flash (blanc, orange, jaune…)
# duration: durée du flash en secondes
func _flash_hit(color: Color, duration: float) -> void:
	if _model == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	for mesh in meshes:
		# Toujours restaurer vers les matériaux originaux mémorisés à l'init,
		# pas vers les matériaux courants (qui peuvent déjà être un flash précédent).
		var orig_mats: Array = _orig_mats.get(mesh, [])
		var flash    := StandardMaterial3D.new()
		flash.albedo_color               = color
		flash.emission_enabled           = true
		flash.emission                   = color
		flash.emission_energy_multiplier = 1.5
		var surface_count := mesh.mesh.get_surface_count() if mesh.mesh else 1
		for i in surface_count:
			mesh.set_surface_override_material(i, flash)
		var tw := create_tween()
		tw.tween_interval(duration)
		tw.tween_callback(func():
			for i in orig_mats.size():
				mesh.set_surface_override_material(i, orig_mats[i])
		)


# Jolt de scale : micro-impulsion qui donne de l'impact au hit.
func _hit_jolt() -> void:
	if _model == null:
		return
	var orig := _model.scale
	var tw := create_tween()
	tw.set_parallel(false)
	tw.tween_property(_model, "scale", orig * 1.18, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_model, "scale", orig, 0.12) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _get_move_direction() -> Vector3:
	if _nav_agent == null or _nav_agent.is_navigation_finished():
		return Vector3.ZERO

	# Détection de blocage
	_stuck_timer += get_physics_process_delta_time()
	if _stuck_timer >= 0.5:
		_stuck_timer = 0.0
		if global_position.distance_to(_last_position) < 0.05:
			# Impulsion aléatoire pour se débloquer
			var rng := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			return rng.normalized()
		_last_position = global_position

	var next := _nav_agent.get_next_path_position()
	var dir  := (next - global_position)
	dir.y     = 0.0
	return dir.normalized()

## Active ou désactive la silhouette à travers les murs
func toggle_highlight(enabled: bool) -> void:
	if _model == null:
		return

	# On crée le matériau de silhouette au premier appel si besoin
	if enabled and _highlight_material == null:
		var shader := Shader.new()
		shader.code = """
		shader_type spatial;
		render_mode unshaded, depth_test_disabled;
		
		uniform vec4 silhouette_color : source_color = vec4(1.0, 0.35, 0.0, 0.5);
		
		void fragment() {
			ALBEDO = silhouette_color.rgb;
			ALPHA = silhouette_color.a;
		}
		"""
		_highlight_material = ShaderMaterial.new()
		_highlight_material.shader = shader

	# On applique ou on retire le overlay sur tous les sous-meshes de l'ennemi
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	
	for mesh in meshes:
		if enabled:
			mesh.material_overlay = _highlight_material
		else:
			mesh.material_overlay = null
