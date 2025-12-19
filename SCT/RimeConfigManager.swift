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

    struct RimeSchema: Identifiable, Hashable {
        var id: String { schemaID }
        let schemaID: String
        let name: String
        let isBuiltIn: Bool
    }

    @Published var schemaList: [String] = ["正在读取..."]
    @Published var availableSchemas: [RimeSchema] = []
    @Published var pageSize: Int = 5
    @Published var colorScheme: String = "purity_of_form_custom"
    @Published var fontFace: String = "Avenir"
    @Published var fontPoint: Int = 16
    @Published var appOptions: [AppOption] = []
    @Published var statusMessage: String = "正在读取配置..."
    @Published private(set) var mergedConfigs: [ConfigDomain: [String: Any]] = [:]
    @Published private(set) var patchConfigs: [ConfigDomain: [String: Any]] = [:]

    private var choicesCache: [String: [String]] = [:]
    private var labelsCache: [String: String] = [:]

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
        choicesCache.removeAll()
        labelsCache.removeAll()

        let hasDefaultFiles = fileExists(named: "default.yaml") || fileExists(named: "default.custom.yaml")
        let hasSquirrelFiles = fileExists(named: "squirrel.yaml") || fileExists(named: "squirrel.custom.yaml")

        guard hasDefaultFiles || hasSquirrelFiles else {
            applyFallbackSnapshot()
            statusMessage = "使用示例配置"
            return
        }

        let defaultBase = loadYamlDictionary(named: "default.yaml")
        let defaultPatch = loadPatchDictionary(named: "default.custom.yaml")
        patchConfigs[.default] = defaultPatch
        mergedConfigs[.default] = mergedDictionary(base: defaultBase, patch: defaultPatch)

        let squirrelBase = loadYamlDictionary(named: "squirrel.yaml")
        let squirrelPatch = loadPatchDictionary(named: "squirrel.custom.yaml")
        patchConfigs[.squirrel] = squirrelPatch
        mergedConfigs[.squirrel] = mergedDictionary(base: squirrelBase, patch: squirrelPatch)

        parseAvailableSchemas()
        applyMergedValues()
        statusMessage = "已读取 \(rimePath.path)"
    }

    private func parseAvailableSchemas() {
        let url = rimePath.appendingPathComponent("default.yaml")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        var schemas: [RimeSchema] = []
        let lines = content.components(separatedBy: .newlines)

        // Regex to match: - schema: id  # name
        let pattern = #"-\s+schema:\s+([a-zA-Z0-9_]+)(?:\s+#\s*(.*))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range) {
                if let idRange = Range(match.range(at: 1), in: line) {
                    let id = String(line[idRange])
                    var name = id
                    if match.numberOfRanges > 2, let nameRange = Range(match.range(at: 2), in: line) {
                        let extractedName = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                        if !extractedName.isEmpty {
                            name = extractedName
                        }
                    }
                    schemas.append(RimeSchema(schemaID: id, name: name, isBuiltIn: true))
                }
            }
        }

        // Also look for other *.schema.yaml files in the directory
        if let files = try? fileManager.contentsOfDirectory(at: rimePath, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "yaml" && file.lastPathComponent.contains(".schema.yaml") {
                let id = file.lastPathComponent.replacingOccurrences(of: ".schema.yaml", with: "")
                if !schemas.contains(where: { $0.schemaID == id }) {
                    let name = getSchemaName(from: file) ?? id
                    schemas.append(RimeSchema(schemaID: id, name: name, isBuiltIn: false))
                }
            }
        }

        self.availableSchemas = schemas
    }

    private func getSchemaName(from url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              let dict = try? Yams.load(yaml: content) as? [String: Any],
              let schema = dict["schema"] as? [String: Any] else {
            return nil
        }
        return schema["name"] as? String
    }

    func reload() {
        loadConfig()
    }

    func addNewSchema(id: String, name: String) {
        let fileName = "\(id).schema.yaml"
        let url = rimePath.appendingPathComponent(fileName)

        let content = """
        # Rime schema settings
        schema:
          schema_id: \(id)
          name: \(name)
          version: "0.1"
        """

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            loadConfig()
            statusMessage = "已添加方案: \(name)"
        } catch {
            statusMessage = "创建方案失败: \(error.localizedDescription)"
        }
    }

    func deleteSchema(id: String) {
        let fileName = "\(id).schema.yaml"
        let url = rimePath.appendingPathComponent(fileName)

        do {
            // 1. Remove from schema_list if present in patch
            var patch = patchConfigs[.default] ?? [:]
            if var schemaList = patch["schema_list"] as? [[String: Any]] {
                let originalCount = schemaList.count
                schemaList.removeAll { ($0["schema"] as? String) == id }
                if schemaList.count != originalCount {
                    patch["schema_list"] = schemaList
                    patchConfigs[.default] = patch
                    saveFullPatch(in: .default)
                }
            }

            // 2. Delete the file
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                loadConfig()
                statusMessage = "已删除方案文件并清理配置: \(id)"
            } else {
                loadConfig()
                statusMessage = "已清理配置: \(id)"
            }
        } catch {
            statusMessage = "删除方案失败: \(error.localizedDescription)"
        }
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
        // Handle virtual keypaths for key_binder
        if keyPath.hasPrefix("key_binder/") {
            let virtualKey = keyPath.replacingOccurrences(of: "key_binder/", with: "")
            switch virtualKey {
            case "select_pair":
                let first = value(in: mergedConfigs[domain] ?? [:], keyPath: "key_binder/select_first_character") as? String ?? ""
                let last = value(in: mergedConfigs[domain] ?? [:], keyPath: "key_binder/select_last_character") as? String ?? ""
                return (first.isEmpty && last.isEmpty) ? [] : [[first, last]]
            case "cursor_pair":
                return getVirtualHotkeyPairs(prevAction: "cursor_prev", nextAction: "cursor_next", in: domain)
            case "page_pair":
                return getVirtualHotkeyPairs(prevAction: "page_up", nextAction: "page_down", in: domain)
            default: break
            }
        }

        guard let dictionary = mergedConfigs[domain] else { return nil }
        return value(in: dictionary, keyPath: keyPath)
    }

    private func getVirtualHotkeyPairs(prevAction: String, nextAction: String, in domain: ConfigDomain) -> [[String]] {
        let prevs = getVirtualHotkeys(for: prevAction, in: domain)
        let nexts = getVirtualHotkeys(for: nextAction, in: domain)

        var pairs: [[String]] = []
        let count = min(prevs.count, nexts.count)
        for i in 0..<count {
            pairs.append([prevs[i], nexts[i]])
        }
        return pairs
    }

    private func getVirtualHotkeys(for action: String, in domain: ConfigDomain) -> [String] {
        let bindings = value(for: "key_binder/bindings", in: domain) as? [[String: Any]] ?? []
        let targetSend: String
        let targetWhen: String

        switch action {
        case "cursor_prev": (targetSend, targetWhen) = ("Shift+Left", "composing")
        case "cursor_next": (targetSend, targetWhen) = ("Shift+Right", "composing")
        case "page_up": (targetSend, targetWhen) = ("Page_Up", "has_menu")
        case "page_down": (targetSend, targetWhen) = ("Page_Down", "has_menu")
        default: return []
        }

        return bindings.filter { ($0["send"] as? String) == targetSend && ($0["when"] as? String) == targetWhen }
            .compactMap { $0["accept"] as? String }
    }

    func allKeys(in domain: ConfigDomain) -> [String] {
        guard let dictionary = mergedConfigs[domain] else { return [] }
        return getAllKeys(from: dictionary)
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

    func mergedConfig(for domain: ConfigDomain) -> [String: Any] {
        return mergedConfigs[domain] ?? [:]
    }

    func doubleValue(for keyPath: String, in domain: ConfigDomain) -> Double? {
        asDouble(value(for: keyPath, in: domain))
    }

    func intValue(for keyPath: String, in domain: ConfigDomain) -> Int? {
        asInt(value(for: keyPath, in: domain))
    }

    /// Resolves choices for a field, either from fixed choices or a reference to another config path.
    func resolveChoices(for field: SchemaField) -> [String] {
        if let choices = field.choices {
            return choices
        }

        if let ref = field.choicesRef {
            if let cached = choicesCache[ref] {
                return cached
            }

            let domains: [ConfigDomain] = [.squirrel, .default]
            for domain in domains {
                if let dict = value(for: ref, in: domain) as? [String: Any] {
                    let sortedKeys = dict.keys.sorted()
                    choicesCache[ref] = sortedKeys
                    return sortedKeys
                }
            }
        }

        return []
    }

    /// Returns a user-friendly label for a choice ID.
    func choiceLabel(for field: SchemaField, choice: String) -> String {
        let cacheKey = "\(field.id):\(choice)"
        if let cached = labelsCache[cacheKey] {
            return cached
        }

        // Hardcoded labels for common Rime options (can be moved to Schema or Localization later)
        let commonLabels: [String: String] = [
            "ascii_punct": "英文标点",
            "traditionalization": "简繁体",
            "emoji": "Emoji",
            "full_shape": "全角半角",
            "search_single_char": "单字模式",
            "noop": "无操作",
            "clear": "清除输入",
            "commit_code": "提交编码",
            "commit_text": "提交文字",
            "inline_ascii": "行内英文",
            "Caps_Lock": "CapsLock",
            "Shift_L": "左 Shift",
            "Shift_R": "右 Shift",
            "Control_L": "左 Control",
            "Control_R": "右 Control"
        ]

        if let label = commonLabels[choice] {
            labelsCache[cacheKey] = label
            return label
        }

        if field.choices != nil {
            return choice // Fixed choices are already labels
        }

        if let ref = field.choicesRef {
            let domains: [ConfigDomain] = [.squirrel, .default]
            for domain in domains {
                if let dict = value(for: ref, in: domain) as? [String: Any],
                   let item = dict[choice] as? [String: Any],
                   let name = item["name"] as? String {
                    labelsCache[cacheKey] = name
                    return name
                }
            }
        }

        labelsCache[cacheKey] = choice
        return choice
    }

    func updateValue(_ value: Any, for keyPath: String, in domain: ConfigDomain) {
        var finalValue = value

        // Handle virtual keypaths for key_binder
        if keyPath.hasPrefix("key_binder/") {
            let virtualKey = keyPath.replacingOccurrences(of: "key_binder/", with: "")
            switch virtualKey {
            case "select_pair":
                let pairs = value as? [[String]] ?? []
                if let firstPair = pairs.first, firstPair.count == 2 {
                    updateValue(firstPair[0], for: "key_binder/select_first_character", in: domain)
                    updateValue(firstPair[1], for: "key_binder/select_last_character", in: domain)
                } else {
                    updateValue("", for: "key_binder/select_first_character", in: domain)
                    updateValue("", for: "key_binder/select_last_character", in: domain)
                }
                return
            case "cursor_pair":
                updateVirtualHotkeyPairs(value as? [[String]] ?? [], prevAction: "cursor_prev", nextAction: "cursor_next", in: domain)
                return
            case "page_pair":
                updateVirtualHotkeyPairs(value as? [[String]] ?? [], prevAction: "page_up", nextAction: "page_down", in: domain)
                return
            default: break
            }
        }

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

        // 1.5 Update patchConfigs for YAML editor
        var patch = patchConfigs[domain] ?? [:]
        patch[keyPath] = finalValue
        patchConfigs[domain] = patch

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
    func removePatch(for keyPath: String, in domain: ConfigDomain) {
        // 1. Update patchConfigs
        var patch = patchConfigs[domain] ?? [:]
        patch.removeValue(forKey: keyPath)
        patchConfigs[domain] = patch

        // 2. Reload everything to get back to base values
        loadConfig()

        // 3. Save the updated patch file
        saveFullPatch(in: domain)
    }

    private func saveFullPatch(in domain: ConfigDomain) {
        let patch = patchConfigs[domain] ?? [:]
        let fileName = "\(domain.rawValue).custom.yaml"
        let url = rimePath.appendingPathComponent(fileName)

        let root: [String: Any] = ["patch": patch]
        if let yaml = try? Yams.dump(object: root, allowUnicode: true) {
            try? yaml.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "已更新 \(fileName)"
        }
    }

    func loadRawYaml(for domain: ConfigDomain) -> String {
        let fileName = "\(domain.rawValue).custom.yaml"
        let url = rimePath.appendingPathComponent(fileName)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "patch:\n"
    }

    func saveRawYaml(_ content: String, for domain: ConfigDomain) {
        let fileName = "\(domain.rawValue).custom.yaml"
        let url = rimePath.appendingPathComponent(fileName)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        loadConfig() // Reload to sync UI
        statusMessage = "已保存 \(fileName)"
    }
    private func updateVirtualHotkeyPairs(_ pairs: [[String]], prevAction: String, nextAction: String, in domain: ConfigDomain) {
        let prevHotkeys = pairs.map { $0[0] }
        let nextHotkeys = pairs.map { $0[1] }

        // We need to update both actions in the bindings
        var bindings = value(for: "key_binder/bindings", in: domain) as? [[String: Any]] ?? []

        let (prevSend, prevWhen) = getActionDetails(for: prevAction)
        let (nextSend, nextWhen) = getActionDetails(for: nextAction)

        // 1. Remove existing bindings for both actions
        bindings.removeAll {
            (($0["send"] as? String) == prevSend && ($0["when"] as? String) == prevWhen) ||
            (($0["send"] as? String) == nextSend && ($0["when"] as? String) == nextWhen)
        }

        // 2. Add new bindings in pairs
        for i in 0..<pairs.count {
            bindings.append(["when": prevWhen, "accept": prevHotkeys[i], "send": prevSend])
            bindings.append(["when": nextWhen, "accept": nextHotkeys[i], "send": nextSend])
        }

        // 3. Update the real keyPath
        updateValue(bindings, for: "key_binder/bindings", in: domain)
    }

    private func getActionDetails(for action: String) -> (send: String, when: String) {
        switch action {
        case "cursor_prev": return ("Shift+Left", "composing")
        case "cursor_next": return ("Shift+Right", "composing")
        case "page_up": return ("Page_Up", "has_menu")
        case "page_down": return ("Page_Down", "has_menu")
        default: return ("", "")
        }
    }

    private func updateVirtualHotkeys(_ hotkeys: [String], for action: String, in domain: ConfigDomain) {
        var bindings = value(for: "key_binder/bindings", in: domain) as? [[String: Any]] ?? []
        let targetSend: String
        let targetWhen: String

        switch action {
        case "cursor_prev": (targetSend, targetWhen) = ("Shift+Left", "composing")
        case "cursor_next": (targetSend, targetWhen) = ("Shift+Right", "composing")
        case "page_up": (targetSend, targetWhen) = ("Page_Up", "has_menu")
        case "page_down": (targetSend, targetWhen) = ("Page_Down", "has_menu")
        default: return
        }

        // 1. Remove existing bindings for this action
        bindings.removeAll { ($0["send"] as? String) == targetSend && ($0["when"] as? String) == targetWhen }

        // 2. Add new bindings
        for hotkey in hotkeys {
            bindings.append(["when": targetWhen, "accept": hotkey, "send": targetSend])
        }

        // 3. Update the real keyPath
        updateValue(bindings, for: "key_binder/bindings", in: domain)
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
