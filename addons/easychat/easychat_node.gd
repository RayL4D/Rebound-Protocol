# easychat_node.gd
@tool
@icon("res://addons/easychat/icon.svg")
extends Control
## EasyChatNode — Visual node of the EasyChat addon.
## Add this node to any scene. It registers itself automatically
## with the EasyChat singleton when it enters the scene tree.

# ── Signals ───────────────────────────────────────────────────────────────────
signal chat_opened
signal chat_closed
signal message_received(sender: String, message: String)

# ── Configuration ─────────────────────────────────────────────────────────────
## EasyChatConfig resource holding all appearance, layout, and behavior settings.
## Assign a saved .tres file to share the same config across multiple scenes,
## or leave empty to use default values.
@export var config: EasyChatConfig:
	set(value):
		if config != null and Engine.is_editor_hint():
			if config.changed.is_connected(_refresh_editor):
				config.changed.disconnect(_refresh_editor)
		config = value
		if Engine.is_editor_hint() and is_node_ready():
			_connect_config()
			_rebuild()

# ── Multiplayer ────────────────────────────────────────────────────────────────
@export_group("Multiplayer")
## Enable real-time multiplayer chat via the LinkUx addon.
## Requires LinkUx to be installed and registered as an autoload.
## If enabled without LinkUx present, a descriptive error will be shown at runtime.
@export var multiplayer_enabled: bool = false

# ── Controls ──────────────────────────────────────────────────────────────────
@export_group("Controls")
## Key that opens the chat panel. Shown in the input placeholder text as {key}.
@export var open_key: Key = KEY_T
## Key that closes the chat or dismisses the autocomplete list if it is open.
@export var close_key: Key = KEY_ESCAPE

# ── Preview (editor only) ──────────────────────────────────────────────────────
@export_group("Preview")
## Rebuilds the entire chat UI and reapplies all layout and theme settings.
## Resets preview Show/Hide tweens and restores the default editor look (Preview
## visibility toggles, full opacity, layout offsets). Use after config changes
## or when you want to clear the static end-state left by preview animations.
@export_tool_button("Rebuild Preview", "Reload")
var _btn_rebuild: Callable = _rebuild

@export_subgroup("Visibility")
## Show or hide the message history panel in the editor preview.
@export var preview_history: bool = true:
	set(v):
		preview_history = v
		if Engine.is_editor_hint() and is_instance_valid(_history_panel):
			_history_panel.visible = v
## Show or hide the input row in the editor preview.
@export var preview_input: bool = true:
	set(v):
		preview_input = v
		if Engine.is_editor_hint() and is_instance_valid(_input_row):
			_input_row.visible = v
## Show or hide the autocomplete panel in the editor preview.
## Use "Show Commands" below to populate it with the configured commands.
@export var preview_autocomplete: bool = false:
	set(v):
		preview_autocomplete = v
		if Engine.is_editor_hint() and is_instance_valid(_autocomplete_panel):
			_autocomplete_panel.visible = v
## Show or hide the notification container in the editor preview.
@export var preview_notification: bool = false:
	set(v):
		preview_notification = v
		if Engine.is_editor_hint() and is_instance_valid(_notif_container):
			_notif_container.visible = v

@export_subgroup("Show-Hide Animations")
## Show starts from the same pre-tween state as in-game (chat closed for history;
## dimmed/hidden input per Animations → Input Row). Hide starts from the open chat pose.
## When a tween finishes, that end pose stays until you press Rebuild Preview.
## Plays the same open animation as in-game (Animations → History Panel).
@export_tool_button("History Panel — Show", "Play")
var _btn_prev_hist_show: Callable = _preview_anim_history_show
## Plays the same close animation as in-game (Animations → History Panel).
@export_tool_button("History Panel — Hide", "Stop")
var _btn_prev_hist_hide: Callable = _preview_anim_history_hide
## Plays the same open animation as in-game (Animations → Input Row).
@export_tool_button("Input Row — Show", "Play")
var _btn_prev_input_show: Callable = _preview_anim_input_row_show
## Plays the same close animation as in-game (Animations → Input Row).
@export_tool_button("Input Row — Hide", "Stop")
var _btn_prev_input_hide: Callable = _preview_anim_input_row_hide

@export_subgroup("Messages")
## Adds a sample message sent by the local player to the history panel.
@export_tool_button("Local Message", "Add")
var _btn_prev_local: Callable = _preview_local_msg
## Adds a sample message received from a remote player to the history panel.
@export_tool_button("Remote Message", "Add")
var _btn_prev_remote: Callable = _preview_remote_msg
## Adds a sample system message (e.g. join/leave event) to the history panel.
@export_tool_button("System Message", "Add")
var _btn_prev_system: Callable = _preview_system_msg
## Removes all messages from the history panel.
@export_tool_button("Clear History", "Remove")
var _btn_prev_clear: Callable = _preview_clear_history

@export_subgroup("Notifications")
## Displays a sample regular notification above the input row.
@export_tool_button("Message Notification", "Add")
var _btn_prev_notif: Callable = _preview_notif
## Displays a sample system notification above the input row.
@export_tool_button("System Notification", "Add")
var _btn_prev_sys_notif: Callable = _preview_sys_notif

@export_subgroup("Commands")
## Populates the autocomplete panel with all commands registered in the config.
## Also makes the autocomplete panel visible so you can inspect its appearance.
@export_tool_button("Show Commands", "Search")
var _btn_prev_commands: Callable = _preview_show_commands

# ── Internal nodes ────────────────────────────────────────────────────────────
var _history_panel: PanelContainer
var _scroll: ScrollContainer
var _message_list: VBoxContainer
var _autocomplete_panel: PanelContainer
var _autocomplete_scroll: ScrollContainer
var _suggestion_list: VBoxContainer
var _notif_container: VBoxContainer
var _input_row: HBoxContainer
var _msg_input: LineEdit
var _send_btn: Button
var _audio_player: AudioStreamPlayer

# ── State ─────────────────────────────────────────────────────────────────────
var _is_open: bool = false
var _is_enabled: bool = false
var _local_player_name: String = "Player"
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _anim_tween_history: Tween = null
var _anim_tween_input: Tween = null
var _selected_suggestion: int = -1
var _scroll_pending: bool = false
var _filtered_commands: Array = []
var _linkux: Node = null

const _RPC_NAME   := "easychat_message"
const _RPC_SYSTEM := "easychat_system"

func _is_fade_anim(anim_type: EasyChatConfig.AnimType) -> bool:
	return anim_type == EasyChatConfig.AnimType.FADE \
		or anim_type == EasyChatConfig.AnimType.FADE_UP \
		or anim_type == EasyChatConfig.AnimType.FADE_DOWN \
		or anim_type == EasyChatConfig.AnimType.FADE_LEFT \
		or anim_type == EasyChatConfig.AnimType.FADE_RIGHT


