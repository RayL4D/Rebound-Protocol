# easychat_config.gd
class_name EasyChatConfig
extends Resource
## EasyChatConfig — Reusable resource with all EasyChat settings.
## Create a .tres file, customize it, and assign it to any EasyChat node.

## Animation style used to show or hide a chat element.
enum AnimType {
	NONE,       ## Instant show/hide with no transition.
	FADE,       ## Fade in/out using opacity (default).
	FADE_UP,    ## Fade + slide up.
	FADE_DOWN,  ## Fade + slide down.
	FADE_LEFT,  ## Fade + slide left.
	FADE_RIGHT, ## Fade + slide right.
	SLIDE_UP,   ## Element enters sliding upward from below; exits sliding downward.
	SLIDE_DOWN, ## Element enters sliding downward from above; exits sliding upward.
	SLIDE_LEFT, ## Element enters sliding in from the left; exits to the left.
	SLIDE_RIGHT,## Element enters sliding in from the right; exits to the right.
	SCALE,      ## Element scales vertically from/to zero, pivoting at the bottom edge.
}

# ── Appearance ────────────────────────────────────────────────────────────────
@export_group("Appearance")

@export_subgroup("History")
## StyleBox applied to the message history panel background.
## Use StyleBoxFlat for solid colors and rounded corners,
## StyleBoxTexture for image / nine-patch backgrounds, or leave empty for the built-in default.
## The StyleBox's Content Margin fields control the internal padding of the panel.
@export var history_style: StyleBox = null

@export_subgroup("Autocomplete")
## StyleBox for the autocomplete dropdown panel background.
## Leave empty to use the built-in default.
@export var autocomplete_style: StyleBox = null
## StyleBox for an unselected suggestion row. Leave empty for transparent background.
@export var autocomplete_item_style: StyleBox = null
## StyleBox for the currently highlighted suggestion row.
## Leave empty to use the built-in default highlight.
@export var autocomplete_selected_style: StyleBox = null
## Text color used for command names (e.g. "/help") in the suggestion list.
@export var autocomplete_command_color: Color = Color(0.55, 0.85, 1.0, 1.0)
## Text color used for command descriptions in the suggestion list.
@export var autocomplete_desc_color: Color = Color(0.7, 0.7, 0.75, 0.75)
## Font size for all text inside the autocomplete suggestion panel.
@export var autocomplete_font_size: int = 12
## Font used for all text inside the autocomplete suggestion panel. Leave empty to use the project theme font.
@export var autocomplete_font: Font = null

@export_subgroup("Input")
## StyleBox for the text input field in its normal (unfocused) state.
## Leave empty to use the built-in default. Content Margins control internal text padding.
@export var input_style: StyleBox = null
## StyleBox for the text input field when it has keyboard focus.
## Leave empty to use the built-in default.
@export var input_focus_style: StyleBox = null
## Font size for the typed text inside the input field.
@export var input_font_size: int = 13
## Font used for the typed text and placeholder inside the input field. Leave empty to use the project theme font.
@export var input_font: Font = null
## Color of the text cursor (caret) inside the input field.
@export var input_caret_color: Color = Color(0.75, 0.85, 1.0)
## Color of the placeholder text shown when the input field is empty.
@export var input_placeholder_color: Color = Color(0.6, 0.6, 0.6, 0.85)
## Placeholder text shown when the input is empty. Use {key} as a token — it will be
## replaced at runtime with the actual open key name (e.g. "T").
@export var input_placeholder_text: String = tr("PLACEHOLDER_EASYCHAT")

@export_subgroup("Send Button")
## StyleBox for the send button in its normal state.
## Leave empty to use the built-in default. Content Margins control button padding.
@export var send_button_style: StyleBox = null
## StyleBox for the send button when hovered or pressed.
## Leave empty to use the built-in default.
@export var send_button_hover_style: StyleBox = null
## Label shown on the send button.
@export var send_button_text: String = "↵"
## Text color of the send button label.
@export var send_button_text_color: Color = Color(0.9, 0.9, 0.85)
## Font size of the send button label.
@export var send_button_font_size: int = 13
## Font used for the send button label. Leave empty to use the project theme font.
@export var send_button_font: Font = null

@export_subgroup("Messages")
## Font size for all messages displayed in the history panel.
@export var message_font_size: int = 13
## Font used for all messages in the history panel. Leave empty to use the project theme font.
@export var message_font: Font = null
## Format string for player messages. Use {sender} and {message} as tokens.
@export var message_format: String = "[{sender}]: {message}"
## Text color for messages sent by the local player.
@export var local_message_color: Color = Color(0.6, 1.0, 0.65)
## Text color for messages received from other players.
@export var remote_message_color: Color = Color(0.9, 0.9, 0.85)
## Text color for system messages (sent via EasyChat.add_system_message()).
@export var system_message_color: Color = Color(1.0, 0.75, 0.3)
## Prefix prepended to every system message. Can be an icon, a tag, or left empty.
@export var system_message_prefix: String = "▶ "

