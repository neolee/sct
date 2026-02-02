import SwiftUI
import MarkdownUI

struct HelpView: View {
    @ObservedObject var manager: RimeConfigManager
    @EnvironmentObject var updater: UpdaterViewModel
    @State private var helpContent: String = L10n.loadingHelp

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (Build \(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Markdown(helpContent)
                    .markdownTheme(.docC)
                    .textSelection(.enabled)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Button(action: {
                        manager.withSecurityScopedAccess {
                            NSWorkspace.shared.activateFileViewerSelecting([manager.rimePath])
                        }
                    }) {
                        Label(L10n.showInFinder, systemImage: "folder")
                    }
                    .buttonStyle(.link)

                    aboutSection
                }
            }
            .padding(16)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .navigationTitle(L10n.help)
        .onAppear {
            loadHelpContent()
        }
    }

    private func loadHelpContent() {
        guard let url = Bundle.main.url(forResource: "Help", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Fallback if file not in bundle (e.g. during development if not added to target)
            if let devUrl = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("SCT/Help.md") as URL?,
               let devContent = try? String(contentsOf: devUrl, encoding: .utf8) {
                helpContent = devContent
                return
            }
            helpContent = L10n.helpLoadError
            return
        }
        helpContent = content
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            HStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.appTitle)
                        .font(.headline)
                    Text(String(format: L10n.version, versionString))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(L10n.copyright)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button(L10n.checkUpdates) {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(!updater.canCheckForUpdates)

                    Button(L10n.resetAccess) {
                        manager.resetAccess()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(.top, 20)
    }
}

extension String {
    var expandingTildeWithFileManager: String {
        return (self as NSString).expandingTildeInPath
    }
}

#Preview {
    HelpView(manager: RimeConfigManager())
        .environmentObject(UpdaterViewModel())
}
