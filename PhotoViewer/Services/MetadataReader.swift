import CoreGraphics
import Foundation
import ImageIO

enum MetadataReader {
    struct Metadata: Sendable {
        var takenAt: Date?
        var cameraMake: String?
        var cameraModel: String?
        var latitude: Double?
        var longitude: Double?
        var hasGPS: Bool
        var width: Int?
        var height: Int?
        var isScreenshot: Bool
    }

    static func read(url: URL) -> Metadata {
        let path = url.path
        let isScreenshot = SmartAnalyzer.isScreenshot(at: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return Metadata(
                takenAt: mod,
                cameraMake: nil,
                cameraModel: nil,
                latitude: nil,
                longitude: nil,
                hasGPS: false,
                width: nil,
                height: nil,
                isScreenshot: isScreenshot
            )
        }

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]

        let takenAt = parseExifDate(exif?[kCGImagePropertyExifDateTimeOriginal as String])
            ?? parseExifDate(exif?[kCGImagePropertyExifDateTimeDigitized as String])
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        let width = properties[kCGImagePropertyPixelWidth as String] as? Int
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int

        let coords = parseGPS(gps)
        let hasGPS = coords.lat != nil && coords.lon != nil

        return Metadata(
            takenAt: takenAt,
            cameraMake: tiff?[kCGImagePropertyTIFFMake as String] as? String,
            cameraModel: tiff?[kCGImagePropertyTIFFModel as String] as? String,
            latitude: coords.lat,
            longitude: coords.lon,
            hasGPS: hasGPS,
            width: width,
            height: height,
            isScreenshot: isScreenshot
        )
    }

  static func facts(url: URL) -> [(String, String)] {
        let meta = read(url: url)
        let name = url.lastPathComponent
        let folder = url.deletingLastPathComponent().path
        var rows: [(String, String)] = [
            ("Name", name),
            ("Folder", folder),
            ("Type", url.pathExtension.uppercased()),
        ]
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            rows.append(("Size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        if let width = meta.width, let height = meta.height {
            rows.append(("Dimensions", "\(width) × \(height)"))
        }
        if let taken = meta.takenAt {
            rows.append(("Taken", DateFormatter.localizedString(from: taken, dateStyle: .medium, timeStyle: .short)))
        }
        if let make = meta.cameraMake { rows.append(("Maker", make)) }
        if let model = meta.cameraModel { rows.append(("Camera", model)) }
        if let lat = meta.latitude, let lon = meta.longitude {
            rows.append(("Coordinates", String(format: "%.5f, %.5f", lat, lon)))
        }
        if let place = readPlaceFromAnnotation(path: pathFor(url)) {
            rows.append(("Place", place))
        }
        return rows
    }

    private static func pathFor(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func readPlaceFromAnnotation(path: String) -> String? {
        nil // filled by view model when showing
    }

    private static func parseExifDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    private struct GPSCoords {
        var lat: Double?
        var lon: Double?
    }

    private static func parseGPS(_ gps: [String: Any]?) -> GPSCoords {
        guard let gps else { return GPSCoords() }
        let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double
        let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double
        let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String
        guard var latitude = lat, var longitude = lon else { return GPSCoords() }
        if latRef == "S" { latitude *= -1 }
        if lonRef == "W" { longitude *= -1 }
        return GPSCoords(lat: latitude, lon: longitude)
    }
}