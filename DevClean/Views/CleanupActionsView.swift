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
            .help(
                viewModel.isAnalysisPartial
                    ? String(localized: "Run the analysis again to get complete results")
                    : String(localized: "Clean the selected modules")
            )

            if viewModel.isBusy {
                runningIndicator
            }

            Spacer()

            if let issue = viewModel.lastIssue, !viewModel.isBusy {
                issueStatusLabel(issue)
            }
        }
    }

    @ViewBuilder
    private var runningIndicator: some View {
        Divider()
            .frame(height: 20)

        ProgressView()
            .controlSize(.small)
            .accessibilityHidden(true)

        Text(viewModel.runState.activeMode?.progressTitle ?? "")
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

        Button("Cancel") {
            viewModel.cancel()
        }
        .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private func issueStatusLabel(_ issue: CleanupRunIssue) -> some View {
        let label = Label {
            Text(issue.label)
        } icon: {
            Image(systemName: iconName(for: issue))
        }
        .font(.callout)
        .foregroundStyle(tint(for: issue))
        .help(issue.recoverySuggestion ?? issue.label)

        label
    }

    private func iconName(for issue: CleanupRunIssue) -> String {
        switch issue {
        case .success:
            "checkmark.circle.fill"
        case .cancelled:
            "stop.circle.fill"
        case .launchFailed:
            "xmark.octagon.fill"
        case .partialFailure, .failed, .timeout, .interruptedBySignal:
            "exclamationmark.triangle.fill"
        }
    }

    private func tint(for issue: CleanupRunIssue) -> Color {
        switch issue {
        case .success:
            .green
        case .cancelled:
            .secondary
        case .launchFailed:
            .red
        case .partialFailure, .failed, .timeout, .interruptedBySignal:
            .orange
        }
    }
}
