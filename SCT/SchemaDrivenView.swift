import SwiftUI

struct SchemaDrivenView: View {
    @ObservedObject var schemaStore: SchemaStore
    @ObservedObject var manager: RimeConfigManager
    let sectionIDs: [String]?
    let title: String?

    init(schemaStore: SchemaStore, manager: RimeConfigManager, sectionIDs: [String]? = nil, title: String? = nil) {
        self.schemaStore = schemaStore
        self.manager = manager
        self.sectionIDs = sectionIDs
        self.title = title
    }

    var body: some View {
        Group {
            if let schema = schemaStore.schema {
                let filteredSections = sectionIDs == nil ? schema.sections : schema.sections.filter { sectionIDs!.contains($0.id) }
                SchemaSectionListView(sections: filteredSections, manager: manager, schemaStore: schemaStore)
            } else if let error = schemaStore.errorMessage {
                ContentUnavailableView("无法加载 Schema",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                ProgressView("正在加载 Schema...")
                    .padding()
            }
        }
        .navigationTitle(title ?? "Schema 驱动预览")
        .rimeToolbar(manager: manager)
    }
}

private struct SchemaSectionListView: View {
    let sections: [SchemaSection]
    @ObservedObject var manager: RimeConfigManager
    @ObservedObject var schemaStore: SchemaStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(sections) { section in
                    SchemaSectionCard(section: section, manager: manager, schemaStore: schemaStore)
                }
            }
            .padding(24)
        }
    }
}

