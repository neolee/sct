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

## Configuration Grouping Decisions
1. Input Schemes: expose `schema_list` plus the primary `switcher` fields (hotkeys/save_options/fold_options/abbreviate_options/option_list_separator); uncommon keys stay in Advanced YAML mode.
2. Candidate Panel: manage every `menu` and `style` sub-key, including memorize_size/mutual_exclusive/translucency/show_paging. `keyboard_layout`/`chord_duration`/`show_notifications_when` keep their defaults and do not need GUI.
3. Input Behaviors: give `ascii_composer` its own module; keep `punctuator` and `recognizer` in the YAML editor only; surface only the frequently used `key_binder` mappings (commit-first/last, paging, etc.).
4. App Options: the `app_options` table shows four toggle columns (ascii_mode/inline/no_inline/vim_mode) and can grow if we add more flags later.
5. Skins: preset color schemes remain read-only for now; a richer "skin editor" may come later for advanced users.
6. YAML Editor: must display the merged base+patch view, highlight patched values, support filtering to "customized only", provide search, and let users enable/disable individual patches with a split/diff view concept.
7. Sandbox Strategy: keep App Sandbox disabled during development to access real `~/Library/Rime`; re-enable it before release and request that directory via security-scoped bookmarks.
8. Navigation Layout: the macOS UI keeps the `NavigationSplitView` structure from `ContentView.swift`, mapping each group above to a dedicated sidebar item; `SchemaDrivenView` is only a prototype surface, not the final container for every feature.

## Plan and Progress
- [x] Initial project scaffolding (2025-12-18).
- [x] Basic `RimeConfigManager` structure for YAML handling (2025-12-18).
- [x] UI prototype with `NavigationSplitView` sidebar and basic forms (2025-12-18).
- [x] Integration with `Yams` library (2025-12-18).
- [x] Robust patch merging implementation (2025-12-18).
- [x] BGR <-> RGB color conversion utility (2025-12-18).
- [x] Schema expansion: update ConfigSchema.json per the grouping decisions and expose values via RimeConfigManager (2025-12-18).
- [x] Navigation UI: wire each configuration group to its own NavigationSplitView destination; keep SchemaDrivenView as a prototype surface (2025-12-18).
- [ ] Editable controls: add steppers/toggles/tables that modify patch dictionaries and verify merge logic.
- [ ] Key binder view: build UI for common bindings (commit-first/last, prev/next, paging) and persist changes.
- [ ] App options table: support add/remove rows with ascii_mode/inline/no_inline/vim_mode toggles plus validation and sorting.
- [ ] YAML editor prototype: merged + diff views, search/filter, and an Enable Customization switch per entry.
- [ ] Advanced "Source Code" mode for direct YAML editing.
- [ ] Schema-driven UI generation to support future Rime features without code changes.
- [ ] Cloud sync/backup of `.custom.yaml` files.
- [ ] Sandbox reactivation: re-enable App Sandbox, request `~/Library/Rime` access, persist the bookmark, retest reload/deploy.