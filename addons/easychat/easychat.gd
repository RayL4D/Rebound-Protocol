# easychat.gd
extends Node
## EasyChat — Singleton global del addon EasyChat.
## Registrado automáticamente como autoload al activar el plugin.
##
## Uso desde cualquier script:
##   EasyChat.enable()
##   EasyChat.disable()
##   EasyChat.add_message("Servidor", "¡Partida iniciada!")
##   EasyChat.add_system_message("Has sido expulsado de la sesión.")
##   EasyChat.set_player_name("MiNick")
##   EasyChat.message_received.connect(_on_message)

# ── Señales ───────────────────────────────────────────────────────────────────
signal chat_opened
signal chat_closed
signal message_received(sender: String, message: String)

# ── Instancia activa ──────────────────────────────────────────────────────────
var _node: Node = null


# ─── REGISTRO (llamado desde EasyChatNode._ready / _exit_tree) ───────────────
func _register(node: Node) -> void:
	if _node != null and is_instance_valid(_node):
		push_warning(
			"[EasyChat] An EasyChat node is already active in this scene. " +
			"Only one instance is allowed per scene — the new node will be ignored."
		)
		return
	_node = node
	node.chat_opened.connect(func() -> void: chat_opened.emit())
	node.chat_closed.connect(func() -> void: chat_closed.emit())
	node.message_received.connect(
		func(s: String, m: String) -> void: message_received.emit(s, m)
	)

func _unregister(node: Node) -> void:
	if _node == node:
		_node = null


# ─── API PÚBLICA ─────────────────────────────────────────────────────────────

## Activa el chat y lo hace visible.
func enable() -> void:
	if _ok(): _node.enable()

## Desactiva el chat, lo oculta y borra el historial.
func disable() -> void:
	if _ok(): _node.disable()

## Devuelve true si el chat está actualmente abierto (el jugador lo tiene visible).
func is_open() -> bool:
	return _ok() and _node.is_open()

## Devuelve true si el chat está habilitado (visible en escena).
func is_enabled() -> bool:
	return _ok() and _node._is_enabled

## Borra todos los mensajes del historial.
func clear_history() -> void:
	if _ok(): _node.clear_history()

## Inyecta un mensaje de jugador en el historial (aparece como mensaje remoto).
func add_message(sender: String, text: String) -> void:
	if _ok(): _node._add_message(sender, text, false)

## Inyecta un mensaje de sistema en el historial con su estilo propio.
func add_system_message(text: String) -> void:
	if _ok(): _node._add_system_message(text)

## Sobreescribe el nombre del jugador local (solo relevante en modo offline).
func set_player_name(name: String) -> void:
	if _ok(): _node.set_player_name(name)


# ─── INTERNO ─────────────────────────────────────────────────────────────────
func _ok() -> bool:
	return _node != null and is_instance_valid(_node)
