import SwiftUI

struct CleanupHeaderView: View {
    let viewModel: CleanupViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dev Cache Cleaner")
                    .font(.largeTitle.bold())
                Text("Select the modules to clean. Sizes were measured during the last analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !viewModel.modules.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Selected \(viewModel.selectedModuleIDs.count) of \(viewModel.modules.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(viewModel.selectedSizeBytes.byteCountFormatted)
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
            }
        }
    }
}
