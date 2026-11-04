import SwiftUI

struct ContentView: View {
    let viewModel: CleanupViewModel

    @State private var isShowingCleanConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CleanupHeaderView(viewModel: viewModel)
            ModuleListView(viewModel: viewModel)
            CleanupActionsView(viewModel: viewModel) {
                isShowingCleanConfirmation = true
            }
            LogPanelView(viewModel: viewModel)
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            viewModel.startIfNeeded()
        }
        .confirmationDialog(
            "Clean the selected modules?",
            isPresented: $isShowingCleanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean", role: .destructive) {
                viewModel.cleanSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.confirmationMessage)
        }
    }
}

#if DEBUG
#Preview {
    ContentView(viewModel: AppDependencies.preview.makeCleanupViewModel())
}
#endif
