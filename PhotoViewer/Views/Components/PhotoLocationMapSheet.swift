import MapKit
import SwiftUI

struct PhotoLocationMapSheet: View {
    let coordinate: CLLocationCoordinate2D
    let photoTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D, photoTitle: String) {
        self.coordinate = coordinate
        self.photoTitle = photoTitle
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                Marker(photoTitle, coordinate: coordinate)
            }
            .mapStyle(.standard(elevation: .realistic))
            footer
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo location")
                    .font(.headline)
                Text(coordinateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Text("Pan and zoom to explore. Pin marks where this photo was taken.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let external = externalMapsURL {
                Link("Open in Maps", destination: external)
                    .font(.caption)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var coordinateLabel: String {
        String(format: "%.5f°, %.5f°", coordinate.latitude, coordinate.longitude)
    }

    private var externalMapsURL: URL? {
        URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)")
    }
}