extends CharacterBody3D

@onready var boat_mesh = $"ship-large2"
@onready var enter_hint_label = $inputLabel
@onready var boat_camera = $Camera3D

# --- OPTIONS DE NAVIGATION ---
@export var VITESSE_MAX = 25.0       
@export var ACCELERATION = 8.0      
@export var INERTIE = 3.0           
@export var VITESSE_VIRAGE = 2.0    

var vitesse_actuelle = 0.0
var active_player = false 
var can_interact = false
var saved_player_node = null 

func _ready():
	enter_hint_label.hide()
	if boat_camera: 
		boat_camera.current = false

func _input(event):
	if event.is_action_pressed("interaction") or (event is InputEventKey and event.pressed and event.keycode == KEY_F):
		if can_interact and not active_player:
			enter_boat()
		elif active_player:
			leave_boat()

func enter_boat():
	var player = get_tree().get_first_node_in_group("player")
	if player:
		saved_player_node = player
		active_player = true
		player.hide()
		player.process_mode = Node.PROCESS_MODE_DISABLED 
		enter_hint_label.hide()
		if boat_camera:
			boat_camera.make_current()

func leave_boat():
	if saved_player_node:
		active_player = false
		vitesse_actuelle = 0.0
		saved_player_node.show()
		saved_player_node.process_mode = Node.PROCESS_MODE_INHERIT
		saved_player_node.global_position = global_position + Vector3(4, 2, 0)
		var player_cameras = saved_player_node.find_children("*", "Camera3D")
		if player_cameras.size() > 0:
			player_cameras[0].make_current()

func _physics_process(delta):
	if not active_player:
		if vitesse_actuelle != 0:
			vitesse_actuelle = move_toward(vitesse_actuelle, 0, INERTIE * delta)
			_appliquer_mouvement(delta)
		return

	# DÉTECTION DES TOUCHES
	var avance = Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up")
	var recule = Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down")
	var tourne_gauche = Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left")
	var tourne_droite = Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right")

	# 1. ROTATION
	if tourne_gauche:
		rotate_y(VITESSE_VIRAGE * delta)
	if tourne_droite:
		rotate_y(-VITESSE_VIRAGE * delta)

	# 2. CALCUL DE LA VITESSE
	if avance:
		vitesse_actuelle = move_toward(vitesse_actuelle, VITESSE_MAX, ACCELERATION * delta)
	elif recule:
		vitesse_actuelle = move_toward(vitesse_actuelle, -VITESSE_MAX / 2, ACCELERATION * delta)
	else:
		vitesse_actuelle = move_toward(vitesse_actuelle, 0, INERTIE * delta)

	_appliquer_mouvement(delta)

func _appliquer_mouvement(delta):
	# --- L'INVERSION SE PASSE ICI ---
	# On utilise basis.z sans le signe "-" pour changer le sens de poussée
	var direction = transform.basis.z 
	
	velocity.x = direction.x * vitesse_actuelle
	velocity.z = direction.z * vitesse_actuelle
	
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

	move_and_slide()

# --- SIGNAUX ---
func _on_area_3d_body_entered(body):
	if body.is_in_group("player"):
		can_interact = true
		enter_hint_label.show()

func _on_area_3d_body_exited(body):
	if body.is_in_group("player"):
		can_interact = false
		enter_hint_label.hide()
