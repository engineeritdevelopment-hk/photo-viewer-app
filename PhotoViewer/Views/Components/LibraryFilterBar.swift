import SwiftUI

/// Narrow the grid by capture / file date (applies immediately).
struct LibraryFilterBar: View {
    @Bindable var model: LibraryViewModel
    var embedded: Bool = false
    @State private var fromEnabled = false
    @State private var toEnabled = false
    @State private var fromDate = Calendar.current.startOfDay(for: Date())
    @State private var toDate = Calendar.current.startOfDay(for: Date())

    private var hasDateWindow: Bool {
        model.metadataFilter.takenAfter != nil || model.metadataFilter.takenBefore != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Label("Date range", systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(width: embedded ? 100 : nil, alignment: .leading)

            DateBoundField(
                title: "From",
                enabled: $fromEnabled,
                date: $fromDate
            )

            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 18)

            DateBoundField(
                title: "To",
                enabled: $toEnabled,
                date: $toDate
            )

            Spacer(minLength: 8)

            if hasDateWindow {
                Button("Clear dates") {
                    clearDateWindow()
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, embedded ? 0 : 12)
        .padding(.vertical, embedded ? 0 : 6)
        .background {
            if !embedded {
                Color(nsColor: .underPageBackgroundColor).opacity(0.35)
            }
        }
        .overlay(alignment: .bottom) {
            if !embedded { Divider() }
        }
        .onAppear(perform: syncFromModel)
        .onChange(of: model.metadataFilter) { _, _ in syncFromModel() }
        .onChange(of: model.indexedDateEarliest) { _, _ in
            if !hasDateWindow { applyLibraryDefaultDates() }
        }
        .onChange(of: model.indexedDateLatest) { _, _ in
            if !hasDateWindow { applyLibraryDefaultDates() }
        }
        .onChange(of: fromEnabled) { _, _ in pushToModel() }
        .onChange(of: toEnabled) { _, _ in pushToModel() }
        .onChange(of: fromDate) { _, _ in
            guard fromEnabled else { return }
            pushToModel()
        }
        .onChange(of: toDate) { _, _ in
            guard toEnabled else { return }
            pushToModel()
        }
    }

    private func syncFromModel() {
        if let after = model.metadataFilter.takenAfter {
            fromEnabled = true
            fromDate = Calendar.current.startOfDay(for: after)
        } else {
            fromEnabled = false
            applyLibraryDefaultDatesToFrom()
        }
        if let before = model.metadataFilter.takenBefore {
            toEnabled = true
            toDate = Calendar.current.startOfDay(for: before)
        } else {
            toEnabled = false
            applyLibraryDefaultDatesToTo()
        }
    }

    private func applyLibraryDefaultDates() {
        applyLibraryDefaultDatesToFrom()
        applyLibraryDefaultDatesToTo()
    }

    private func applyLibraryDefaultDatesToFrom() {
        fromDate = model.defaultDateFilterFrom()
    }

    private func applyLibraryDefaultDatesToTo() {
        toDate = model.defaultDateFilterTo()
    }

    private func pushToModel() {
        var filter = model.metadataFilter
        filter.takenAfter = fromEnabled ? model.startOfDay(fromDate) : nil
        filter.takenBefore = toEnabled ? model.endOfDay(toDate) : nil
        if fromEnabled && toEnabled && fromDate > toDate {
            swap(&fromDate, &toDate)
            filter.takenAfter = model.startOfDay(fromDate)
            filter.takenBefore = model.endOfDay(toDate)
        }
        guard filter != model.metadataFilter else { return }
        model.applyMetadataFilter(filter)
    }

    private func clearDateWindow() {
        fromEnabled = false
        toEnabled = false
        applyLibraryDefaultDates()
        var filter = model.metadataFilter
        filter.takenAfter = nil
        filter.takenBefore = nil
        model.applyMetadataFilter(filter)
    }
}

// MARK: - Date bound control

private struct DateBoundField: View {
    let title: String
    @Binding var enabled: Bool
    @Binding var date: Date

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $enabled) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(enabled ? Color.primary : Color.secondary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(.leading, 1)

            datePicker
                .padding(.leading, 18)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 156, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    enabled
                        ? Color.accentColor.opacity(0.1)
                        : Color(nsColor: .controlBackgroundColor)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    enabled ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1),
                    lineWidth: enabled ? 1.25 : 1
                )
        }
        .help("\(title): \(Self.dayFormatter.string(from: date)). Click the date or checkbox to filter.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) date filter")
        .accessibilityValue(enabled ? "On, \(Self.dayFormatter.string(from: date))" : "Off")
        .accessibilityHint("Click to turn on and edit the date")
    }

    private var datePicker: some View {
        DatePicker(
            "",
            selection: $date,
            displayedComponents: .date
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(enabled ? 1 : 0.6)
            .overlay {
                if !enabled {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            enabled = true
                        }
                        .help("Click to enable this date bound")
                }
            }
    }
}