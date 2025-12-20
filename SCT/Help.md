# 帮助与说明

## 核心理念
**“尊重 Rime 逻辑，简化用户操作”**
- **非破坏性**：SCT 永远不会修改 Rime 的默认 `.yaml` 文件。所有更改都写入 `default.custom.yaml` 或 `squirrel.custom.yaml` 的 `patch:` 键下。
- **原生体验**：使用 SwiftUI 构建，提供原生的 macOS 设置体验。
- **透明度**：您可以在“高级设置”中随时查看合并后的 YAML 配置。

## 常见问题 (FAQ)

### 1. 为什么我的更改没有生效？
在 SCT 中保存更改后，您需要点击工具栏上的“部署”按钮（或使用快捷键 `Cmd+R`）。这会触发 Squirrel 重新加载配置。

### 2. 如何添加新的输入方案？
在“输入方案”页面，点击底部的“添加新方案”按钮。输入方案 ID（如 `rime_ice`）和名称。SCT 会自动为您创建基础的方案文件并将其添加到激活列表中。

### 3. 什么是“高级设置”？
“高级设置”允许您浏览 Rime 的完整配置树。您可以直接修改任何值，SCT 会自动将其添加到对应的 `.custom.yaml` 文件中。

### 4. 沙盒访问权限
为了安全地访问 `~/Library/Rime` 目录，SCT 需要您的授权。如果您移动了 Rime 目录，可以在此处重新授权。

## 关于 SCT
SCT (Squirrel Configuration Tool) 是一个开源项目，旨在为 macOS 上的鼠须管输入法提供更友好的配置界面。

[GitHub 项目主页](https://github.com/paradigmx/rime-sct)

---
© 2025 Neo. All rights reserved.