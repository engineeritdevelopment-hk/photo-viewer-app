import SwiftUI

struct OptionToggle: View {
    let title: String
    let helpText: String
    @Binding var isOn: Bool
    var compact: Bool = false
    var disabled: Bool = false
    @State private var isHelpPresented = false

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
                .font(compact ? .caption : .body)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(disabled)
                .help(disabled ? "Stop analysis before changing this option." : "")

            Button {
                isHelpPresented = true
            } label: {
                Image(systemName: "info.circle")
                    .font(compact ? .caption2 : .callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Click for an explanation")
            .accessibilityLabel("\(title) explanation")
            .accessibilityHint("Shows how this analysis option works")
        }
        .alert(title, isPresented: $isHelpPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(helpText)
        }
    }
}

/// Select analysis options, then Run or Stop.
struct LibraryAnalysisControls: View {
    @Bindable var model: LibraryViewModel

    private var optionsLocked: Bool { model.isAnalysisRunning }

    var body: some View {
        HStack(spacing: 10) {
            OptionToggle(
                title: "Categories",
                helpText: "Detect semantic categories from each photo (Vision labels, text, and Apple Intelligence when available). Categories appear as chips above the grid; optional export titles are stored without renaming originals. Pin a category to Albums from the chip menu.",
                isOn: $model.categoryDetectionOn,
                compact: true,
                disabled: optionsLocked
            )

            OptionToggle(
                title: "Objects",
                helpText: "Find things in each photo with an on-device detector trained on about 600 kinds of objects. Search those names under Filter → Objects.",
                isOn: $model.objectDetectionOn,
                compact: true,
                disabled: optionsLocked
            )

            OptionToggle(
                title: "Faces",
                helpText: "Detect faces and group similar ones into people across your library. Re-run Faces to merge duplicates into one person.",
                isOn: $model.analyzeFacesOn,
                compact: true,
                disabled: optionsLocked
            )

            Divider()
                .frame(height: 20)

            Button("Run") {
                model.startAnalysis()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!model.canStartAnalysis)
            .help(runHelp)

            Button("Stop") {
                model.stopAnalysis()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.isAnalysisRunning)
            .help("Stop the current analysis, including a face search.")
        }
    }

    private var runHelp: String {
        if model.activity.isCataloging {
            return "Wait until indexing finishes."
        }
        if !model.categoryDetectionOn && !model.objectDetectionOn && !model.analyzeFacesOn {
            return "Select Categories, Objects, and/or Faces to run analysis."
        }
        return "Run on-device analysis for the current library."
    }
}
