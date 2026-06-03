# chat_command.gd
class_name ChatCommand
extends Resource
## ChatCommand — Recurso reutilizable que representa un comando de chat.
## Guárdalo como .tres y conéctate a su señal "executed" desde cualquier lugar.

signal executed(args: Array)

@export var command_name: String = ""
@export var aliases: PackedStringArray = []
@export var description: String = ""
@export var usage: String = ""
