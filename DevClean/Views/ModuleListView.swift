import SwiftUI

struct ModuleListView: View {
    let viewModel: CleanupViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            moduleScrollView
        }
        .frame(height: 350)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator)
        }
    }

    private var header: some View {
        HStack {
            Text("Modules")
                .font(.headline)
            if viewModel.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            if !viewModel.modules.isEmpty {
                Text("Click a module to exclude it from cleaning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var moduleScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.modules.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.modules) { module in
                        ModuleRowView(
                            module: module,
                            isSelected: selectionBinding(for: module),
                            isEnabled: !viewModel.isBusy
                        )
                        if module.id != viewModel.modules.last?.id {
                            Divider()
                                .padding(.leading, 30)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if viewModel.isBusy {
                ProgressView()
                Text("Scanning caches…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "shippingbox")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No modules found")
                    .foregroundStyle(.secondary)
                Text("Click “Rescan” to run the analysis again.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func selectionBinding(for module: CleanupModule) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedModuleIDs.contains(module.id) },
            set: { viewModel.setSelected($0, for: module.id) }
        )
    }
}

private struct ModuleRowView: View {
    let module: CleanupModule
    @Binding var isSelected: Bool
    let isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: 16) {
                Text(module.name)
                Spacer(minLength: 12)
                Text(module.sizeBytes.byteCountFormatted)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!isEnabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}
