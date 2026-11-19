import SwiftUI

struct ActivityBanner: View {
    let activity: LibraryActivity
    var embedded: Bool = false

    @State private var metadataEstimator = ProgressETAEstimator()
    @State private var analyzeEstimator = ProgressETAEstimator()
    @State private var facesEstimator = ProgressETAEstimator()
    @State private var geocodeEstimator = ProgressETAEstimator()
    @State private var catalogEstimator = ProgressETAEstimator()

    @State private var metadataETALabel: String?
    @State private var analyzeETALabel: String?
    @State private var facesETALabel: String?
    @State private var geocodeETALabel: String?
    @State private var catalogETALabel: String?

    private var isVisible: Bool {
        activity.isCataloging
            || activity.isMetadataing
            || activity.isAnalyzing
            || activity.isFaceProcessing
            || activity.isGeocoding
            || activity.isExporting
            || activity.errorMessage != nil
    }

    var body: some View {
        if !isVisible {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if activity.isCataloging {
                catalogLine
            }
            if activity.isMetadataing {
                line(
                    title: "Reading metadata…",
                    done: activity.metadataDone,
                    total: activity.metadataTotal,
                    eta: metadataETALabel,
                    secondary: nil
                )
            }
            if activity.isAnalyzing {
                line(
                    title: "Analyzing…",
                    done: activity.analyzed,
                    total: activity.analyzeTotal,
                    eta: analyzeETALabel,
                    secondary: nil
                )
            }
            if activity.isFaceProcessing {
                line(
                    title: "Analyzing faces…",
                    done: activity.facesProcessed,
                    total: activity.faceTotal,
                    eta: facesETALabel,
                    secondary: nil
                )
            }
            if activity.isGeocoding {
                line(
                    title: "Resolving places…",
                    done: activity.geocoded,
                    total: activity.geocodeTotal,
                    eta: geocodeETALabel,
                    secondary: nil
                )
            }
            if activity.isExporting {
                line(title: "Exporting…", done: activity.exportCopied, total: activity.exportTotal, eta: nil, secondary: nil)
            }
            if let error = activity.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, embedded ? 10 : 12)
        .padding(.vertical, embedded ? 6 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if embedded {
                Color(nsColor: .controlBackgroundColor).opacity(0.55)
            } else {
                Color(nsColor: .underPageBackgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: embedded ? 8 : 0, style: .continuous))
        .overlay(alignment: .bottom) {
            if !embedded { Divider() }
        }
        .accessibilityElement(children: .combine)
        .onAppear { syncETALabels() }
        .onChange(of: activity) { _, _ in syncETALabels() }
    }

    private func syncETALabels() {
        if activity.isMetadataing {
            metadataETALabel = metadataEstimator.update(done: activity.metadataDone, total: activity.metadataTotal)
        } else {
            metadataEstimator.reset()
            metadataETALabel = nil
        }

        if activity.isAnalyzing {
            analyzeETALabel = analyzeEstimator.update(done: activity.analyzed, total: activity.analyzeTotal)
        } else {
            analyzeEstimator.reset()
            analyzeETALabel = nil
        }

        if activity.isFaceProcessing {
            facesETALabel = facesEstimator.update(done: activity.facesProcessed, total: activity.faceTotal)
        } else {
            facesEstimator.reset()
            facesETALabel = nil
        }

        if activity.isGeocoding {
            geocodeETALabel = geocodeEstimator.update(done: activity.geocoded, total: activity.geocodeTotal)
        } else {
            geocodeEstimator.reset()
            geocodeETALabel = nil
        }

        if activity.isCataloging, let total = activity.catalogTotal {
            catalogETALabel = catalogEstimator.update(done: activity.catalogScanned, total: total)
        } else {
            catalogEstimator.reset()
            catalogETALabel = nil
        }
    }

    private var catalogLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let total = activity.catalogTotal {
                Text("Indexing… \(activity.catalogScanned) / \(total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(activity.catalogScanned), total: Double(total))
                if let catalogETALabel {
                    Text(catalogETALabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Indexing… \(activity.catalogScanned) files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView()
            }
            if let secondary = activity.currentSourceName {
                Text("Source: \(secondary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func line(title: String, done: Int, total: Int, eta: String?, secondary: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(total > 0 ? "\(title) \(done) / \(total)" : "\(title) \(done) files")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
            } else {
                ProgressView()
            }
            if let eta {
                Text(eta)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let secondary {
                Text("Source: \(secondary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}