# ─── PRINCIPAL ───────────────────────────────────────────────────────────────
func _ready() -> void:
	# Ensure the node never blocks game input and always fills the viewport
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	if config == null:
		config = EasyChatConfig.new()

	if Engine.is_editor_hint():
		_connect_config()
		_rebuild()
		return

	_create_ui()
	_apply_layout()
	_apply_theme()
	_apply_config_props()

	# Initial state: history hidden, input dimmed or hidden depending on anim type
	_history_panel.visible = false
	_history_panel.modulate.a = 0.0
	_autocomplete_panel.visible = false

	if _is_fade_anim(config.input_anim_type) \
			or config.input_anim_type == EasyChatConfig.AnimType.NONE:
		_input_row.visible = true
		_input_row.modulate.a = config.alpha_input_closed
	else:
		_input_row.visible = false
		_input_row.modulate.a = 1.0

	_send_btn.focus_mode = Control.FOCUS_NONE

	_msg_input.text_submitted.connect(_on_input_submitted)
	_msg_input.text_changed.connect(_on_input_text_changed)
	_msg_input.focus_entered.connect(_open)
	_msg_input.focus_exited.connect(_on_input_focus_exited)
	_send_btn.pressed.connect(_on_send_pressed)

	add_to_group("easychat")

	var api := get_node_or_null("/root/EasyChat")
	if api:
		api._register(self)

	if multiplayer_enabled:
		_setup_multiplayer()
	else:
		_update_visibility()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		if config != null and config.changed.is_connected(_refresh_editor):
			config.changed.disconnect(_refresh_editor)
		return
	var api := get_node_or_null("/root/EasyChat")
	if api:
		api._unregister(self)


# ─── EDITOR PREVIEW ──────────────────────────────────────────────────────────
func _connect_config() -> void:
	if config == null:
		return
	if not config.changed.is_connected(_refresh_editor):
		config.changed.connect(_refresh_editor)

func _rebuild() -> void:
	if Engine.is_editor_hint():
		if _anim_tween_history != null:
			_anim_tween_history.kill()
			_anim_tween_history = null
		if _anim_tween_input != null:
			_anim_tween_input.kill()
			_anim_tween_input = null
	for child in get_children():
		child.free()
	_create_ui()
	_apply_layout()
	_apply_theme()
	_apply_config_props()
	# Default editor look: inspector toggles + neutral layout (same as before
	# preview Show/Hide animations were added).
	_history_panel.visible = preview_history
	_history_panel.modulate.a = 1.0
	_history_panel.scale = Vector2.ONE
	_input_row.visible = preview_input
	_input_row.modulate.a = 1.0
	_input_row.scale = Vector2.ONE
	_autocomplete_panel.visible = preview_autocomplete
	_notif_container.visible = preview_notification

func _refresh_editor() -> void:
	if not Engine.is_editor_hint():
		return
	if _history_panel == null:
		_rebuild()
		return
	_apply_layout()
	_apply_theme()
	_apply_config_props()


# ─── MULTIPLAYER ──────────────────────────────────────────────────────────────
func _setup_multiplayer() -> void:
	_linkux = get_node_or_null("/root/LinkUx")
	if _linkux == null:
		push_error(
			"[EasyChat] 'multiplayer_enabled' is enabled but LinkUx is not available. " +
			"Install the LinkUx addon and register it as an autoload to use " +
			"real-time multiplayer chat."
		)
		_update_visibility()
		return

	_linkux.session_started.connect(_on_session_started)
	_linkux.session_closed.connect(_on_session_closed)
	_update_local_player_name()
	_update_visibility()

	if _linkux.is_in_session():
		_register_rpc()

func _register_rpc() -> void:
	if _linkux == null:
		return
	_linkux.register_rpc(_RPC_NAME,   Callable(self, "_on_chat_rpc"))
	_linkux.register_rpc(_RPC_SYSTEM, Callable(self, "_on_system_rpc"))

func _on_session_started() -> void:
	_register_rpc()
	_update_local_player_name()
	_update_visibility()

func _on_session_closed() -> void:
	if _is_open:
		_force_close()
	_update_visibility()

func _update_visibility() -> void:
	visible = _is_enabled

func _update_local_player_name() -> void:
	if _linkux == null or not multiplayer_enabled:
		return
	var name: String = _linkux.get_local_player_name()
	if not name.is_empty():
		_local_player_name = name

func _get_sender_name() -> String:
	_update_local_player_name()
	return _local_player_name


# ─── PUBLIC API ───────────────────────────────────────────────────────────────
func is_open() -> bool:
	return _is_open

func enable() -> void:
	_is_enabled = true
	_update_visibility()

func disable() -> void:
	if _is_open:
		_force_close()
	clear_history()
	_is_enabled = false
	visible = false

func clear_history() -> void:
	for child in _message_list.get_children():
		child.queue_free()

func set_player_name(name: String) -> void:
	_local_player_name = name


# ─── INPUT ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _is_enabled:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	var key := (event as InputEventKey).keycode

	if _is_open and _autocomplete_panel.visible:
		match key:
			KEY_UP:
				_navigate_suggestions(-1)
				get_viewport().set_input_as_handled()
				return
			KEY_DOWN:
				_navigate_suggestions(1)
				get_viewport().set_input_as_handled()
				return
			KEY_TAB:
				_apply_suggestion()
				get_viewport().set_input_as_handled()
				return

	if key == close_key and _is_open:
		if _autocomplete_panel.visible:
			_autocomplete_panel.visible = false
			_selected_suggestion = -1
		else:
			_close()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_enabled:
		return
	if not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.keycode == open_key and not _is_open:
		_open()


# ─── OPEN / CLOSE ─────────────────────────────────────────────────────────────
func _open() -> void:
	if _is_open:
		return
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for action in InputMap.get_actions():
		Input.action_release(action)
	# Dismiss all stacked notifications when the chat opens
	for _nc in _notif_container.get_children():
		_nc.queue_free()
	_play_sound(config.sound_chat_opened)

	# History panel animation
	if _anim_tween_history:
		_anim_tween_history.kill()
	_anim_tween_history = _anim_element_show(
		_history_panel,
		config.history_anim_type,
		config.history_anim_duration,
		config.history_slide_distance
	)

	# Input row animation — for FADE, start from alpha_input_closed; otherwise start from 0
	if _anim_tween_input:
		_anim_tween_input.kill()
	var input_from := config.alpha_input_closed if _is_fade_anim(config.input_anim_type) else 0.0
	_anim_tween_input = _anim_element_show(
		_input_row,
		config.input_anim_type,
		config.input_anim_duration,
		config.input_slide_distance,
		input_from
	)

	_scroll_to_bottom()
	call_deferred("_focus_input")
	chat_opened.emit()

func _close() -> void:
	if not _is_open:
		return
	_is_open = false
	_autocomplete_panel.visible = false
	_selected_suggestion = -1
	_msg_input.release_focus()
	_play_sound(config.sound_chat_closed)

	# History panel animation
	if _anim_tween_history:
		_anim_tween_history.kill()
	_anim_tween_history = _anim_element_hide(
		_history_panel,
		config.history_anim_type,
		config.history_anim_duration,
		config.history_slide_distance
	)

	# Input row animation — for FADE, keep dim; for others hide fully
	if _anim_tween_input:
		_anim_tween_input.kill()
	var input_end := config.alpha_input_closed if _is_fade_anim(config.input_anim_type) else 0.0
	_anim_tween_input = _anim_element_hide(
		_input_row,
		config.input_anim_type,
		config.input_anim_duration,
		config.input_slide_distance,
		input_end
	)

	Input.mouse_mode = _prev_mouse_mode
	chat_closed.emit()

