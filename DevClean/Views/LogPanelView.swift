import SwiftUI

struct LogPanelView: View {
    let viewModel: CleanupViewModel

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
            if !viewModel.logOutput.isEmpty {
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

    private var logScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.logOutput.isEmpty {
                        Text("Script output will appear here…")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(viewModel.logOutput)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(LogAnchor.bottom)
                }
            }
            .onChange(of: viewModel.logOutput) { _, _ in
                proxy.scrollTo(LogAnchor.bottom, anchor: .bottom)
            }
        }
    }

    private enum LogAnchor {
        static let bottom = "log-bottom"
    }
}
