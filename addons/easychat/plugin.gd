# plugin.gd
@tool
extends EditorPlugin

const AUTOLOAD_NAME := "EasyChat"
const AUTOLOAD_PATH := "res://addons/easychat/easychat.gd"

# _enable_plugin / _disable_plugin gestionan el autoload (se llaman solo al
# activar/desactivar el plugin en Project Settings → Plugins).
func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)

func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)

# _enter_tree / _exit_tree registran el tipo personalizado cada vez que el
# editor arranca con el plugin habilitado (requerido para que aparezca en
# "Agregar nodo" y para que el inspector muestre las propiedades del script).
func _enter_tree() -> void:
	var script := preload("res://addons/easychat/easychat_node.gd")
	var icon   := preload("res://addons/easychat/icon.svg")
	add_custom_type("EasyChat", "Control", script, icon)

func _exit_tree() -> void:
	remove_custom_type("EasyChat")
