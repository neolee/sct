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
- **Markdown Engine**: [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) for rich help documentation rendering.

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
- Automatically scan `~/Library/Rime` for `*.schema.yaml` files to populate the available schema list, ensuring user-added schemas are recognized.

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

## Advanced YAML Editor Design
The "Advanced Settings" tab is designed as a **Smart Configuration Browser** to bridge the gap between GUI and raw YAML editing.

### 1. Merged View with Source Attribution
- Displays the final effective configuration tree.
- **Visual Distinction**: Base values (from `default.yaml`) are shown in a neutral style, while patched values (from `.custom.yaml`) are highlighted (e.g., blue text or background).
- **Source Labels**: Each entry indicates whether it's a "Default" or "Customized" value.

### 2. Interaction Model
- **Search & Filter**: Global search by key path or value. A "Modified Only" toggle to quickly audit user changes.
- **One-Click Customization**: For any default value, a "Customize" button adds it to the patch dictionary and opens it for editing.
- **One-Click Reset**: For any customized value, a "Reset" button removes it from the patch, reverting to the base value.

### 3. Editor Types
- **Type-Aware UI**: Automatically provides appropriate controls (Toggle for Bool, Stepper for Int, TextField for String).
- **Source Fallback**: For complex types (nested objects or arrays), provides a mini YAML source editor.
- **Full Source Mode**: A dedicated sub-tab for direct editing of the `.custom.yaml` file with syntax validation.

### 4. Advanced Settings Refinement (2025-12-19)
- **Duplicate Entry Fix**: Resolved an issue where customized keys appeared twice by ensuring the patch dictionary is normalized (nested) before merging into the base configuration.
- **Unified Text Editor**: Replaced type-specific controls (Toggle, Stepper, etc.) with a consistent `TextField` for all values in the Advanced view. This provides a more "pro" feel and avoids UI clutter.
- **Smart Parsing**: Implemented a `parseValue` helper to automatically convert text input back to `Bool`, `Int`, or `Double` where appropriate, maintaining YAML type integrity.
- **Reset Logic Fix**: Corrected the order of operations in `removePatch` to ensure changes are saved to disk before reloading the configuration, fixing the issue where the reset button had no effect.
- **UX Polish**:
    - Fixed label wrapping in the header.
    - Enabled full-row click to focus the editor.
    - Implemented "Select All" on focus for faster editing.

## Plan and Progress
- [x] Initial project scaffolding (2025-12-18).
- [x] Basic `RimeConfigManager` structure for YAML handling (2025-12-18).
- [x] UI prototype with `NavigationSplitView` sidebar and basic forms (2025-12-18).
- [x] Integration with `Yams` library (2025-12-18).
- [x] Robust patch merging implementation (2025-12-18).
- [x] BGR <-> RGB color conversion utility (2025-12-18).
- [x] Schema-driven UI generation to support future Rime features without code changes.
- [x] Schema expansion: update ConfigSchema.json per the grouping decisions and expose values via RimeConfigManager (2025-12-18).
- [x] Navigation UI: wire each configuration group to its own NavigationSplitView destination; keep SchemaDrivenView as a prototype surface (2025-12-18).
- [x] Key binder view: build UI for common bindings (commit-first/last, prev/next, paging) and persist changes (2025-12-19).
- [x] App options table: support add/remove rows with ascii_mode/inline/no_inline/vim_mode toggles plus validation and sorting (2025-12-19).
- [x] App selection: allow users to select apps from /Applications to get Bundle ID (2025-12-19).
- [x] UI Polish: rename "App Options" to "应用程序" and "Bundle ID" to "应用程序 ID" (2025-12-19).
- [x] YAML editor prototype: merged + diff views, search/filter, and an Enable Customization switch per entry (2025-12-19).
- [x] Advanced "Source Code" mode for direct YAML editing (2025-12-19).
- [x] Sandbox reactivation: re-enable App Sandbox, request `~/Library/Rime` access, persist the bookmark, retest reload/deploy (2025-12-20).
- [x] Documentation and user friendly help within the app (Added HelpView and field descriptions) (2025-12-20).
- [x] UI String Consolidation: Created `L10n.swift` to centralize static UI strings and moved Help content to `Help.md` (2025-12-20).
- [x] Markdown-based Help system: Refactored `HelpView` to load content from an external `Help.md` file for easier maintenance (2025-12-20).
- [x] Fix Markdown rendering: Integrated `MarkdownUI` library for professional rendering of headers, lists, and GitHub Flavored Markdown (2025-12-20).
- [ ] Backup/cloud sync of `.custom.yaml` files. (Users can use iCloud/Dropbox; SCT provides "Show in Finder" for convenience).
- [ ] Auto update mechanism for SCT itself. (Added "Check for Updates" link to GitHub).
- [ ] Final polish and distribution preparation.