func _force_close() -> void:
	_is_open = false
	if _anim_tween_history:
		_anim_tween_history.kill()
		_anim_tween_history = null
	if _anim_tween_input:
		_anim_tween_input.kill()
		_anim_tween_input = null
	# Restore layout offsets in case a slide animation was killed mid-way.
	_apply_layout()
	_history_panel.visible = false
	_history_panel.modulate.a = 0.0
	_autocomplete_panel.visible = false
	_selected_suggestion = -1
	# Reset input row to its closed-state appearance.
	if _is_fade_anim(config.input_anim_type) \
			or config.input_anim_type == EasyChatConfig.AnimType.NONE:
		_input_row.visible = true
		_input_row.modulate.a = config.alpha_input_closed
	else:
		_input_row.visible = false
		_input_row.modulate.a = 1.0
	_msg_input.release_focus()
	Input.mouse_mode = _prev_mouse_mode
	chat_closed.emit()

func _focus_input() -> void:
	if _is_open:
		_msg_input.grab_focus()

func _on_input_focus_exited() -> void:
	# If the chat is still open, immediately return focus to the input so the
	# player never has to click the field again after an accidental focus loss.
	# _close() / _force_close() set _is_open = false before release_focus(), so
	# this handler is a no-op during a normal close.
	if _is_open:
		call_deferred("_focus_input")


# ─── ANIMATION HELPERS ────────────────────────────────────────────────────────
## Shows [node] using the given animation style.
## [from_alpha] is the starting opacity for FADE (default 0.0).
## [slide_dist] is the pixel offset for slide animations.
func _anim_element_show(
	node: Control,
	anim_type: EasyChatConfig.AnimType,
	duration: float,
	slide_dist: float,
	from_alpha: float = 0.0
) -> Tween:
	# IMPORTANT: never assign node.position on anchored Controls (layout_mode=1).
	# On those nodes, position is derived from anchors + offsets; assigning it
	# rewrites offset_top/left and breaks the layout. Slide animations must
	# manipulate the offset_* properties directly instead.
	node.visible = true
	var t: Tween = null
	match anim_type:
		EasyChatConfig.AnimType.NONE:
			node.modulate.a = 1.0
		EasyChatConfig.AnimType.FADE:
			node.modulate.a = from_alpha
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", 1.0, duration)
		EasyChatConfig.AnimType.FADE_UP:
			node.modulate.a = from_alpha
			var ot := node.offset_top;    var ob := node.offset_bottom
			node.offset_top = ot + slide_dist;  node.offset_bottom = ob + slide_dist
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", 1.0, duration)
			t.parallel().tween_property(node, "offset_top",    ot, duration)
			t.parallel().tween_property(node, "offset_bottom", ob, duration)
		EasyChatConfig.AnimType.FADE_DOWN:
			node.modulate.a = from_alpha
			var otd := node.offset_top;    var obd := node.offset_bottom
			node.offset_top = otd - slide_dist;  node.offset_bottom = obd - slide_dist
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", 1.0, duration)
			t.parallel().tween_property(node, "offset_top",    otd, duration)
			t.parallel().tween_property(node, "offset_bottom", obd, duration)
		EasyChatConfig.AnimType.FADE_LEFT:
			node.modulate.a = from_alpha
			var ol := node.offset_left;   var or_ := node.offset_right
			node.offset_left = ol - slide_dist;  node.offset_right = or_ - slide_dist
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", 1.0, duration)
			t.parallel().tween_property(node, "offset_left",  ol,  duration)
			t.parallel().tween_property(node, "offset_right", or_, duration)
		EasyChatConfig.AnimType.FADE_RIGHT:
			node.modulate.a = from_alpha
			var olr := node.offset_left;   var orr := node.offset_right
			node.offset_left = olr + slide_dist;  node.offset_right = orr + slide_dist
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", 1.0, duration)
			t.parallel().tween_property(node, "offset_left",  olr, duration)
			t.parallel().tween_property(node, "offset_right", orr, duration)
		EasyChatConfig.AnimType.SLIDE_UP:
			# Enter from below: push both vertical offsets down, tween back to original.
			node.modulate.a = 1.0
			var ot := node.offset_top;    var ob := node.offset_bottom
			node.offset_top = ot + slide_dist;  node.offset_bottom = ob + slide_dist
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "offset_top",    ot, duration)
			t.parallel().tween_property(node, "offset_bottom", ob, duration)
		EasyChatConfig.AnimType.SLIDE_DOWN:
			# Enter from above: push both vertical offsets up, tween back to original.
			node.modulate.a = 1.0
			var ot := node.offset_top;    var ob := node.offset_bottom
			node.offset_top = ot - slide_dist;  node.offset_bottom = ob - slide_dist
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "offset_top",    ot, duration)
			t.parallel().tween_property(node, "offset_bottom", ob, duration)
		EasyChatConfig.AnimType.SLIDE_LEFT:
			# Enter from the left: push both horizontal offsets left, tween back to original.
			node.modulate.a = 1.0
			var ol := node.offset_left;   var or_ := node.offset_right
			node.offset_left = ol - slide_dist;  node.offset_right = or_ - slide_dist
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "offset_left",  ol,  duration)
			t.parallel().tween_property(node, "offset_right", or_, duration)
		EasyChatConfig.AnimType.SLIDE_RIGHT:
			# Enter from the right: push both horizontal offsets right, tween back to original.
			node.modulate.a = 1.0
			var ol := node.offset_left;   var or_ := node.offset_right
			node.offset_left = ol + slide_dist;  node.offset_right = or_ + slide_dist
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "offset_left",  ol,  duration)
			t.parallel().tween_property(node, "offset_right", or_, duration)
		EasyChatConfig.AnimType.SCALE:
			node.modulate.a = 1.0
			var pivot_y := node.size.y if node.size.y > 1.0 else slide_dist
			node.pivot_offset = Vector2(node.size.x * 0.5, pivot_y)
			node.scale = Vector2(1.0, 0.001)
			t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(node, "scale:y", 1.0, duration)
	return t

