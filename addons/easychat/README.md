# EasyChat

[![Godot 4](https://img.shields.io/badge/Godot-4.3-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Version](https://img.shields.io/badge/version-2.0.0-5aafff)](./plugin.cfg)

**EasyChat** is a modular, reusable **in-game chat** and **command console** addon for [**Godot 4**](https://godotengine.org/). Drop a single custom node into your UI, tune appearance and behaviour with resources, and optionally sync chat over the network when you pair it with **LinkUx** (LAN / online backends with the same game-side flow).

Whether you are building a single-player HUD, a co-op lobby, or a competitive session, EasyChat gives you history, autocomplete for `/` commands, notifications while the panel is closed, and a small global API so gameplay code can post system messages without juggling node references.

---

## 📑 Table of contents

- [Features](#features)
- [What’s new in 2.0.0](#whats-new-in-200)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Documentation](#documentation)
- [Project layout](#project-layout)
- [Credits](#credits)

---

## ✨ Features

| | |
| :--- | :--- |
| **Custom node** | Registered editor type **EasyChat** (`Control`) with its own icon and live editor preview. |
| **Global API** | Autoload **`EasyChat`** for `enable()`, `disable()`, `add_message()`, `add_system_message()`, and more. |
| **Robust customization** | **`EasyChatConfig`** now centralizes a simpler but more powerful setup: colors, fonts, layout, animations, sounds, limits, and command list—share one `.tres` across scenes. |
| **StyleBox per element** | Assign custom `StyleBox` resources to history, input, send button, autocomplete, suggestion rows, and notifications while preserving built-in default styles. |
| **Interactive preview tools** | New **Preview** section in `EasyChatConfig` with editor buttons to rebuild, toggle sections, spawn sample messages/notifications, and preview show/hide animations instantly. |
| **Expanded animations** | All chat elements support `NONE`, `FADE`, `FADE_UP`, `FADE_DOWN`, `FADE_LEFT`, `FADE_RIGHT`, `SLIDE_*`, and `SCALE`, plus per-group `Slide Distance` controls in `Animations`. |
| **Commands** | **`ChatCommand`** resources with `executed(args)`; autocomplete and keyboard navigation. |
| **Offline & online** | Works out of the box offline; enable **`multiplayer_enabled`** and LinkUx for real-time RPC chat. |
| **Player-friendly** | Open/close keys, optional “close on send”, floating notifications, and input that does not eat gameplay when the chat is closed. |

---

## 🚀 What’s new in 2.0.0

- Simplified and redesigned the customization workflow so setup is faster while still allowing deep visual control.
- Added `StyleBox` support across chat elements, enabling fine-grained skinning without losing the default fallback theme.
- Added the new **Preview** tools in `EasyChatConfig` for direct editor-side testing of states, sample content, and animations.
- Expanded animation options with directional fade variants (`FADE_UP/DOWN/LEFT/RIGHT`) and per-subgroup slide distance values.

---

## 📋 Requirements

| Item | Required? | Notes |
| :--- | :---: | :--- |
| **Godot 4.3** | Yes | Uses Godot 4 APIs (`@export`, typed signals, `Tween`, etc.). |
| **LinkUx addon** | Optional | Only if you turn on **`multiplayer_enabled`** on the EasyChat node and want networked chat. Expects autoload **`/root/LinkUx`**. |

Expected install path in your project:

```text
res://addons/easychat/
```

---

## 📦 Installation

1. Copy this repository’s `addons/easychat` folder (or the packaged addon folder) into your Godot project under **`res://addons/easychat/`**.
2. Open **Project → Project Settings → Plugins**.
3. Enable **EasyChat**.
4. *(Optional)* Install **LinkUx** and register it as an autoload if you plan to use multiplayer chat.
5. Add an **EasyChat** node to a scene (for example under a `CanvasLayer` that covers the viewport).

That’s it—the plugin registers the **`EasyChat`** autoload and the custom node type automatically.

---

## 🚀 Quick start

### 1️⃣ Add the node

In your main UI or gameplay scene, add **EasyChat** from the **Add Node** dialog. The node fills the screen and anchors the chat bar to the bottom of the viewport.

### 2️⃣ Try it in-game

- Default **open chat** key: **`T`** (configurable on the node).
- Default **close** key: **`Escape`**.
- Type plain text and press **Enter** to send; lines starting with **`/`** run commands.

### 3️⃣ Use the singleton from code

```gdscript
func _ready() -> void:
    EasyChat.set_player_name("Ada") # Only if you want it to display a custom name (in multiplayer mode, it does this automatically)
    EasyChat.enable() # You need to activate it to use it (you can deactivate it with disable())

func _on_match_started() -> void:
    EasyChat.add_system_message("Match started — good luck!")
```

### 4️⃣ Optional: shared look

Create an **`EasyChatConfig`** resource (`.tres`), tweak styles, animations, and limits, assign it to the node’s **`config`** field, and reuse the same resource in other scenes.

### 5️⃣ Preview in the editor

In `EasyChatConfig`, use the **Preview** section buttons to:

- Rebuild and refresh the preview UI.
- Toggle History/Input/Autocomplete/Notifications visibility.
- Trigger show/hide animations for History Panel and Input Row.
- Spawn local/remote/system messages and notification samples.
- Quickly inspect command autocomplete visuals.

---

## 📚 Documentation

The **official documentation** is a website:

Then open **[EasyChat Official Documentation](https://iuxgames.github.io/EasyChat_WebSite/)** in your browser for the full interactive docs (navigation, **EN / ES** language toggle, and **quick search**).

---

## 🗂 Project layout

```text
addons/easychat/
├── plugin.cfg          # Plugin metadata
├── plugin.gd           # EditorPlugin: autoload + custom type registration
├── easychat.gd         # Global EasyChat singleton (facade)
├── easychat_node.gd    # EasyChat Control node (UI, Input, Sync, etc.)
├── easychat_config.gd  # EasyChatConfig resource
├── chat_command.gd     # ChatCommand resource
├── icon.svg
└── icon.png
```

---

## 🙏 Credits

- **EasyChat** — **IUX Games**, **Isaackiux** · version **2.0.0** (see [`plugin.cfg`](./plugin.cfg)).
- Designed to work alongside **LinkUx** for swappable multiplayer backends, but it can work without any problems offline (just uncheck the Multiplayer checkbox in EasyChatConfig).