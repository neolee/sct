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

    private var saveTasks: [String: Task<Void, Never>] = [:]
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

    /// Triggers Squirrel to reload its configuration.
    func deploy() {
        let squirrelAppPath = "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: squirrelAppPath)
        process.arguments = ["--reload"]

        do {
            try process.run()
            statusMessage = "已触发重新部署"
        } catch {
            // Fallback: touch the config files if the app is not found or fails
            statusMessage = "部署失败，尝试更新文件时间戳..."
            touchConfigFiles()
        }
    }

    private func touchConfigFiles() {
        let files = ["default.custom.yaml", "squirrel.custom.yaml"]
        for fileName in files {
            let fileURL = rimePath.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            }
        }
        statusMessage = "已更新文件时间戳"
    }

    func value(for keyPath: String, in domain: ConfigDomain) -> Any? {
        guard let dictionary = mergedConfigs[domain] else { return nil }
        return value(in: dictionary, keyPath: keyPath)
    }

    func doubleValue(for keyPath: String, in domain: ConfigDomain) -> Double? {
        asDouble(value(for: keyPath, in: domain))
    }

    func intValue(for keyPath: String, in domain: ConfigDomain) -> Int? {
        asInt(value(for: keyPath, in: domain))
    }

    func updateValue(_ value: Any, for keyPath: String, in domain: ConfigDomain) {
        var finalValue = value

        // Handle Double to ensure clean YAML output without scientific notation
        if let doubleValue = value as? Double {
            // Using Decimal with a fixed locale to ensure consistent string conversion
            let rounded = (doubleValue * 10000).rounded() / 10000
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.maximumFractionDigits = 4
            formatter.numberStyle = .decimal
            if let formattedString = formatter.string(from: NSNumber(value: rounded)),
               let decimal = Decimal(string: formattedString, locale: Locale(identifier: "en_US")) {
                finalValue = decimal
            } else {
                finalValue = rounded
            }
        }

        // 1. Update mergedConfigs for immediate UI update
        var merged = mergedConfigs[domain] ?? [:]
        let components = keyPath.split(separator: "/").map(String.init)
        updateInMemoryValue(finalValue, for: components[...], in: &merged)
        mergedConfigs[domain] = merged

        // 2. Sync @Published properties
        applyMergedValues()

        // 3. Save to .custom.yaml (Debounced)
        let taskKey = "\(domain.rawValue)/\(keyPath)"
        saveTasks[taskKey]?.cancel()
        saveTasks[taskKey] = Task {
            // Small delay to batch rapid updates (like sliders)
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            if !Task.isCancelled {
                saveToPatch(finalValue, for: keyPath, in: domain)
            }
        }
    }

    private func updateInMemoryValue(_ value: Any, for components: ArraySlice<String>, in dictionary: inout [String: Any]) {
        guard let head = components.first else { return }
        if components.count == 1 {
            dictionary[head] = value
            return
        }
        var child = dictionary[head] as? [String: Any] ?? [:]
        updateInMemoryValue(value, for: components.dropFirst(), in: &child)
        dictionary[head] = child
    }

    private func saveToPatch(_ value: Any, for keyPath: String, in domain: ConfigDomain) {
        let fileName = domain == .default ? "default.custom.yaml" : "squirrel.custom.yaml"
        let url = rimePath.appendingPathComponent(fileName)

        var root: [String: Any] = [:]
        if fileManager.fileExists(atPath: url.path),
           let contents = try? String(contentsOf: url, encoding: .utf8),
           let existingRoot = try? Yams.load(yaml: contents) as? [String: Any] {
            root = existingRoot
        }

        var patch = root["patch"] as? [String: Any] ?? [:]
        
        // Use flat keys (e.g., "style/font_face") instead of nested structures.
        // This is the most robust way to patch Rime configs without overwriting sibling keys.
        patch[keyPath] = value
        root["patch"] = patch

        do {
            // width: -1 prevents unnecessary line breaks in long strings
            // allowUnicode: true ensures Chinese characters are not escaped
            let yaml = try Yams.dump(object: root, width: -1, allowUnicode: true)
            try yaml.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            statusMessage = "已保存到 \(fileName)"
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
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

            if let menu = mergedDefault["menu"] as? [String: Any] {
                if let size = asInt(menu["page_size"]) {
                    pageSize = size
                }
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

                if let fp = asInt(style["font_point"]) {
                    fontPoint = fp
                }
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

    private func asDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let dec = value as? Decimal { return NSDecimalNumber(decimal: dec).doubleValue }
        return nil
    }

    private func asInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let dec = value as? Decimal { return NSDecimalNumber(decimal: dec).intValue }
        return nil
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
                let normalizedValue = normalizeValue(value)
                if let dictValue = normalizedValue as? [String: Any],
                   let existingDict = normalized[key] as? [String: Any] {
                    normalized[key] = mergedDictionary(base: existingDict, patch: dictValue)
                } else {
                    normalized[key] = normalizedValue
                }
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
