import Foundation
import Combine

// MARK: - Schema Models

struct ConfigSchema: Decodable {
    let version: Int
    let meta: SchemaMeta?
    let sections: [SchemaSection]
    let itemSchemas: [String: [SchemaItemField]]?
}

struct SchemaMeta: Decodable {
    let description: String?
    let targetFiles: [String: String]?
}

struct SchemaSection: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String?
    let targetFile: String
    let fields: [SchemaField]
}

struct SchemaField: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let type: SchemaFieldType
    let keyPath: String
    let itemKey: String?
    let allowReorder: Bool?
    let allowToggle: Bool?
    let dataSource: SchemaFieldDataSource?
    let min: Double?
    let max: Double?
    let step: Double?
    let choices: [String]?
    let choicesRef: String?
    let delimiter: String?
    let optional: Bool?
    let columns: [SchemaTableColumn]?
    let keys: [String]?
    let itemSchema: String?
}

struct SchemaFieldDataSource: Decodable, Hashable {
    let file: String
    let keyPath: String
}

struct SchemaTableColumn: Decodable, Hashable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let type: String
    let isKey: Bool?
    let optional: Bool?
}

struct SchemaItemField: Decodable, Hashable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let type: SchemaFieldType
    let choices: [String]?
    let optional: Bool?
    let min: Double?
    let max: Double?
    let step: Double?
}

enum SchemaFieldType: String, Decodable {
    case schemaList
    case stepper
    case text
    case hotkeyList
    case multiSelect
    case toggle
    case enumeration = "enum"
    case chipList
    case mapping
    case regexTable
    case keyPicker
    case bindingTable
    case segmented
    case fontPicker
    case slider
    case table
    case collection
    case keyMapping
    case colorBGR
}

// MARK: - Store

final class SchemaStore: ObservableObject {
    @Published var schema: ConfigSchema?
    @Published var errorMessage: String?

    init() {
        loadSchema()
    }

    private func loadSchema() {
        if let bundleURL = Bundle.main.url(forResource: "ConfigSchema", withExtension: "json") {
            loadSchema(from: bundleURL)
            return
        }

        if let devURL = developmentSchemaURL() {
            loadSchema(from: devURL)
            return
        }

        errorMessage = "ConfigSchema.json 未找到"
    }

    private func loadSchema(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            schema = try decoder.decode(ConfigSchema.self, from: data)
        } catch {
            errorMessage = "Schema 解析失败：\(error.localizedDescription)"
        }
    }

    private func developmentSchemaURL() -> URL? {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidate = current.appendingPathComponent("SCT/ConfigSchema.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }
}