## Hides [node] using the given animation style.
## [end_alpha] is the target opacity (default 0.0 = fully hidden).
## When [end_alpha] is 0.0 the node is also set to invisible after the animation.
func _anim_element_hide(
	node: Control,
	anim_type: EasyChatConfig.AnimType,
	duration: float,
	slide_dist: float,
	end_alpha: float = 0.0
) -> Tween:
	var hide_after := end_alpha <= 0.0
	var t: Tween = null
	match anim_type:
		EasyChatConfig.AnimType.NONE:
			node.modulate.a = end_alpha
			if hide_after:
				node.visible = false
		EasyChatConfig.AnimType.FADE:
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", end_alpha, duration)
			if hide_after:
				t.tween_callback(func() -> void:
					if not _is_open:
						node.visible = false
				)
		EasyChatConfig.AnimType.FADE_UP:
			var otfu := node.offset_top;    var obfu := node.offset_bottom
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", end_alpha, duration)
			t.parallel().tween_property(node, "offset_top",    otfu + slide_dist, duration)
			t.parallel().tween_property(node, "offset_bottom", obfu + slide_dist, duration)
			t.tween_callback(func() -> void:
				if not _is_open:
					if hide_after:
						node.visible = false
					node.offset_top = otfu;  node.offset_bottom = obfu
			)
		EasyChatConfig.AnimType.FADE_DOWN:
			var otfd := node.offset_top;    var obfd := node.offset_bottom
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", end_alpha, duration)
			t.parallel().tween_property(node, "offset_top",    otfd - slide_dist, duration)
			t.parallel().tween_property(node, "offset_bottom", obfd - slide_dist, duration)
			t.tween_callback(func() -> void:
				if not _is_open:
					if hide_after:
						node.visible = false
					node.offset_top = otfd;  node.offset_bottom = obfd
			)
		EasyChatConfig.AnimType.FADE_LEFT:
			var olfl := node.offset_left;   var orfl := node.offset_right
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", end_alpha, duration)
			t.parallel().tween_property(node, "offset_left",  olfl - slide_dist, duration)
			t.parallel().tween_property(node, "offset_right", orfl - slide_dist, duration)
			t.tween_callback(func() -> void:
				if not _is_open:
					if hide_after:
						node.visible = false
					node.offset_left = olfl;  node.offset_right = orfl
			)
		EasyChatConfig.AnimType.FADE_RIGHT:
			var olfr := node.offset_left;   var orfr := node.offset_right
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "modulate:a", end_alpha, duration)
			t.parallel().tween_property(node, "offset_left",  olfr + slide_dist, duration)
			t.parallel().tween_property(node, "offset_right", orfr + slide_dist, duration)
			t.tween_callback(func() -> void:
				if not _is_open:
					if hide_after:
						node.visible = false
					node.offset_left = olfr;  node.offset_right = orfr
			)
		EasyChatConfig.AnimType.SLIDE_UP:
			# Exit downward; restore original offsets in the callback.
			var ot := node.offset_top;    var ob := node.offset_bottom
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "offset_top",    ot + slide_dist, duration)
			t.parallel().tween_property(node, "offset_bottom", ob + slide_dist, duration)
			t.tween_callback(func() -> void:
				if not _is_open:
					node.visible = false
					node.offset_top = ot;  node.offset_bottom = ob
			)
		EasyChatConfig.AnimType.SLIDE_DOWN:
			# Exit upward; restore original offsets in the callback.
			var ot := node.offset_top;    var ob := node.offset_bottom
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "offset_top",    ot - slide_dist, duration)
			t.parallel().tween_property(node, "offset_bottom", ob - slide_dist, duration)
			t.tween_callback(func() -> void:
				if not _is_open:
					node.visible = false
					node.offset_top = ot;  node.offset_bottom = ob
			)
		EasyChatConfig.AnimType.SLIDE_LEFT:
			# Exit to the left; restore original offsets in the callback.
			var ol := node.offset_left;   var or_ := node.offset_right
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "offset_left",  ol  - slide_dist, duration)
			t.parallel().tween_property(node, "offset_right", or_ - slide_dist, duration)
			t.tween_callback(func() -> void:
				if not _is_open:
					node.visible = false
					node.offset_left = ol;  node.offset_right = or_
			)
		EasyChatConfig.AnimType.SLIDE_RIGHT:
			# Exit to the right; restore original offsets in the callback.
			var ol := node.offset_left;   var or_ := node.offset_right
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "offset_left",  ol  + slide_dist, duration)
			t.parallel().tween_property(node, "offset_right", or_ + slide_dist, duration)
			t.tween_callback(func() -> void:
				if not _is_open:
					node.visible = false
					node.offset_left = ol;  node.offset_right = or_
			)
		EasyChatConfig.AnimType.SCALE:
			t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(node, "scale:y", 0.001, duration)
			t.tween_callback(func() -> void:
				if not _is_open:
					node.visible = false
					node.scale = Vector2.ONE
			)
	return t


# ─── MESSAGES AND COMMANDS ────────────────────────────────────────────────────
func _on_send_pressed() -> void:
	_on_input_submitted(_msg_input.text)

func _on_input_submitted(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	_msg_input.clear()
	_autocomplete_panel.visible = false
	_selected_suggestion = -1

	if text.begins_with("/"):
		_execute_command(text)
		if config.close_on_send:
			_close()
		else:
			# Godot 4 releases LineEdit focus after text_submitted; restore it.
			_msg_input.grab_focus()
		return

	var sender := _get_sender_name()

	# ─── MULTIJOUEUR NATIF GODOT (SANS LINKUX) ───
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_rpc_send_chat_message.rpc(sender, text)

	_add_message(sender, text, true)

	if config.close_on_send:
		# Show the sent message in the notification overlay before closing
		var formatted := config.message_format \
			.replace("{sender}", sender) \
			.replace("{message}", text)
		_show_notification(formatted)
		_close()
	else:
		# Godot 4 releases LineEdit focus after text_submitted; restore it.
		_msg_input.grab_focus()

func _execute_command(text: String) -> void:
	var parts := text.substr(1).split(" ", false)
	if parts.is_empty():
		return

	var cmd_name := parts[0].to_lower()
	var args: Array = Array(parts.slice(1)) if parts.size() > 1 else []

	for cmd in config.commands:
		var c := cmd as ChatCommand
		if c == null:
			continue
		if c.command_name.to_lower() == cmd_name:
			c.executed.emit(args)
			return
		for alias: String in c.aliases:
			if alias.to_lower() == cmd_name:
				c.executed.emit(args)
				return

	_add_system_message("Unknown command: /%s" % cmd_name, false)

func _on_chat_rpc(from_peer: int, sender: String, message: String) -> void:
	_add_message(sender, message, false)
	# ENet uses star topology: clients connect only to the host, not to each other.
	# A client's broadcast_rpc therefore reaches the host only. The host must relay
	# the message to every other connected peer so all clients see it.
	# The original sender is excluded — it already displayed the message locally.
	if multiplayer_enabled and _linkux != null and _linkux.is_host():
		for peer_id: int in _linkux.get_connected_peers():
			if peer_id != from_peer:
				_linkux.send_rpc(peer_id, _RPC_NAME, [sender, message])

func _on_system_rpc(from_peer: int, text: String) -> void:
	# Received from another peer — display locally without re-broadcasting.
	_add_system_message(text, false)
	# Same relay logic as chat messages: host forwards to all other clients.
	if multiplayer_enabled and _linkux != null and _linkux.is_host():
		for peer_id: int in _linkux.get_connected_peers():
			if peer_id != from_peer:
				_linkux.send_rpc(peer_id, _RPC_SYSTEM, [text])

func _add_message(sender: String, message: String, is_local: bool) -> void:
	_trim_history_if_needed()

	var formatted := config.message_format \
		.replace("{sender}", sender) \
		.replace("{message}", message)
	var label := Label.new()
	label.text = formatted
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color",
		config.local_message_color if is_local else config.remote_message_color)
	_apply_font_theme(label, config.message_font, config.message_font_size)
	_append_history_label(label)

	if _is_open:
		_scroll_to_bottom()
	else:
		_show_notification(formatted)

	if is_local:
		_play_sound(config.sound_message_sent)
	else:
		_play_sound(config.sound_message_received)

	message_received.emit(sender, message)

## Adds a system message to the history.
## [broadcast] — when true and multiplayer is active, the message is sent to all other peers
## so it appears in everyone's chat. Set to false for local-only feedback (e.g. command errors).
func _add_system_message(text: String, broadcast: bool = true) -> void:
	_trim_history_if_needed()

	var label := Label.new()
	label.text = config.system_message_prefix + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", config.system_message_color)
	_apply_font_theme(label, config.message_font, config.message_font_size)
	_append_history_label(label)

	# Broadcast to other players when requested and session is active.
	if broadcast and multiplayer_enabled and _linkux != null and _linkux.is_in_session():
		_linkux.broadcast_rpc(_RPC_SYSTEM, [text], false)

	_play_sound(config.sound_system_message)

	# Notification overlay: only shown when the chat is closed — if open the
	# message is already visible in the history right in front of the player.
	if not _is_open:
		_show_notification(config.system_message_prefix + text)

	if _is_open:
		_scroll_to_bottom()


