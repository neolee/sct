//
//  ContentView.swift
//  SCT
//
//  Created by Neo on 2025/12/18.
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case schemes
    case panel
    case behaviors
    case apps
    case advanced
    case prototype
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .schemes: return "输入方案"
        case .panel: return "候选词面板"
        case .behaviors: return "输入行为"
        case .apps: return "应用设置"
        case .advanced: return "高级设置"
        case .prototype: return "Schema 驱动预览"
        }
    }
    
    var icon: String {
        switch self {
        case .schemes: return "list.bullet.indent"
        case .panel: return "list.number"
        case .behaviors: return "keyboard"
        case .apps: return "apps.ipad"
        case .advanced: return "gearshape.2"
        case .prototype: return "testtube.2"
        }
    }
}

struct ContentView: View {
    @StateObject private var manager = RimeConfigManager()
    @StateObject private var schemaStore = SchemaStore()
    @State private var selection: SidebarItem? = .schemes
    
    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.icon)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Squirrel 配置")
        } detail: {
            if let item = selection {
                detailView(for: item)
            } else {
                Text("请选择一个项目")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .overlay(alignment: .bottomLeading) {
            StatusBarView(status: manager.statusMessage)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .task {
            manager.reload()
            schemaStore.loadSchema()
        }
    }
    
    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
        switch item {
        case .schemes:
            SchemaDrivenView(schemaStore: schemaStore, manager: manager, sectionIDs: ["schemes.list", "switcher"], title: item.title)
        case .panel:
            SchemaDrivenView(schemaStore: schemaStore, manager: manager, sectionIDs: ["panel.menu", "style"], title: item.title)
        case .behaviors:
            SchemaDrivenView(schemaStore: schemaStore, manager: manager, sectionIDs: ["asciiComposer", "keyBinder"], title: item.title)
        case .apps:
            SchemaDrivenView(schemaStore: schemaStore, manager: manager, sectionIDs: ["appOptions"], title: item.title)
        case .advanced:
            AdvancedSettingsView(manager: manager)
        case .prototype:
            SchemaDrivenView(schemaStore: schemaStore, manager: manager)
        }
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject var manager: RimeConfigManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("高级设置")
                .font(.title)
            
            Text("此处将提供 YAML 编辑器和部署功能。")
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                Button(action: {
                    manager.reload()
                }) {
                    Label("重新加载", systemImage: "arrow.clockwise")
                }
                
                Button(action: {
                    // manager.deploy() // If deploy is implemented
                }) {
                    Label("部署更改", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .navigationTitle("高级设置")
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
