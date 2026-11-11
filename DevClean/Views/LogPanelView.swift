import SwiftUI

struct LogPanelView: View {
    let viewModel: CleanupViewModel

    /// Distance (in points) from the very bottom that still counts as "at the
    /// end" of the log.
    private static let bottomTolerance: CGFloat = 40

    @State private var viewportHeight: CGFloat = 0
    @State private var contentBottom: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator)
        }
    }

    private var header: some View {
        HStack {
            Label("Log", systemImage: "terminal")
                .font(.headline)
            Spacer()
            if !viewModel.logLines.isEmpty {
                Button {
                    viewModel.copyLog()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Copy the entire log to the clipboard")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Keeps the log pinned to the bottom only while the user has not scrolled
    /// away from it, so reading older output is not interrupted.
    private var logScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.logLines.isEmpty {
                        Text("Script output will appear here…")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(attributedLog)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(LogAnchor.bottom)
                        .background {
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: ContentBottomKey.self,
                                        value: geo.frame(in: .named(LogAnchor.space)).maxY
                                    )
                            }
                        }
                }
            }
            .coordinateSpace(name: LogAnchor.space)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ViewportHeightKey.self, value: geo.size.height)
                }
            }
            .onPreferenceChange(ContentBottomKey.self) { contentBottom = $0 }
            .onPreferenceChange(ViewportHeightKey.self) { viewportHeight = $0 }
            .onChange(of: viewModel.logLines) { _, _ in
                guard isAtLogEnd else { return }
                proxy.scrollTo(LogAnchor.bottom, anchor: .bottom)
            }
        }
    }

    /// The full transcript as one selectable text, with stderr lines — the
    /// script's error output — painted red so failures stand out at a glance.
    private var attributedLog: AttributedString {
        var attributed = AttributedString()
        for line in viewModel.logLines {
            var entry = AttributedString(line.text)
            if line.isFromStderr {
                entry.foregroundColor = .red
            }
            attributed += entry
            attributed += AttributedString("\n")
        }
        return attributed
    }

    /// Bottom of the content within `viewportHeight + tolerance` of the
    /// viewport bottom — i.e. the user is at (or near) the end, or the content
    /// does not fill the viewport yet.
    private var isAtLogEnd: Bool {
        contentBottom <= viewportHeight + Self.bottomTolerance
    }

    private enum LogAnchor {
        static let bottom = "log-bottom"
        static let space = "log-space"
    }
}

private struct ContentBottomKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

private struct ViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
