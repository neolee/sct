import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var manager: RimeConfigManager
    @State private var searchText = ""
    @State private var showCustomizedOnly = false
    @State private var selectedDomain: RimeConfigManager.ConfigDomain = .default
    @State private var showSourceEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Header / Controls
            HStack {
                Picker("配置文件", selection: $selectedDomain) {
                    Text("default.yaml").tag(RimeConfigManager.ConfigDomain.default)
                    Text("squirrel.yaml").tag(RimeConfigManager.ConfigDomain.squirrel)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Spacer()

                Button(action: { showSourceEditor = true }) {
                    Label("源码编辑", systemImage: "code.square")
                }
                .buttonStyle(.bordered)

                Toggle("仅显示已修改", isOn: $showCustomizedOnly)
                    .toggleStyle(.checkbox)
            }
            .padding()
            .background(.ultraThinMaterial)

            // Key-Value List
            List {
                let merged = manager.mergedConfigs[selectedDomain] ?? [:]
                let patch = manager.patchConfigs[selectedDomain] ?? [:]
                let allKeys = getAllKeys(from: merged).sorted()

                let filteredKeys = allKeys.filter { key in
                    let matchesSearch = searchText.isEmpty || key.localizedCaseInsensitiveContains(searchText)
                    let isCustomized = patch[key] != nil
                    return matchesSearch && (!showCustomizedOnly || isCustomized)
                }

                ForEach(filteredKeys, id: \.self) { key in
                    let isCustomized = patch[key] != nil
                    let value = getValue(for: key, from: merged)

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(key)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(isCustomized ? .bold : .regular)

                                if isCustomized {
                                    Text("已修改")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(4)
                                }
                            }

                            Text(SchemaValueFormatter.string(from: value ?? "—"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        if isCustomized {
                            Button("还原") {
                                manager.removePatch(for: key, in: selectedDomain)
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .searchable(text: $searchText, placement: .automatic, prompt: "搜索键名...")
        .navigationTitle("高级设置")
        .rimeToolbar(manager: manager)
        .sheet(isPresented: $showSourceEditor) {
            SourceCodeEditorView(domain: selectedDomain, manager: manager)
        }
    }

    private func getAllKeys(from dict: [String: Any], prefix: String = "") -> [String] {
        var keys: [String] = []
        for (key, value) in dict {
            let fullKey = prefix.isEmpty ? key : "\(prefix)/\(key)"
            if let subDict = value as? [String: Any] {
                keys.append(contentsOf: getAllKeys(from: subDict, prefix: fullKey))
            } else {
                keys.append(fullKey)
            }
        }
        return keys
    }

    private func getValue(for keyPath: String, from dict: [String: Any]) -> Any? {
        let components = keyPath.split(separator: "/")
        var current: Any? = dict
        for component in components {
            if let d = current as? [String: Any] {
                current = d[String(component)]
            } else {
                return nil
            }
        }
        return current
    }
}

struct SourceCodeEditorView: View {
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager
    @Environment(\.dismiss) var dismiss

    @State private var content: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .padding(4)

                Divider()

                HStack {
                    Text("直接编辑 \(domain.rawValue).custom.yaml")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") {
                        dismiss()
                    }
                    Button("保存") {
                        manager.saveRawYaml(content, for: domain)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("源码编辑")
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            content = manager.loadRawYaml(for: domain)
        }
    }
}
