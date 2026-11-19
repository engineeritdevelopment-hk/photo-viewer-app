import CoreLocation
import Foundation

actor PlaceLabelService {
    private var cache: [String: String] = [:]
    private let geocoder = CLGeocoder()
    private var pending = 0
    private let maxConcurrent = 2

    init() {
        if let data = try? Data(contentsOf: ApplicationPaths.geocodeCache),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = decoded
        }
    }

    func label(latitude: Double, longitude: Double) async -> String? {
        let key = coordinateKey(latitude: latitude, longitude: longitude)
        if let hit = cache[key] { return hit }

        while pending >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        pending += 1
        defer { pending -= 1 }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            let label = placemarks.first.flatMap(formatPlacemark)
            if let label {
                cache[key] = label
                persistCache()
            }
            return label
        } catch {
            return nil
        }
    }

    private func coordinateKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.3f,%.3f", latitude, longitude)
    }

    private func formatPlacemark(_ placemark: CLPlacemark) -> String? {
        let parts = [placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? placemark.name : parts.joined(separator: ", ")
    }

    private func persistCache() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: ApplicationPaths.geocodeCache, options: .atomic)
        }
    }
}