func _trim_history_if_needed() -> void:
	if _message_list.get_child_count() >= config.max_messages:
		var _old := _message_list.get_child(0)
		_message_list.remove_child(_old)
		_old.queue_free()


func _append_history_label(label: Label) -> void:
	var anim := config.message_anim_type
	var dur := config.message_anim_duration
	if anim == EasyChatConfig.AnimType.NONE or dur <= 0.0:
		_message_list.add_child(label)
		return

	var wrap := Control.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match anim:
		EasyChatConfig.AnimType.SLIDE_LEFT, EasyChatConfig.AnimType.SLIDE_RIGHT, \
		EasyChatConfig.AnimType.SLIDE_UP, EasyChatConfig.AnimType.SLIDE_DOWN:
			wrap.clip_children = Control.CLIP_CHILDREN_ONLY
		_:
			wrap.clip_children = Control.CLIP_CHILDREN_DISABLED

	# Manual layout inside [wrap] so SLIDE/SCALE do not fight the outer VBoxContainer.
	label.layout_mode = 0
	label.position = Vector2.ZERO
	# Avoid a one-frame zero-height row before [_history_message_anim_start] measures the label.
	wrap.custom_minimum_size.y = maxf(label.get_line_height(), 1.0)
	wrap.add_child(label)
	_message_list.add_child(wrap)
	call_deferred("_history_message_anim_start", wrap, label, anim, dur)


func _history_message_anim_start(wrap: Control, label: Label, anim: EasyChatConfig.AnimType, dur: float) -> void:
	await get_tree().process_frame
	if not is_instance_valid(wrap) or not is_instance_valid(label) or label.get_parent() != wrap:
		return

	var pw: float = wrap.size.x
	if pw < 4.0:
		await get_tree().process_frame
		if not is_instance_valid(wrap) or not is_instance_valid(label):
			return
		pw = wrap.size.x
	if pw < 4.0:
		wrap.modulate.a = 1.0
		label.position = Vector2.ZERO
		return

	label.size = Vector2(pw, 0)
	var min_sz := label.get_minimum_size()
	label.size.y = maxf(min_sz.y, label.get_line_height())
	wrap.custom_minimum_size.y = label.size.y

	var dist: float = maxf(config.message_slide_distance, 1.0)

	if _is_open:
		_scroll_to_bottom()

	match anim:
		EasyChatConfig.AnimType.FADE:
			wrap.modulate.a = 0.0
			var tf := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tf.tween_property(wrap, "modulate:a", 1.0, dur)
		EasyChatConfig.AnimType.FADE_UP:
			wrap.modulate.a = 0.0
			label.position = Vector2(0.0, dist)
			var tfu := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tfu.tween_property(wrap, "modulate:a", 1.0, dur)
			tfu.parallel().tween_property(label, "position:y", 0.0, dur)
		EasyChatConfig.AnimType.FADE_DOWN:
			wrap.modulate.a = 0.0
			label.position = Vector2(0.0, -dist)
			var tfd := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tfd.tween_property(wrap, "modulate:a", 1.0, dur)
			tfd.parallel().tween_property(label, "position:y", 0.0, dur)
		EasyChatConfig.AnimType.FADE_LEFT:
			wrap.modulate.a = 0.0
			label.position = Vector2(-dist, 0.0)
			var tfl := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tfl.tween_property(wrap, "modulate:a", 1.0, dur)
			tfl.parallel().tween_property(label, "position:x", 0.0, dur)
		EasyChatConfig.AnimType.FADE_RIGHT:
			wrap.modulate.a = 0.0
			label.position = Vector2(dist, 0.0)
			var tfr := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tfr.tween_property(wrap, "modulate:a", 1.0, dur)
			tfr.parallel().tween_property(label, "position:x", 0.0, dur)
		EasyChatConfig.AnimType.SLIDE_UP:
			label.position = Vector2(0.0, dist)
			var tu := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tu.tween_property(label, "position:y", 0.0, dur)
		EasyChatConfig.AnimType.SLIDE_DOWN:
			label.position = Vector2(0.0, -dist)
			var td := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			td.tween_property(label, "position:y", 0.0, dur)
		EasyChatConfig.AnimType.SLIDE_LEFT:
			label.position = Vector2(-dist, 0.0)
			var tl := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tl.tween_property(label, "position:x", 0.0, dur)
		EasyChatConfig.AnimType.SLIDE_RIGHT:
			label.position = Vector2(dist, 0.0)
			var tr := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tr.tween_property(label, "position:x", 0.0, dur)
		EasyChatConfig.AnimType.SCALE:
			label.pivot_offset = Vector2(pw * 0.5, label.size.y)
			label.scale = Vector2(1.0, 0.001)
			var ts := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			ts.tween_property(label, "scale:y", 1.0, dur)
		_:
			wrap.modulate.a = 1.0


func _scroll_to_bottom() -> void:
	# Guard: if a scroll is already scheduled for this frame, skip spawning another
	# coroutine. Without this, N rapid messages create N simultaneous coroutines that
	# all resume and contend on the same ScrollContainer next frame.
	if _scroll_pending:
		return
	_scroll_pending = true
	await get_tree().process_frame
	_scroll_pending = false
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


# ─── AUTOCOMPLETE ─────────────────────────────────────────────────────────────
func _on_input_text_changed(new_text: String) -> void:
	if not _is_open:
		return
	if new_text.begins_with("/"):
		var partial := new_text.substr(1).split(" ")[0].to_lower()
		_update_autocomplete(partial)
	else:
		_autocomplete_panel.visible = false
		_selected_suggestion = -1

func _update_autocomplete(partial: String) -> void:
	_filtered_commands.clear()
	for cmd in config.commands:
		var c := cmd as ChatCommand
		if c == null:
			continue
		if c.command_name.to_lower().begins_with(partial):
			_filtered_commands.append(c)
			continue
		for alias: String in c.aliases:
			if alias.to_lower().begins_with(partial):
				_filtered_commands.append(c)
				break

	for child in _suggestion_list.get_children():
		child.queue_free()

	for i: int in _filtered_commands.size():
		_build_suggestion_item(_filtered_commands[i] as ChatCommand, i)

	_selected_suggestion = -1

	var visible_count := mini(_filtered_commands.size(), config.max_suggestions_visible)
	var panel_h := visible_count * config.suggestion_item_height + 6.0
	var input_top := -(config.panel_margin_bottom + config.input_height)
	_autocomplete_panel.offset_bottom = input_top
	_autocomplete_panel.offset_top = input_top - panel_h

	_autocomplete_panel.visible = not _filtered_commands.is_empty()

func _build_suggestion_item(cmd: ChatCommand, index: int) -> void:
	var item := PanelContainer.new()
	item.custom_minimum_size = Vector2(0.0, config.suggestion_item_height)
	item.mouse_filter = Control.MOUSE_FILTER_STOP
	item.add_theme_stylebox_override("panel", _make_item_style(false))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	var cmd_label := Label.new()
	cmd_label.text = "/%s" % cmd.command_name
	cmd_label.add_theme_color_override("font_color", config.autocomplete_command_color)
	cmd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font_theme(cmd_label, config.autocomplete_font, config.autocomplete_font_size)

	var desc_label := Label.new()
	desc_label.text = cmd.description
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_color_override("font_color", config.autocomplete_desc_color)
	desc_label.clip_text = true
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font_theme(desc_label, config.autocomplete_font, config.autocomplete_font_size)

	hbox.add_child(cmd_label)
	hbox.add_child(desc_label)
	item.add_child(hbox)

	item.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_suggestion_clicked(index)
	)
	item.mouse_entered.connect(func() -> void:
		_selected_suggestion = index
		_highlight_suggestion(index)
	)

	_suggestion_list.add_child(item)