@export_subgroup("Notification")
## StyleBox applied to each stacked notification entry.
## Leave empty to use the built-in default (transparent background).
## Content Margins control the padding around the notification text.
@export var notification_style: StyleBox = null
## Text color of the floating notification entries.
@export var notification_color: Color = Color(0.9, 0.9, 0.85)
## Font size of the notification text.
@export var notification_font_size: int = 13
## Font used for the notification text. Leave empty to use the project theme font.
@export var notification_font: Font = null

# ── Behavior ──────────────────────────────────────────────────────────────────
@export_group("Behavior")
## Whether the send button is visible next to the input field.
@export var show_send_button: bool = true
## If true, the chat automatically closes after the player sends a message or runs a command.
## When closed via this setting, the sent message briefly appears in the notification overlay.
@export var close_on_send: bool = false
## Opacity of the input row when the chat is closed (only applies to FADE and NONE animation types). Range 0–1.
@export var alpha_input_closed: float = 0.35
## Maximum opacity of the floating notification entries. Range 0–1.
@export var notification_alpha: float = 0.75
## How long (in seconds) each floating notification stays visible before fading out.
@export var notification_duration: float = 3.0
## Maximum number of messages kept in the history. Oldest messages are removed when the limit is reached.
@export var max_messages: int = 100
## Maximum number of autocomplete suggestions shown at once before the list starts scrolling.
@export var max_suggestions_visible: int = 6
## Maximum number of notification entries that can stack at once.
## When the limit is reached, the oldest entry is removed to make room for the new one.
@export var max_notifications: int = 3

# ── Animations ────────────────────────────────────────────────────────────────
@export_group("Animations")

@export_subgroup("History Panel")
## Animation style used when the history panel opens or closes.
@export var history_anim_type: AnimType = AnimType.FADE
## Duration in seconds of the history panel open/close animation.
@export var history_anim_duration: float = 0.18
## Pixel distance for SLIDE_* history animations.
@export var history_slide_distance: float = 206.0

@export_subgroup("Input Row")
## Animation style used when the input row appears or disappears.
## Note: for SLIDE and SCALE types the input row is fully hidden when the chat is closed.
## FADE and FADE_* keep the row visible with alpha_input_closed while closed.
@export var input_anim_type: AnimType = AnimType.FADE
## Duration in seconds of the input row open/close animation.
@export var input_anim_duration: float = 0.18
## Pixel distance for SLIDE_* input row animations.
@export var input_slide_distance: float = 42.0

@export_subgroup("History messages")
## Animation played when a new line is appended to the history (player and system messages).
## NONE keeps the previous instant appearance. SLIDE_* uses message_slide_distance (pixels).
@export var message_anim_type: AnimType = AnimType.NONE
## Duration in seconds of the history message appear animation.
@export var message_anim_duration: float = 0.12
## Pixel distance for SLIDE_* message animations (how far off-screen the line starts).
@export var message_slide_distance: float = 28.0

@export_subgroup("Notification")
## Animation style used when a notification entry appears.
## SLIDE_LEFT / SLIDE_RIGHT slide the entry in from outside the panel horizontally.
## SLIDE_UP / SLIDE_DOWN slide the entry in along the vertical axis.
## SCALE scales the entry in from zero height, pivoting at the bottom edge.
@export var notification_anim_type: AnimType = AnimType.FADE
## Duration in seconds of the notification entry appear animation.
@export var notification_anim_duration: float = 0.15
## Pixel distance for SLIDE_* notification animations.
@export var notification_slide_distance: float = 28.0

# ── Layout ────────────────────────────────────────────────────────────────────
@export_group("Layout")
## Width (in pixels) of the entire chat panel (history + input row).
@export var panel_width: float = 415.0
## Height (in pixels) of the message history panel.
@export var panel_height: float = 206.0
## Height (in pixels) of the input row (text field + send button).
@export var input_height: float = 42.0
## Width (in pixels) of the send button. Only relevant when show_send_button is true.
@export var send_button_width: float = 52.0
## Horizontal gap (in pixels) between the message input field and the send button.
## Uses the HBoxContainer separation; only visible when show_send_button is true.
@export var input_send_separation: int = 0
## Distance (in pixels) from the left edge of the viewport to the chat panel.
@export var panel_margin_left: float = 10.0
## Distance (in pixels) from the bottom edge of the viewport to the chat panel.
@export var panel_margin_bottom: float = 10.0
## Height (in pixels) of each row in the autocomplete suggestion list.
@export var suggestion_item_height: float = 28.0

# ── Sounds ────────────────────────────────────────────────────────────────────
@export_group("Sounds")
## Sound played when a message is received from another player. Leave empty for no sound.
@export var sound_message_received: AudioStream = null
## Sound played when a system message arrives in the history. Leave empty for no sound.
@export var sound_system_message: AudioStream = null
## Sound played when the local player successfully sends a message. Leave empty for no sound.
@export var sound_message_sent: AudioStream = null
## Sound played when the chat panel opens. Leave empty for no sound.
@export var sound_chat_opened: AudioStream = null
## Sound played when the chat panel closes. Leave empty for no sound.
@export var sound_chat_closed: AudioStream = null

# ── Commands ──────────────────────────────────────────────────────────────────
@export_group("Commands")
## List of ChatCommand resources. Each command appears in autocomplete and emits
## its own executed(args) signal when run.
@export var commands: Array[ChatCommand] = []
