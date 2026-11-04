import SwiftUI

struct CleanupActionsView: View {
    let viewModel: CleanupViewModel
    let onCleanRequested: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Rescan") {
                viewModel.analyze()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isBusy)
            .help("Run the analysis for all modules again")

            Button("Clean Selected", role: .destructive) {
                onCleanRequested()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!viewModel.canClean)
            .help("Clean the selected modules")

            if viewModel.isBusy {
                runningIndicator
            }

            Spacer()

            if let exitCode = viewModel.lastExitCode, !viewModel.isBusy {
                exitStatusLabel(exitCode: exitCode)
            }
        }
    }

    @ViewBuilder
    private var runningIndicator: some View {
        Divider()
            .frame(height: 20)

        ProgressView()
            .controlSize(.small)

        Text(viewModel.runState.activeMode?.progressTitle ?? "")
            .font(.callout)
            .foregroundStyle(.secondary)

        Button("Cancel") {
            viewModel.cancel()
        }
        .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private func exitStatusLabel(exitCode: Int32) -> some View {
        if exitCode == 0 {
            Label("Success", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        } else {
            Label("Exit code: \(Int(exitCode))", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}