func _make_item_style(selected: bool) -> StyleBox:
	if selected:
		return config.autocomplete_selected_style if config.autocomplete_selected_style != null \
			else _default_autocomplete_selected_style()
	else:
		return config.autocomplete_item_style if config.autocomplete_item_style != null \
			else _default_autocomplete_item_style()

func _navigate_suggestions(direction: int) -> void:
	if _filtered_commands.is_empty():
		return
	_selected_suggestion = wrapi(_selected_suggestion + direction, 0, _filtered_commands.size())
	_highlight_suggestion(_selected_suggestion)

func _highlight_suggestion(index: int) -> void:
	for i: int in _suggestion_list.get_child_count():
		var item := _suggestion_list.get_child(i) as PanelContainer
		if item == null:
			continue
		item.add_theme_stylebox_override("panel", _make_item_style(i == index))

func _apply_suggestion() -> void:
	if _filtered_commands.is_empty():
		return
	if _selected_suggestion < 0:
		_selected_suggestion = 0
	_on_suggestion_clicked(_selected_suggestion)

func _on_suggestion_clicked(index: int) -> void:
	if index < 0 or index >= _filtered_commands.size():
		return
	var cmd := _filtered_commands[index] as ChatCommand
	if cmd == null:
		return
	_msg_input.text = "/%s " % cmd.command_name
	_msg_input.caret_column = _msg_input.text.length()
	_autocomplete_panel.visible = false
	_selected_suggestion = -1
	_msg_input.grab_focus()


# ─── NOTIFICATION ─────────────────────────────────────────────────────────────
func _show_notification(text: String) -> void:
	# Enforce max stack: remove_child first so get_child_count() decrements immediately.
	# Using queue_free alone defers the deletion — the count stays unchanged and the
	# while loop would spin forever once the stack is full (guaranteed crash/hang).
	while _notif_container.get_child_count() >= config.max_notifications:
		var _old := _notif_container.get_child(0)
		_notif_container.remove_child(_old)
		_old.queue_free()

	# Build the entry panel (starts invisible; _animate_notification_entry reveals it).
	var entry := PanelContainer.new()
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.modulate.a = 0.0
	entry.add_theme_stylebox_override("panel", _make_notification_style())

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_color", config.notification_color)
	_apply_font_theme(lbl, config.notification_font, config.notification_font_size)
	entry.add_child(lbl)
	_notif_container.add_child(entry)

	_animate_notification_entry(entry)

## Animates a notification entry in using the configured style, then fades it out
## and frees it. Async: awaits one frame for positional animations so the
## VBoxContainer can finish laying out the entry before its size/position is read.
func _animate_notification_entry(entry: PanelContainer) -> void:
	var anim_type := config.notification_anim_type
	var dur_in    := config.notification_anim_duration
	var slide_dist := maxf(config.notification_slide_distance, 1.0)

	# Positional animations (SLIDE_*, SCALE) need the entry to be laid out first
	# so that entry.size and entry.position contain real values.
	match anim_type:
		EasyChatConfig.AnimType.SLIDE_LEFT, \
		EasyChatConfig.AnimType.SLIDE_RIGHT, \
		EasyChatConfig.AnimType.SLIDE_UP, \
		EasyChatConfig.AnimType.SLIDE_DOWN, \
		EasyChatConfig.AnimType.SCALE:
			await get_tree().process_frame
			if not is_instance_valid(entry):
				return

	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	match anim_type:
		EasyChatConfig.AnimType.NONE:
			# Instant appear — skip to the hold + fade-out phase.
			entry.modulate.a = config.notification_alpha
			var t2 := create_tween()
			t2.tween_interval(config.notification_duration)
			t2.tween_property(entry, "modulate:a", 0.0, 0.4)
			t2.tween_callback(func() -> void:
				if is_instance_valid(entry): entry.queue_free()
			)
			return

		EasyChatConfig.AnimType.FADE:
			t.tween_property(entry, "modulate:a", config.notification_alpha, dur_in)
		EasyChatConfig.AnimType.FADE_LEFT:
			entry.modulate.a = 0.0
			var sxf_l := entry.position.x
			entry.position.x = sxf_l - slide_dist
			t.tween_property(entry, "modulate:a", config.notification_alpha, dur_in)
			t.parallel().tween_property(entry, "position:x", sxf_l, dur_in)
		EasyChatConfig.AnimType.FADE_RIGHT:
			entry.modulate.a = 0.0
			var sxf_r := entry.position.x
			entry.position.x = sxf_r + slide_dist
			t.tween_property(entry, "modulate:a", config.notification_alpha, dur_in)
			t.parallel().tween_property(entry, "position:x", sxf_r, dur_in)
		EasyChatConfig.AnimType.FADE_UP:
			entry.modulate.a = 0.0
			var syf_u := entry.position.y
			entry.position.y = syf_u + slide_dist
			t.tween_property(entry, "modulate:a", config.notification_alpha, dur_in)
			t.parallel().tween_property(entry, "position:y", syf_u, dur_in)
		EasyChatConfig.AnimType.FADE_DOWN:
			entry.modulate.a = 0.0
			var syf_d := entry.position.y
			entry.position.y = syf_d - slide_dist
			t.tween_property(entry, "modulate:a", config.notification_alpha, dur_in)
			t.parallel().tween_property(entry, "position:y", syf_d, dur_in)

		EasyChatConfig.AnimType.SLIDE_LEFT:
			entry.modulate.a = config.notification_alpha
			var sx := entry.position.x
			entry.position.x = sx - slide_dist
			t.tween_property(entry, "position:x", sx, dur_in)

		EasyChatConfig.AnimType.SLIDE_RIGHT:
			entry.modulate.a = config.notification_alpha
			var sx := entry.position.x
			entry.position.x = sx + slide_dist
			t.tween_property(entry, "position:x", sx, dur_in)

		EasyChatConfig.AnimType.SLIDE_UP:
			# Enter from below: start below the container's visible bottom edge.
			entry.modulate.a = config.notification_alpha
			var sy := entry.position.y
			entry.position.y = sy + slide_dist
			t.tween_property(entry, "position:y", sy, dur_in)

		EasyChatConfig.AnimType.SLIDE_DOWN:
			# Enter from above: start above the container's visible top edge.
			entry.modulate.a = config.notification_alpha
			var sy := entry.position.y
			entry.position.y = sy - slide_dist
			t.tween_property(entry, "position:y", sy, dur_in)

		EasyChatConfig.AnimType.SCALE:
			entry.modulate.a = config.notification_alpha
			entry.pivot_offset = Vector2(entry.size.x * 0.5, entry.size.y)
			entry.scale = Vector2(1.0, 0.001)
			t.set_trans(Tween.TRANS_BACK)
			t.tween_property(entry, "scale:y", 1.0, dur_in)

	# After the entry appears: hold, then fade out, then free.
	t.tween_interval(config.notification_duration)
	t.tween_property(entry, "modulate:a", 0.0, 0.4)
	t.tween_callback(func() -> void:
		if is_instance_valid(entry): entry.queue_free()
	)

func _make_notification_style() -> StyleBox:
	return config.notification_style if config.notification_style != null \
		else _default_notification_style()