private struct SchemaSectionCard: View {
    let section: SchemaSection
    @ObservedObject var manager: RimeConfigManager
    @ObservedObject var schemaStore: SchemaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: section.icon ?? "square.on.square")
                    .foregroundStyle(Color.accentColor)
                Text(section.title)
                    .font(.headline)
                Spacer()
                Text(section.targetFile)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                ForEach(section.fields) { field in
                    SchemaFieldRow(field: field, section: section, manager: manager, schemaStore: schemaStore)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SchemaFieldRow: View {
    let field: SchemaField
    let section: SchemaSection
    @ObservedObject var manager: RimeConfigManager
    @ObservedObject var schemaStore: SchemaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(field.label)
                    .fontWeight(.semibold)
                    .padding(.top, 4)
                Spacer()
                controlView
            }
        }
    }

    @ViewBuilder
    private var controlView: some View {
        let domain = RimeConfigManager.ConfigDomain(rawValue: section.targetFile) ?? .default
        let rawValue = manager.value(for: field.keyPath, in: domain)

        switch field.type {
        case .toggle:
            Toggle("", isOn: Binding(
                get: { rawValue as? Bool ?? false },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            ))
            .labelsHidden()

        case .stepper:
            Stepper(value: Binding(
                get: { manager.intValue(for: field.keyPath, in: domain) ?? Int(field.defaultInt) },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            ), in: field.minInt...field.maxInt) {
                Text("\(manager.intValue(for: field.keyPath, in: domain) ?? Int(field.defaultInt))")
                    .monospacedDigit()
            }

        case .text:
            TextField(field.label, text: Binding(
                get: { rawValue as? String ?? "" },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 200)

        case .enumeration:
            let choices = manager.resolveChoices(for: field)
            Picker("", selection: Binding(
                get: { rawValue as? String ?? choices.first ?? "" },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            )) {
                if rawValue == nil {
                    Text("未设置").tag("")
                }
                ForEach(choices, id: \.self) { choice in
                    Text(manager.choiceLabel(for: field, choice: choice)).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

        case .segmented:
            let choices = manager.resolveChoices(for: field)
            Picker("", selection: Binding(
                get: { rawValue as? String ?? choices.first ?? "" },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            )) {
                ForEach(choices, id: \.self) { choice in
                    Text(manager.choiceLabel(for: field, choice: choice)).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

        case .slider:
            SliderControl(field: field, domain: domain, manager: manager)

        case .colorBGR:
            if let bgrString = rawValue as? String {
                ColorPicker("", selection: Binding(
                    get: { Color(bgrHex: bgrString) ?? .black },
                    set: { if let hex = $0.bgrHexString() { manager.updateValue(hex, for: field.keyPath, in: domain) } }
                ))
                .labelsHidden()
            } else {
                Text("无效颜色")
                    .foregroundStyle(.secondary)
            }

        case .fontPicker:
            let fonts = schemaStore.availableFonts
            Picker("", selection: Binding(
                get: { rawValue as? String ?? "Avenir" },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            )) {
                if fonts.isEmpty {
                    Text("正在加载字体...").tag("Avenir")
                } else {
                    ForEach(fonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 200)

        case .multiSelect:
            MultiSelectControl(field: field, domain: domain, manager: manager)

        case .schemaList:
            SchemaListControl(field: field, domain: domain, manager: manager)

        case .appOptions:
            AppOptionsControl(field: field, domain: domain, manager: manager)

        case .keyBinder:
            KeyBinderControl(field: field, domain: domain, manager: manager)

        case .keyMapping:
            KeyMappingControl(field: field, domain: domain, manager: manager)

        case .hotkeyList:
            HotkeyListControl(field: field, domain: domain, manager: manager)

        default:
            Text(SchemaValueFormatter.string(from: rawValue ?? "—"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct SliderControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    @State private var localValue: Double = 0

    var body: some View {
        HStack {
            Slider(value: Binding(
                get: { localValue },
                set: { newValue in
                    let step = field.step ?? 0.05
                    localValue = (newValue / step).rounded() * step
                }
            ), in: (field.min ?? 0)...(field.max ?? 1))
            Text(String(format: "%.2f", localValue))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44)
        }
        .frame(maxWidth: 200)
        .onAppear {
            localValue = manager.doubleValue(for: field.keyPath, in: domain) ?? field.min ?? 0
        }
        .onChange(of: localValue) { _, newValue in
            manager.updateValue(newValue, for: field.keyPath, in: domain)
        }
        // Sync back if manager changes externally
        .onChange(of: manager.doubleValue(for: field.keyPath, in: domain)) { _, newValue in
            if let nv = newValue, nv != localValue {
                localValue = nv
            }
        }
    }
}

struct MultiSelectControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        let currentValues = manager.value(for: field.keyPath, in: domain) as? [String] ?? []
        let choices = manager.resolveChoices(for: field)

        VStack(alignment: .leading, spacing: 6) {
            ForEach(choices, id: \.self) { choice in
                HStack {
                    Spacer()
                    Text(manager.choiceLabel(for: field, choice: choice))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: Binding(
                        get: { currentValues.contains(choice) },
                        set: { isSelected in
                            var newValues = currentValues
                            if isSelected {
                                if !newValues.contains(choice) {
                                    newValues.append(choice)
                                }
                            } else {
                                newValues.removeAll { $0 == choice }
                            }
                            manager.updateValue(newValues, for: field.keyPath, in: domain)
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
            }
        }
        .frame(maxWidth: 220)
    }
}

struct SchemaListControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        let availableSchemas = manager.availableSchemas
        let selectedSchemaIDs = (manager.mergedConfig(for: domain)[field.keyPath] as? [[String: Any]])?
            .compactMap { $0["schema"] as? String } ?? []

        VStack(alignment: .leading, spacing: 8) {
            ForEach(availableSchemas, id: \.id) { schema in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(schema.name)
                            .font(.body)
                        Text(schema.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { selectedSchemaIDs.contains(schema.id) },
                        set: { isSelected in
                            var currentList = (manager.mergedConfig(for: domain)[field.keyPath] as? [[String: Any]]) ?? []
                            if isSelected {
                                if !currentList.contains(where: { ($0["schema"] as? String) == schema.id }) {
                                    currentList.append(["schema": schema.id])
                                }
                            } else {
                                currentList.removeAll { ($0["schema"] as? String) == schema.id }
                            }
                            manager.updateValue(currentList, for: field.keyPath, in: domain)
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: 300)
    }
}

struct AppOptionsControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    @State private var newBundleID: String = ""

    var body: some View {
        let options = (manager.mergedConfig(for: domain)[field.keyPath] as? [String: [String: Any]]) ?? [:]
        let sortedKeys = options.keys.sorted()

        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Bundle ID").frame(width: 150, alignment: .leading)
                Text("ASCII").frame(width: 50)
                Text("Inline").frame(width: 50)
                Text("NoInline").frame(width: 60)
                Text("Vim").frame(width: 40)
                Spacer()
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            ForEach(sortedKeys, id: \.self) { bundleID in
                HStack {
                    Text(bundleID)
                        .frame(width: 150, alignment: .leading)
                        .font(.system(.body, design: .monospaced))

                    flagToggle(bundleID: bundleID, flag: "ascii_mode").frame(width: 50)
                    flagToggle(bundleID: bundleID, flag: "inline").frame(width: 50)
                    flagToggle(bundleID: bundleID, flag: "no_inline").frame(width: 60)
                    flagToggle(bundleID: bundleID, flag: "vim_mode").frame(width: 40)

                    Spacer()

                    Button(role: .destructive) {
                        var currentOptions = options
                        currentOptions.removeValue(forKey: bundleID)
                        manager.updateValue(currentOptions, for: field.keyPath, in: domain)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            Divider()

            HStack {
                TextField("添加 Bundle ID (如 com.apple.Terminal)", text: $newBundleID)
                    .textFieldStyle(.roundedBorder)

                Button("添加") {
                    guard !newBundleID.isEmpty else { return }
                    var currentOptions = options
                    if currentOptions[newBundleID] == nil {
                        currentOptions[newBundleID] = [:]
                        manager.updateValue(currentOptions, for: field.keyPath, in: domain)
                    }
                    newBundleID = ""
                }
                .disabled(newBundleID.isEmpty)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    @ViewBuilder
    private func flagToggle(bundleID: String, flag: String) -> some View {
        let options = (manager.mergedConfig(for: domain)[field.keyPath] as? [String: [String: Any]]) ?? [:]
        let flags = options[bundleID] ?? [:]
        let isOn = flags[flag] as? Bool ?? false

        Toggle("", isOn: Binding(
            get: { isOn },
            set: { newValue in
                var currentOptions = options
                var currentFlags = currentOptions[bundleID] ?? [:]
                if newValue {
                    currentFlags[flag] = true
                } else {
                    currentFlags.removeValue(forKey: flag)
                }
                currentOptions[bundleID] = currentFlags
                manager.updateValue(currentOptions, for: field.keyPath, in: domain)
            }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
    }
}

struct KeyBinderControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        let bindings = (manager.mergedConfig(for: domain)[field.keyPath] as? [[String: Any]]) ?? []

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("When").frame(width: 80, alignment: .leading)
                Text("Accept").frame(width: 100, alignment: .leading)
                Text("Send/Toggle").frame(width: 120, alignment: .leading)
                Spacer()
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            ForEach(0..<bindings.count, id: \.self) { index in
                let binding = bindings[index]
                HStack {
                    Text(binding["when"] as? String ?? "always")
                        .frame(width: 80, alignment: .leading)
                    Text(binding["accept"] as? String ?? "")
                        .frame(width: 100, alignment: .leading)
                    Text((binding["send"] as? String) ?? (binding["toggle"] as? String) ?? "")
                        .frame(width: 120, alignment: .leading)

                    Spacer()

                    Button(role: .destructive) {
                        var currentBindings = bindings
                        currentBindings.remove(at: index)
                        manager.updateValue(currentBindings, for: field.keyPath, in: domain)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }
}

struct KeyMappingControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        let mapping = (manager.mergedConfig(for: domain)[field.keyPath] as? [String: String]) ?? [:]
        let keys = field.keys ?? []
        let choices = field.choices ?? []

        VStack(alignment: .leading, spacing: 8) {
            ForEach(keys, id: \.self) { key in
                HStack {
                    Text(key)
                        .frame(width: 100, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { mapping[key] ?? "noop" },
                        set: { newValue in
                            var currentMapping = mapping
                            currentMapping[key] = newValue
                            manager.updateValue(currentMapping, for: field.keyPath, in: domain)
                        }
                    )) {
                        ForEach(choices, id: \.self) { choice in
                            Text(choice).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 150)
                }
            }
        }
    }
}

struct HotkeyListControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    @State private var newHotkey: String = ""

    var body: some View {
        let hotkeys = (manager.mergedConfig(for: domain)[field.keyPath] as? [String]) ?? []

        VStack(alignment: .leading, spacing: 8) {
            ForEach(hotkeys, id: \.self) { hotkey in
                HStack {
                    Text(hotkey)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button(role: .destructive) {
                        var currentHotkeys = hotkeys
                        currentHotkeys.removeAll { $0 == hotkey }
                        manager.updateValue(currentHotkeys, for: field.keyPath, in: domain)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            HStack {
                TextField("添加快捷键 (如 Control+grave)", text: $newHotkey)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    guard !newHotkey.isEmpty else { return }
                    var currentHotkeys = hotkeys
                    if !currentHotkeys.contains(newHotkey) {
                        currentHotkeys.append(newHotkey)
                        manager.updateValue(currentHotkeys, for: field.keyPath, in: domain)
                    }
                    newHotkey = ""
                }
                .disabled(newHotkey.isEmpty)
            }
        }
        .frame(maxWidth: 300)
    }
}

extension SchemaField {
    var minInt: Int { Int(min ?? 0) }
    var maxInt: Int { Int(max ?? 100) }
    var defaultInt: Int { 0 } // Could be added to JSON
}
