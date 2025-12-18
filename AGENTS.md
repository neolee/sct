# Squirrel Configuration Tool (SCT) - Agent Guide

This document serves as a project overview and design record for AI agents working on the Squirrel (鼠须管) configuration GUI.

## Project Overview
The goal is to provide a native macOS GUI for configuring the Squirrel input method, which traditionally requires manual editing of YAML files in `~/Library/Rime`.

## Core Design Philosophy
**"Respect Rime Logic, Simplify User Operation"**
- **Non-Destructive**: Never modify default `.yaml` files. All changes must be written to `.custom.yaml` files under the `patch:` key.
- **Native Experience**: Use SwiftUI and macOS design patterns to make configuration feel like a first-class system setting.
- **Transparency**: Users should be able to see what YAML changes are being made.

## Key Design Decisions

### 1. Dual-Layer Configuration Model
- **Base Layer**: `default.yaml`, `squirrel.yaml` (Read-only).
- **Patch Layer**: `default.custom.yaml`, `squirrel.custom.yaml` (Read/Write).
- **Merged View**: The GUI displays the result of merging the Patch Layer into the Base Layer.

### 2. Technology Stack
- **Language**: Swift 6.0+
- **Framework**: SwiftUI (Targeting latest macOS)
- **YAML Engine**: [Yams](https://github.com/jpsim/Yams) for robust YAML parsing and serialization.

### 3. Configuration Merging Logic
Rime's patch system supports:
- Simple key-value replacement.
- Nested key access (e.g., `style/font_face`).
- Array manipulation (though SCT currently focuses on full array replacement for simplicity).

### 4. Color Handling
Rime uses **BGR** (Blue-Green-Red) hex format (e.g., `0xBBGGRR`). SCT must:
- Convert BGR to `SwiftUI.Color` for the UI.
- Convert `SwiftUI.Color` back to BGR for saving.

## Functional Modules

### General Settings
- `menu/page_size`: Number of candidates.
- `schema_list`: Selection and ordering of input schemas.
- `ascii_composer`: Behavior of Shift/Caps Lock keys.

### Appearance (The "Skin" Module)
- **Skin Selection**: Browse and apply `preset_color_schemes`.
- **Live Preview**: A simulated candidate window that reflects font, color, and layout changes in real-time.
- **Font Management**: Selection of system fonts and point sizes.

### App-Specific Settings
- `app_options`: Manage `ascii_mode` (default English) for specific applications (e.g., Terminal, Xcode).

### Shortcuts
- `switcher/hotkeys`: Record and manage global activation hotkeys.

## Technical Implementation Details

### Deployment Mechanism
After saving changes, Squirrel needs to "Deploy" to apply them.
- **Method**: Triggered via a "Deploy" button in the GUI.
- **Implementation**: Execute `/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel --reload` or touch the config files.

### File Monitoring
- Monitor `~/Library/Rime` for external changes to keep the GUI in sync.

### Sandbox & File Access
- During development we disable the App Sandbox so SCT can access the real `~/Library/Rime` path for schema testing.
- Before shipping we must re-enable the sandbox and build a security-scoped file access flow (e.g., prompting for `~/Library/Rime` and persisting the bookmark).

## Current Progress (as of 2025-12-18)
- [x] Initial project scaffolding.
- [x] Basic `RimeConfigManager` structure for YAML handling.
- [x] UI Prototype with Sidebar navigation and basic forms.
- [ ] Integration with `Yams` library.
- [ ] Robust patch merging implementation.
- [ ] BGR <-> RGB color conversion utility.

## Future Roadmap
- [ ] Advanced "Source Code" mode for direct YAML editing.
- [ ] Schema-driven UI generation to support future Rime features without code changes.
- [ ] Cloud sync/backup of `.custom.yaml` files.