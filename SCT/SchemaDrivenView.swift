import SwiftUI

struct SchemaDrivenView: View {
    @ObservedObject var schemaStore: SchemaStore
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        Group {
            if let schema = schemaStore.schema {
                SchemaSectionListView(sections: schema.sections) { section, field in
                    displayValue(for: field, in: section)
                }
            } else if let error = schemaStore.errorMessage {
                ContentUnavailableView("无法加载 Schema",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                ProgressView("正在加载 Schema...")
                    .padding()
            }
        }
        .navigationTitle("Schema 驱动预览")
    }

    private func displayValue(for field: SchemaField, in section: SchemaSection) -> String {
        guard let domain = RimeConfigManager.ConfigDomain(rawValue: section.targetFile),
              let rawValue = manager.value(for: field.keyPath, in: domain) else {
            return "—"
        }
        return SchemaValueFormatter.string(from: rawValue)
    }
}

private struct SchemaSectionListView: View {
    let sections: [SchemaSection]
    let valueProvider: (SchemaSection, SchemaField) -> String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(sections) { section in
                    SchemaSectionCard(section: section) { field in
                        valueProvider(section, field)
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct SchemaSectionCard: View {
    let section: SchemaSection
    let valueProvider: (SchemaField) -> String

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

            VStack(alignment: .leading, spacing: 12) {
                ForEach(section.fields) { field in
                    SchemaFieldRow(field: field,
                                   valueDescription: valueProvider(field))
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SchemaFieldRow: View {
    let field: SchemaField
    let valueDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.label)
                    .fontWeight(.semibold)
                Spacer()
                Text(field.type.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(valueDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
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
