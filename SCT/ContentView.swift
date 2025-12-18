//
//  ContentView.swift
//  SCT
//
//  Created by Neo on 2025/12/18.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var configManager = RimeConfigManager()
    @StateObject private var schemaStore = SchemaStore()
    @State private var selection: SidebarItem? = .general

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("Squirrel 配置")
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralSettingsView(manager: configManager)
            case .appearance:
                AppearanceSettingsView(manager: configManager)
            case .shortcuts:
                ShortcutSettingsView()
            case .apps:
                AppSettingsView(manager: configManager)
            case .advanced:
                AdvancedSettingsView(reloadAction: configManager.reload)
            case .schemaPreview:
                SchemaDrivenView(schemaStore: schemaStore, manager: configManager)
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .overlay(alignment: .bottomLeading) {
            StatusBarView(status: configManager.statusMessage)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }
}

private enum SidebarItem: String, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }
    case general
    case appearance
    case shortcuts
    case apps
    case advanced
    case schemaPreview

    var title: String {
        switch self {
        case .general: return "通用设置"
        case .appearance: return "外观皮肤"
        case .shortcuts: return "快捷键"
        case .apps: return "应用设置"
        case .advanced: return "高级设置"
        case .schemaPreview: return "Schema 驱动"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .shortcuts: return "keyboard"
        case .apps: return "rectangle.3.group"
        case .advanced: return "hammer"
        case .schemaPreview: return "list.bullet.rectangle"
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        Form {
            Section("菜单") {
                Stepper(value: .constant(manager.pageSize), in: 1...10) {
                    Text("候选词个数：\(manager.pageSize)")
                }
                .help("目前仅展示 patch 中的值，后续将支持实时保存")
            }

            Section("方案列表") {
                if manager.schemaList.isEmpty {
                    Text("尚未加载方案")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.schemaList, id: \.self) { schema in
                        HStack {
                            Text(schema)
                            Spacer()
                            Toggle("启用", isOn: .constant(true))
                                .labelsHidden()
                                .disabled(true)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("通用设置")
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("候选窗预览")
                    .font(.title2)
                    .bold()

                CandidatePreview(colorSchemeName: manager.colorScheme,
                                  fontFace: manager.fontFace,
                                  fontSize: CGFloat(manager.fontPoint))
                    .frame(maxWidth: 440)

                Form {
                    Section("皮肤") {
                        Picker("当前皮肤", selection: .constant(manager.colorScheme)) {
                            Text(manager.colorScheme).tag(manager.colorScheme)
                            Text("dark_temple").tag("dark_temple")
                            Text("clean_white").tag("clean_white")
                        }
                        .disabled(true)
                    }

                    Section("字体") {
                        TextField("字体", text: .constant(manager.fontFace))
                            .disabled(true)
                        Slider(value: .constant(Double(manager.fontPoint)), in: 10...30, step: 1) {
                            Text("字号")
                        }
                        .disabled(true)
                        Text("当前：\(manager.fontPoint) pt")
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            }
            .padding(32)
        }
        .navigationTitle("外观皮肤")
    }
}

struct ShortcutSettingsView: View {
    var body: some View {
        ContentUnavailableView("快捷键管理开发中",
                               systemImage: "command",
                               description: Text("这里将支持录制 F4 / Control+grave 等热键"))
            .navigationTitle("快捷键")
    }
}

struct AppSettingsView: View {
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("应用特定设置")
                .font(.title2)
                .bold()

            if manager.appOptions.isEmpty {
                Text("尚未发现 `app_options` 配置，稍后会提供添加按钮。")
                    .foregroundStyle(.secondary)
            } else {
                Table(manager.appOptions) {
                    TableColumn("Bundle ID") { option in
                        Text(option.bundleID)
                    }
                    TableColumn("默认英文") { option in
                        Toggle("", isOn: .constant(option.asciiMode))
                            .labelsHidden()
                            .disabled(true)
                    }
                }
                .frame(minHeight: 240)
            }

            Spacer()
        }
        .padding(32)
        .navigationTitle("应用设置")
    }
}

struct AdvancedSettingsView: View {
    var reloadAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("高级功能")
                .font(.title2)
                .bold()
            Text("未来这里会提供 patch 对比、YAML 编辑器、以及手动触发 Deploy 的能力。")
                .foregroundStyle(.secondary)

            HStack {
                Button("重新读取配置", action: reloadAction)
                Button("Deploy", action: {})
                    .disabled(true)
            }

            Spacer()
        }
        .padding(32)
        .navigationTitle("高级设置")
    }
}

struct CandidatePreview: View {
    var colorSchemeName: String
    var fontFace: String
    var fontSize: CGFloat

    private let mockCandidates = ["候选 1", "候选 2", "候选 3", "候选 4"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("皮肤：\(colorSchemeName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(Array(mockCandidates.enumerated()), id: \.offset) { index, candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1)")
                            .font(.system(size: fontSize * 0.55, weight: .medium))
                            .foregroundStyle(index == 0 ? .black : .gray)
                        Text(candidate)
                            .font(.custom(fontFace.isEmpty ? "Avenir" : fontFace, size: fontSize))
                            .foregroundStyle(index == 0 ? .black : .white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(index == 0 ? Color(.sRGB, red: 0.92, green: 0.92, blue: 0.92, opacity: 1)
                                          : Color(.sRGB, red: 0.2, green: 0.2, blue: 0.2, opacity: 1))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 4)
        }
    }
}

struct StatusBarView: View {
    var status: String

    var body: some View {
        Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}

#Preview {
    ContentView()
}
