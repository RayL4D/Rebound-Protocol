# =============================================================
# HUD.gd — Barre de vie au-dessus du joueur
# =============================================================
# Structure dans hud.tscn (noms EXACTS, respecter la casse) :
#   HUD (CanvasLayer)         ← ce script
#     └── HPContainer (Control)
#           ├── HPBar (ProgressBar)
#           └── HPLabel (Label)
# =============================================================
extends CanvasLayer

@onready var _hp_container: Control     = $HPContainer
@onready var _hp_bar:       ProgressBar = $HPContainer/HPBar
@onready var _hp_label:     Label       = $HPContainer/HPLabel

var _player: Player   = null
var _camera: Camera3D = null

const WORLD_OFFSET := Vector3(0.0, 2.2, 0.0)


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("HUD: joueur introuvable dans le groupe 'player'.")
		return

	_camera = get_viewport().get_camera_3d()

	_hp_bar.max_value = _player.max_hp
	_hp_bar.value     = _player.current_hp
	_update_label(_player.current_hp)

	_player.hp_changed.connect(_on_hp_changed)
	_player.player_died.connect(_on_player_died)


func _process(_delta: float) -> void:
	if _player == null or _camera == null:
		return
	var screen_pos := _camera.unproject_position(_player.global_position + WORLD_OFFSET)
	_hp_container.position = screen_pos - _hp_container.size * 0.5


func _on_hp_changed(new_hp: int) -> void:
	_hp_bar.value = new_hp
	_update_label(new_hp)
	_flash(Color(1.5, 0.2, 0.2))


func _on_player_died() -> void:
	_hp_bar.value    = 0
	_update_label(0)
	_hp_bar.modulate = Color(1.0, 0.2, 0.2)


func _update_label(hp: int) -> void:
	_hp_label.text = "%d / %d" % [hp, _player.max_hp]


func _flash(flash_color: Color) -> void:
	_hp_bar.modulate = flash_color
	var tween := create_tween()
	tween.tween_property(_hp_bar, "modulate", Color.WHITE, 0.35)
