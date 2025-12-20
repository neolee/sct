import SwiftUI

struct HelpView: View {
    @State private var helpContent: AttributedString = AttributedString(L10n.loadingHelp)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(helpContent)
                    .textSelection(.enabled)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "~/Library/Rime".expandingTildeWithFileManager)
                    }) {
                        Label(L10n.showInFinder, systemImage: "folder")
                    }
                    .buttonStyle(.link)

                    aboutSection
                }
            }
            .padding(40)
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
                parseMarkdown(devContent)
                return
            }
            helpContent = AttributedString(L10n.helpLoadError)
            return
        }
        parseMarkdown(content)
    }

    private func parseMarkdown(_ content: String) {
        do {
            helpContent = try AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            helpContent = AttributedString(content)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            HStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Squirrel Configuration Tool")
                        .font(.headline)
                    Text(String(format: L10n.version, "1.0.0 (Build 20251219)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(L10n.copyright)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button(L10n.checkUpdates) {
                        if let url = URL(string: "https://github.com/paradigmx/rime-sct") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
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
    HelpView()
}
