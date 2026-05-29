# =============================================================
# arena_first_level_2.gd — Scène de la Grotte 
# =============================================================
extends Node3D

@onready var hud: Node = $HUD
@onready var level_exit: Node = $Instant_exit
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

func _ready() -> void:
	_prewarm_bullet_shaders()
	MusicManager.play("gameplay")
	AmbientManager.play("arena")
	TranslationServer.set_locale(SceneManager.current_lang)

	CollisionManager.add_missing_collisions(self)
	_setup_ui()
	_set_permanent_message("LVL2_CAVE_ENTRY")
	call_deferred("_bake_navigation")

	if level_exit and level_exit.has_method("activate"):
		level_exit.activate()

	# Filet de sécurité : restaurer position + HP après TOUS les _ready() de la scène.
	call_deferred("_deferred_restore_player")

func _setup_ui() -> void:
	if not hud:
		push_error("HUD non trouvé dans la grotte !")
		return
	
	var wave_label = hud.find_child("WaveLabel", true, false) as Label
	var enemies_label = hud.find_child("EnemiesLabel", true, false) as Label
	var separator_label = hud.find_child("Separator", true, false) as Label
	
	if wave_label: 
		wave_label.text = ""
	if enemies_label: 
		enemies_label.text = ""
	if separator_label:
		separator_label.text = ""

# --- UTILITAIRES D'AFFICHAGE ---
func _set_permanent_message(translation_key: String) -> void:
	if not hud: return
	
	var message_label = hud.find_child("MessageLabel", true, false) as Label
	var panel = hud.find_child("PanelContainer", true, false) as Control
	if not panel: panel = hud.find_child("Panel", true, false) as Control
	
	if message_label:
		message_label.text = tr(translation_key)
		
	if panel:
		panel.visible = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_set_permanent_message("LVL2_CAVE_ENTRY")


func _bake_navigation() -> void:
	if not is_instance_valid(_nav_region):
		return

	var nav_mesh := _nav_region.navigation_mesh
	nav_mesh.cell_size                        = 0.25
	nav_mesh.cell_height                      = 0.20
	nav_mesh.agent_radius                     = 0.5
	nav_mesh.agent_height                     = 2.0
	nav_mesh.agent_max_climb                  = 0.5
	nav_mesh.agent_max_slope                  = 45.0
	nav_mesh.region_min_size                  = 4.0
	nav_mesh.geometry_parsed_geometry_type    = NavigationMesh.PARSED_GEOMETRY_BOTH
	nav_mesh.geometry_source_geometry_mode    = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

	var source_geo := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_geo, self)
	NavigationServer3D.bake_from_source_geometry_data_async(
		nav_mesh, source_geo,
		Callable(self, "_on_navigation_baked")
	)


func _on_navigation_baked() -> void:
	if is_instance_valid(_nav_region):
		NavigationServer3D.region_set_navigation_mesh(
			_nav_region.get_region_rid(), _nav_region.navigation_mesh
		)
	print("[Level2] Navigation mesh baked.")


func _prewarm_bullet_shaders() -> void:
	const SCENE = preload("res://scenes/projectiles/bullet_enemy.tscn")
	var dummy: Node3D = SCENE.instantiate() as Node3D
	dummy.position = Vector3(0.0, -500.0, 0.0)
	add_child(dummy)
	await get_tree().process_frame
	if is_instance_valid(dummy):
		dummy.queue_free()


func _deferred_restore_player() -> void:
	if SaveData.active_slot < 0:
		return  # Mode co-op ou aucun slot chargé — pas de restauration checkpoint
	var player: Player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	print("[Level2] _deferred_restore_player — appel restore_from_checkpoint()")
	player.restore_from_checkpoint()