# ─── SOUND ────────────────────────────────────────────────────────────────────
func _play_sound(stream: AudioStream) -> void:
	if stream == null or _audio_player == null:
		return
	_audio_player.stream = stream
	_audio_player.play()


# ─── UI CONSTRUCTION ──────────────────────────────────────────────────────────
func _create_ui() -> void:
	# ── History ──
	_history_panel = PanelContainer.new()
	_history_panel.layout_mode = 1
	_history_panel.anchor_top = 1.0
	_history_panel.anchor_bottom = 1.0
	_history_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_scroll = ScrollContainer.new()
	_scroll.layout_mode = 2
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_message_list = VBoxContainer.new()
	_message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_scroll.add_child(_message_list)
	_history_panel.add_child(_scroll)
	add_child(_history_panel)

	# ── Autocomplete ──
	_autocomplete_panel = PanelContainer.new()
	_autocomplete_panel.layout_mode = 1
	_autocomplete_panel.anchor_top = 1.0
	_autocomplete_panel.anchor_bottom = 1.0
	_autocomplete_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_autocomplete_scroll = ScrollContainer.new()
	_autocomplete_scroll.layout_mode = 2
	_autocomplete_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_autocomplete_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_autocomplete_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_suggestion_list = VBoxContainer.new()
	_suggestion_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_autocomplete_scroll.add_child(_suggestion_list)
	_autocomplete_panel.add_child(_autocomplete_scroll)
	add_child(_autocomplete_panel)

	# ── Notification stack ──
	# Entries are added dynamically by _show_notification().
	# alignment=END means new entries appear at the bottom, growing upward.
	_notif_container = VBoxContainer.new()
	_notif_container.layout_mode = 1
	_notif_container.anchor_top = 1.0
	_notif_container.anchor_bottom = 1.0
	_notif_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notif_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notif_container.alignment = BoxContainer.ALIGNMENT_END
	_notif_container.clip_children = Control.CLIP_CHILDREN_ONLY
	add_child(_notif_container)

	# ── Input row ──
	_input_row = HBoxContainer.new()
	_input_row.layout_mode = 1
	_input_row.anchor_top = 1.0
	_input_row.anchor_bottom = 1.0
	_input_row.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_msg_input = LineEdit.new()
	_msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_input.placeholder_text = config.input_placeholder_text.replace(
		"{key}", OS.get_keycode_string(open_key)
	)

	_send_btn = Button.new()
	_send_btn.custom_minimum_size = Vector2(config.send_button_width, 0.0)
	_send_btn.text = config.send_button_text
	_send_btn.visible = config.show_send_button

	_input_row.add_child(_msg_input)
	_input_row.add_child(_send_btn)
	add_child(_input_row)

	# ── Audio ──
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)


# ─── THEME AND LAYOUT ─────────────────────────────────────────────────────────
func _apply_config_props() -> void:
	_send_btn.text    = config.send_button_text
	_send_btn.visible = config.show_send_button
	_send_btn.custom_minimum_size = Vector2(config.send_button_width, 0.0)
	_msg_input.placeholder_text = config.input_placeholder_text.replace(
		"{key}", OS.get_keycode_string(open_key)
	)

func _apply_layout() -> void:
	var right := config.panel_margin_left + config.panel_width
	var input_top := -(config.panel_margin_bottom + config.input_height)
	var history_top := input_top - config.panel_height

	_history_panel.offset_left   = config.panel_margin_left
	_history_panel.offset_right  = right
	_history_panel.offset_top    = history_top
	_history_panel.offset_bottom = input_top

	_autocomplete_panel.offset_left   = config.panel_margin_left
	_autocomplete_panel.offset_right  = right
	_autocomplete_panel.offset_bottom = input_top
	_autocomplete_panel.offset_top    = input_top - config.suggestion_item_height * 3.0

	# The container spans the full height above the input row so entries can
	# stack upward as far as needed (ALIGNMENT_END keeps them pinned at the bottom).
	_notif_container.offset_left   = config.panel_margin_left
	_notif_container.offset_right  = right
	_notif_container.offset_bottom = input_top - 3.0
	_notif_container.offset_top    = history_top

	_input_row.offset_left   = config.panel_margin_left
	_input_row.offset_right  = right
	_input_row.offset_top    = input_top
	_input_row.offset_bottom = -config.panel_margin_bottom

	_input_row.add_theme_constant_override("separation", config.input_send_separation)

func _apply_theme() -> void:
	# Each element uses config.X_style if assigned, otherwise falls back to a
	# built-in StyleBoxFlat that reproduces the original default appearance.
	_history_panel.add_theme_stylebox_override("panel",
		config.history_style if config.history_style != null else _default_history_style())

	_autocomplete_panel.add_theme_stylebox_override("panel",
		config.autocomplete_style if config.autocomplete_style != null else _default_autocomplete_style())

	var s_input       := config.input_style       if config.input_style       != null else _default_input_style()
	var s_input_focus := config.input_focus_style if config.input_focus_style != null else _default_input_focus_style()
	_msg_input.add_theme_stylebox_override("normal",    s_input)
	_msg_input.add_theme_stylebox_override("read_only", s_input)
	_msg_input.add_theme_stylebox_override("focus",     s_input_focus)
	_msg_input.add_theme_color_override("font_color",             config.remote_message_color)
	_msg_input.add_theme_color_override("font_placeholder_color", config.input_placeholder_color)
	_msg_input.add_theme_color_override("caret_color",            config.input_caret_color)
	_apply_font_theme(_msg_input, config.input_font, config.input_font_size)

	var s_btn   := config.send_button_style       if config.send_button_style       != null else _default_send_style()
	var s_btn_h := config.send_button_hover_style if config.send_button_hover_style != null else _default_send_hover_style()
	_send_btn.add_theme_stylebox_override("normal",  s_btn)
	_send_btn.add_theme_stylebox_override("hover",   s_btn_h)
	_send_btn.add_theme_stylebox_override("pressed", s_btn_h)
	_send_btn.add_theme_stylebox_override("focus",   s_btn)
	_send_btn.add_theme_color_override("font_color", config.send_button_text_color)
	_apply_font_theme(_send_btn, config.send_button_font, config.send_button_font_size)

# ── Default StyleBox factories ────────────────────────────────────────────────
# These reproduce the original appearance when no StyleBox is assigned in the config.
# Assign your own StyleBoxFlat / StyleBoxTexture in the config to override anything here.

func _default_history_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.06, 0.08, 0.78)
	s.corner_radius_top_left  = 6;  s.corner_radius_top_right  = 6
	s.corner_radius_bottom_left = 0; s.corner_radius_bottom_right = 0
	s.content_margin_left = 8.0;  s.content_margin_right  = 8.0
	s.content_margin_top  = 6.0;  s.content_margin_bottom = 6.0
	return s

func _default_autocomplete_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.07, 0.11, 0.94)
	s.corner_radius_top_left = 4;  s.corner_radius_top_right = 4
	s.content_margin_top = 3.0;   s.content_margin_bottom   = 3.0
	return s

func _default_autocomplete_item_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

func _default_autocomplete_selected_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.18, 0.28, 0.58, 0.88)
	s.content_margin_left = 8.0;  s.content_margin_right  = 8.0
	s.content_margin_top  = 2.0;  s.content_margin_bottom = 2.0
	return s

