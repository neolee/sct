import Foundation
import Combine
import Yams

/// A lightweight configuration loader that reads the available `.custom.yaml` patches.
/// The goal for now is to exercise the Yams dependency and provide data for the prototype UI.
final class RimeConfigManager: ObservableObject {
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

    private let rimePath: URL

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
        let defaultCustom = loadPatchDictionary(named: "default.custom.yaml")
        let squirrelCustom = loadPatchDictionary(named: "squirrel.custom.yaml")

        var hydratedFromDisk = false

        if let menu = defaultCustom?["menu"] as? [String: Any],
           let size = menu["page_size"] as? Int {
            pageSize = size
            hydratedFromDisk = true
        }

        if let schemas = defaultCustom?["schema_list"] as? [[String: Any]] {
            schemaList = schemas.compactMap { $0["schema"] as? String }
            hydratedFromDisk = !schemaList.isEmpty
        }

        if let style = squirrelCustom?["style"] as? [String: Any] {
            colorScheme = style["color_scheme"] as? String ?? colorScheme
            fontFace = style["font_face"] as? String ?? fontFace
            fontPoint = style["font_point"] as? Int ?? fontPoint
            hydratedFromDisk = true
        }

        if let apps = squirrelCustom?["app_options"] as? [String: Any] {
            appOptions = apps.compactMap { key, value in
                guard let dict = value as? [String: Any] else { return nil }
                let ascii = dict["ascii_mode"] as? Bool ?? false
                return AppOption(bundleID: key, asciiMode: ascii)
            }
            .sorted { $0.bundleID < $1.bundleID }
            hydratedFromDisk = !appOptions.isEmpty
        }

        if hydratedFromDisk {
            statusMessage = "已读取 \(rimePath.path)"
        } else {
            applyFallbackSnapshot()
            statusMessage = "使用示例配置"
        }
    }

    func reload() {
        loadConfig()
    }

    private func loadPatchDictionary(named fileName: String) -> [String: Any]? {
        let url = rimePath.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        guard
            let root = try? Yams.load(yaml: contents),
            let dict = root as? [String: Any],
            let patch = dict["patch"] as? [String: Any]
        else {
            return nil
        }

        return patch
    }

    private func applyFallbackSnapshot() {
        guard
            let root = try? Yams.load(yaml: Self.fallbackYAML),
            let dict = root as? [String: Any]
        else {
            schemaList = ["rime_ice"]
            return
        }

        if let menu = dict["menu"] as? [String: Any] {
            pageSize = menu["page_size"] as? Int ?? pageSize
        }

        if let schemas = dict["schema_list"] as? [[String: Any]] {
            schemaList = schemas.compactMap { $0["schema"] as? String }
        }

        if let style = dict["style"] as? [String: Any] {
            colorScheme = style["color_scheme"] as? String ?? colorScheme
            fontFace = style["font_face"] as? String ?? fontFace
            fontPoint = style["font_point"] as? Int ?? fontPoint
        }

        if let apps = dict["app_options"] as? [String: Any] {
            appOptions = apps.compactMap { key, value in
                guard let dict = value as? [String: Any] else { return nil }
                return AppOption(bundleID: key, asciiMode: dict["ascii_mode"] as? Bool ?? false)
            }
        }
    }
}
