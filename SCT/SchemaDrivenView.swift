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
                SchemaSectionListView(sections: filteredSections, manager: manager)
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
    }
}

private struct SchemaSectionListView: View {
    let sections: [SchemaSection]
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(sections) { section in
                    SchemaSectionCard(section: section, manager: manager)
                }
            }
            .padding(24)
        }
    }
}

private struct SchemaSectionCard: View {
    let section: SchemaSection
    @ObservedObject var manager: RimeConfigManager

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
                    SchemaFieldRow(field: field, section: section, manager: manager)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(field.label)
                    .fontWeight(.semibold)
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
                get: { rawValue as? Int ?? Int(field.defaultInt) },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            ), in: field.minInt...field.maxInt) {
                Text("\(rawValue as? Int ?? Int(field.defaultInt))")
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
            Picker("", selection: Binding(
                get: { rawValue as? String ?? field.choices?.first ?? "" },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            )) {
                ForEach(field.choices ?? [], id: \.self) { choice in
                    Text(choice).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

        case .segmented:
            Picker("", selection: Binding(
                get: { rawValue as? String ?? field.choices?.first ?? "" },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            )) {
                ForEach(field.choices ?? [], id: \.self) { choice in
                    Text(choice).tag(choice)
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
            Slider(value: $localValue,
                   in: (field.min ?? 0)...(field.max ?? 1),
                   step: field.step ?? 0.01)
            Text(String(format: "%.2f", localValue))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44)
        }
        .frame(maxWidth: 200)
        .onAppear {
            localValue = manager.value(for: field.keyPath, in: domain) as? Double ?? field.min ?? 0
        }
        .onChange(of: localValue) { _, newValue in
            manager.updateValue(newValue, for: field.keyPath, in: domain)
        }
        // Sync back if manager changes externally
        .onChange(of: manager.value(for: field.keyPath, in: domain) as? Double) { _, newValue in
            if let nv = newValue, nv != localValue {
                localValue = nv
            }
        }
    }
}

extension SchemaField {
    var minInt: Int { Int(min ?? 0) }
    var maxInt: Int { Int(max ?? 100) }
    var defaultInt: Int { 0 } // Could be added to JSON
}

enum SchemaValueFormatter {
    static func string(from value: Any) -> String {
        switch value {
        case let bool as Bool:
            return bool ? "开启" : "关闭"
        case let int as Int:
            return String(int)
        case let double as Double:
            return double.cleanString
        case let string as String:
            return string
        case let array as [Any]:
            return array.map { string(from: $0) }.joined(separator: ", ")
        case let dict as [String: Any]:
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return dict.description
        default:
            return String(describing: value)
        }
    }
}

private extension Double {
    var cleanString: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}