func _default_input_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.06, 0.08, 0.65)
	s.border_width_left = 1;  s.border_width_top    = 1
	s.border_width_right = 1; s.border_width_bottom = 1
	s.border_color = Color(0.3, 0.3, 0.35, 0.5)
	s.corner_radius_bottom_left = 6;  s.corner_radius_bottom_right = 6
	s.content_margin_left = 10.0; s.content_margin_right  = 10.0
	s.content_margin_top  = 4.0;  s.content_margin_bottom = 4.0
	return s

func _default_input_focus_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.07, 0.10, 0.88)
	s.border_width_left = 1;  s.border_width_top    = 1
	s.border_width_right = 1; s.border_width_bottom = 1
	s.border_color = Color(0.45, 0.55, 1.0, 0.8)
	s.corner_radius_bottom_left = 6;  s.corner_radius_bottom_right = 6
	s.content_margin_left = 10.0; s.content_margin_right  = 10.0
	s.content_margin_top  = 4.0;  s.content_margin_bottom = 4.0
	return s

func _default_send_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.06, 0.08, 0.65)
	s.border_width_left = 1;  s.border_width_top    = 1
	s.border_width_right = 1; s.border_width_bottom = 1
	s.border_color = Color(0.3, 0.3, 0.35, 0.5)
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 6.0;  s.content_margin_right  = 6.0
	s.content_margin_top  = 4.0;  s.content_margin_bottom = 4.0
	return s

func _default_send_hover_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.07, 0.10, 0.88)
	s.border_width_left = 1;  s.border_width_top    = 1
	s.border_width_right = 1; s.border_width_bottom = 1
	s.border_color = Color(0.45, 0.55, 1.0, 0.8)
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 6.0;  s.content_margin_right  = 6.0
	s.content_margin_top  = 4.0;  s.content_margin_bottom = 4.0
	return s

func _default_notification_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.06, 0.08, 0.0)
	s.corner_radius_top_left  = 4;  s.corner_radius_top_right  = 4
	s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
	s.content_margin_left = 6.0;  s.content_margin_right  = 6.0
	s.content_margin_top  = 3.0;  s.content_margin_bottom = 3.0
	return s

## Applies [size] and optional [font] to [node].
## When [font] is null any existing font override is removed, restoring the project theme font.
func _apply_font_theme(node: Control, font: Font, size: int) -> void:
	node.add_theme_font_size_override("font_size", size)
	if font:
		node.add_theme_font_override("font", font)
	else:
		node.remove_theme_font_override("font")


# ─── EDITOR PREVIEW HELPERS ───────────────────────────────────────────────────
# These functions are only meaningful in the editor (@tool) and are wired to
# the inspector buttons in the Preview group.  They reuse the same code paths
# as runtime so the preview is an accurate representation of the real chat.

func _preview_local_msg() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_message_list):
		return
	_add_message("You", "Hey! This is a message sent by you.", true)

func _preview_remote_msg() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_message_list):
		return
	_add_message("Player2", "Hello! This is a message from another player.", false)

func _preview_system_msg() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_message_list):
		return
	# broadcast=false — local only, no RPC in editor
	_add_system_message("Player2 has joined the session.", false)

func _preview_clear_history() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_message_list):
		return
	for child in _message_list.get_children():
		child.queue_free()

func _preview_notif() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_notif_container):
		return
	_show_notification("[Player2]: Hello! This is a notification preview.")
	# Make the container visible so the notification is actually seen.
	preview_notification = true

func _preview_sys_notif() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_notif_container):
		return
	_show_notification(config.system_message_prefix + "Player2 has joined the session.")
	preview_notification = true

func _preview_show_commands() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_autocomplete_panel):
		return
	# Passing "" matches all commands (every name begins_with "").
	_update_autocomplete("")
	# Ensure the panel is visible whether or not there are commands configured.
	if not _autocomplete_panel.visible:
		_autocomplete_panel.visible = true
	preview_autocomplete = true


func _stop_preview_history_anim() -> void:
	if not Engine.is_editor_hint():
		return
	if _anim_tween_history != null:
		_anim_tween_history.kill()
		_anim_tween_history = null
	if is_instance_valid(_history_panel):
		_apply_layout()
		_history_panel.scale = Vector2.ONE


func _stop_preview_input_anim() -> void:
	if not Engine.is_editor_hint():
		return
	if _anim_tween_input != null:
		_anim_tween_input.kill()
		_anim_tween_input = null
	if is_instance_valid(_input_row):
		_apply_layout()
		_input_row.scale = Vector2.ONE


## Editor "chat closed" history state — matches [_open] before the history show tween runs.
func _editor_prep_history_panel_before_show_anim() -> void:
	if not is_instance_valid(_history_panel):
		return
	_history_panel.visible = false
	_history_panel.modulate.a = 0.0
	_history_panel.scale = Vector2.ONE


## Fully open history — matches [_close] / in-game open chat before the history hide tween.
func _editor_prep_history_panel_before_hide_anim() -> void:
	if not is_instance_valid(_history_panel):
		return
	_history_panel.visible = true
	_history_panel.modulate.a = 1.0
	_history_panel.scale = Vector2.ONE


## Editor input row before open — same as runtime [_ready] initial input row.
func _editor_prep_input_row_before_show_anim() -> void:
	if not is_instance_valid(_input_row):
		return
	if _is_fade_anim(config.input_anim_type) \
			or config.input_anim_type == EasyChatConfig.AnimType.NONE:
		_input_row.visible = true
		_input_row.modulate.a = config.alpha_input_closed
	else:
		_input_row.visible = false
		_input_row.modulate.a = 1.0
	_input_row.scale = Vector2.ONE


## Input row while chat is open — before the input hide tween in [_close].
func _editor_prep_input_row_before_hide_anim() -> void:
	if not is_instance_valid(_input_row):
		return
	_input_row.visible = true
	_input_row.modulate.a = 1.0
	_input_row.scale = Vector2.ONE


func _preview_anim_history_show() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_history_panel):
		return
	_stop_preview_history_anim()
	_editor_prep_history_panel_before_show_anim()
	_anim_tween_history = _anim_element_show(
		_history_panel,
		config.history_anim_type,
		config.history_anim_duration,
		config.history_slide_distance,
		0.0
	)


func _preview_anim_history_hide() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_history_panel):
		return
	_stop_preview_history_anim()
	_editor_prep_history_panel_before_hide_anim()
	_anim_tween_history = _anim_element_hide(
		_history_panel,
		config.history_anim_type,
		config.history_anim_duration,
		config.history_slide_distance,
		0.0
	)


func _preview_anim_input_row_show() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_input_row):
		return
	_stop_preview_input_anim()
	_editor_prep_input_row_before_show_anim()
	var from_alpha := config.alpha_input_closed if _is_fade_anim(config.input_anim_type) else 0.0
	_anim_tween_input = _anim_element_show(
		_input_row,
		config.input_anim_type,
		config.input_anim_duration,
		config.input_slide_distance,
		from_alpha
	)


func _preview_anim_input_row_hide() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_input_row):
		return
	_stop_preview_input_anim()
	_editor_prep_input_row_before_hide_anim()
	var end_alpha := config.alpha_input_closed if _is_fade_anim(config.input_anim_type) else 0.0
	_anim_tween_input = _anim_element_hide(
		_input_row,
		config.input_anim_type,
		config.input_anim_duration,
		config.input_slide_distance,
		end_alpha
	)
	

@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_chat_message(sender_name: String, message_text: String) -> void:
	if not is_inside_tree():
		return
	_add_message(sender_name, message_text, false)
