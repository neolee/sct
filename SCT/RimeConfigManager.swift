import Foundation
import Combine
import Yams

/// A lightweight configuration loader that reads the available `.custom.yaml` patches.
/// The goal for now is to exercise the Yams dependency and provide data for the prototype UI.
final class RimeConfigManager: ObservableObject {
    enum ConfigDomain: String {
        case `default`
        case squirrel
    }

    struct AppOption: Identifiable {
        let id = UUID()
        let bundleID: String
        let asciiMode: Bool
    }

    @Published var schemaList: [String] = ["正在读取..."]
    @Published var pageSize: Int = 5
    @Published var colorScheme: String = "purity_of_form_custom"
    @Published var fontFace: String = "Avenir"
    @Published var fontPoint: Int = 16
    @Published var appOptions: [AppOption] = []
    @Published var statusMessage: String = "正在读取配置..."
    @Published private(set) var mergedConfigs: [ConfigDomain: [String: Any]] = [:]

    private let rimePath: URL
    private let fileManager = FileManager.default

    private static let fallbackYAML = """
    menu:
      page_size: 9
    schema_list:
      - schema: rime_ice
      - schema: double_pinyin
      - schema: t9
    style:
      color_scheme: dark_temple
      font_face: "Sarasa UI SC"
      font_point: 16
    app_options:
      com.apple.Terminal:
        ascii_mode: true
      com.apple.dt.Xcode:
        ascii_mode: true
    """

    init(rimePath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Rime", isDirectory: true)) {
        self.rimePath = rimePath
        loadConfig()
    }

    func loadConfig() {
        let hasDefaultFiles = fileExists(named: "default.yaml") || fileExists(named: "default.custom.yaml")
        let hasSquirrelFiles = fileExists(named: "squirrel.yaml") || fileExists(named: "squirrel.custom.yaml")

        guard hasDefaultFiles || hasSquirrelFiles else {
            applyFallbackSnapshot()
            statusMessage = "使用示例配置"
            return
        }

        let defaultBase = loadYamlDictionary(named: "default.yaml")
        let defaultPatch = loadPatchDictionary(named: "default.custom.yaml")
        mergedConfigs[.default] = mergedDictionary(base: defaultBase, patch: defaultPatch)

        let squirrelBase = loadYamlDictionary(named: "squirrel.yaml")
        let squirrelPatch = loadPatchDictionary(named: "squirrel.custom.yaml")
        mergedConfigs[.squirrel] = mergedDictionary(base: squirrelBase, patch: squirrelPatch)

        applyMergedValues()
        statusMessage = "已读取 \(rimePath.path)"
    }

    func reload() {
        loadConfig()
    }

    func value(for keyPath: String, in domain: ConfigDomain) -> Any? {
        guard let dictionary = mergedConfigs[domain] else { return nil }
        return value(in: dictionary, keyPath: keyPath)
    }

    private func loadPatchDictionary(named fileName: String) -> [String: Any] {
        let url = rimePath.appendingPathComponent(fileName)
          guard fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8),
              let root = try? Yams.load(yaml: contents) as? [String: Any],
              let patch = root["patch"] as? [String: Any] else {
            return [:]
        }
          return normalizeRimeDictionary(patch)
    }

    private func loadYamlDictionary(named fileName: String) -> [String: Any] {
        let url = rimePath.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8),
              let root = try? Yams.load(yaml: contents) as? [String: Any] else {
            return [:]
        }
          return normalizeRimeDictionary(root)
    }

    private func mergedDictionary(base: [String: Any], patch: [String: Any]) -> [String: Any] {
        guard !patch.isEmpty else { return base }
        var result = base
        for (key, value) in patch {
            if let patchDict = value as? [String: Any], let baseDict = result[key] as? [String: Any] {
                result[key] = mergedDictionary(base: baseDict, patch: patchDict)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private func value(in dictionary: [String: Any], keyPath: String) -> Any? {
        var current: Any? = dictionary
        for component in keyPath.split(separator: "/") {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[String(component)]
        }
        return current
    }

    private func fileExists(named fileName: String) -> Bool {
        let url = rimePath.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path)
    }

    private func applyMergedValues() {
        if let mergedDefault = mergedConfigs[.default] {
            if let schemas = mergedDefault["schema_list"] as? [[String: Any]] {
                schemaList = schemas.compactMap { $0["schema"] as? String }
            } else {
                schemaList = []
            }

            if let menu = mergedDefault["menu"] as? [String: Any],
               let size = menu["page_size"] as? Int {
                pageSize = size
            } else {
                pageSize = 5
            }
        } else {
            schemaList = []
            pageSize = 5
        }

        if let mergedSquirrel = mergedConfigs[.squirrel] {
            if let style = mergedSquirrel["style"] as? [String: Any] {
                colorScheme = style["color_scheme"] as? String ?? colorScheme
                fontFace = style["font_face"] as? String ?? fontFace
                fontPoint = style["font_point"] as? Int ?? fontPoint
            }

            if let apps = mergedSquirrel["app_options"] as? [String: Any] {
                appOptions = apps.compactMap { key, value in
                    guard let dict = value as? [String: Any] else { return nil }
                    let ascii = dict["ascii_mode"] as? Bool ?? false
                    return AppOption(bundleID: key, asciiMode: ascii)
                }
                .sorted { $0.bundleID < $1.bundleID }
            } else {
                appOptions = []
            }
        } else {
            appOptions = []
        }
    }

    private func applyFallbackSnapshot() {
        guard
            let root = try? Yams.load(yaml: Self.fallbackYAML),
            let dictRaw = root as? [String: Any]
        else {
            schemaList = ["rime_ice"]
            mergedConfigs = [:]
            return
        }

        let dict = normalizeRimeDictionary(dictRaw)

        mergedConfigs[.default] = dict
        mergedConfigs[.squirrel] = dict
        applyMergedValues()
    }

    // MARK: - Dictionary Normalization

    private func normalizeRimeDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        var normalized: [String: Any] = [:]
        for (key, value) in dictionary {
            if key.contains("/") {
                let components = key.split(separator: "/").map(String.init)
                insert(value: value, for: components[...], into: &normalized)
            } else {
                normalized[key] = normalizeValue(value)
            }
        }
        return normalized
    }

    private func insert(value: Any, for components: ArraySlice<String>, into dictionary: inout [String: Any]) {
        guard let head = components.first else { return }
        if components.count == 1 {
            dictionary[head] = normalizeValue(value)
            return
        }

        var child = dictionary[head] as? [String: Any] ?? [:]
        insert(value: value, for: components.dropFirst(), into: &child)
        dictionary[head] = child
    }

    private func normalizeValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return normalizeRimeDictionary(dict)
        }
        if let array = value as? [[String: Any]] {
            return array.map { normalizeRimeDictionary($0) }
        }
        if let array = value as? [Any] {
            let dicts = array.compactMap { $0 as? [String: Any] }
            if dicts.count == array.count {
                return dicts.map { normalizeRimeDictionary($0) }
            }
        }
        return value
    }
}
