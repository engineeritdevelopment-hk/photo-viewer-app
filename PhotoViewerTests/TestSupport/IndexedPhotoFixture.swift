import Foundation
@testable import Photo_Viewer

/// Seeds a small catalog for filter / sidebar integration tests.
enum IndexedPhotoFixture {
    static let path2020 = "/Volumes/DiskA/2020/a.jpg"
    static let pathScreenshot = "/Volumes/DiskA/2024/screen.png"
    static let pathBeach = "/Volumes/DiskB/beach.jpg"
    static let pathOther = "/Volumes/Other/x.jpg"
    static let diskAPrefix = "/Volumes/DiskA"
    static let diskBPrefix = "/Volumes/DiskB"

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func endOfDay(_ date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    static func populateMixedLibrary(on store: PhotoIndexStore) async throws {
        try await store.upsertCatalogRow(
            path: path2020,
            sourceId: "src-a",
            modTime: date(2020, 6, 15),
            fileSize: 100
        )
        try await store.updateMetadata(
            path: path2020,
            takenAt: date(2020, 6, 15),
            cameraMake: "Apple",
            cameraModel: "iPhone 11",
            latitude: 48.8566,
            longitude: 2.3522,
            hasGPS: true,
            width: 1000,
            height: 800,
            isScreenshot: false
        )
        try await store.updatePlaceLabel(path: path2020, placeLabel: "Paris, France")

        try await store.upsertCatalogRow(
            path: pathScreenshot,
            sourceId: "src-a",
            modTime: date(2024, 3, 1),
            fileSize: 50
        )
        try await store.updateMetadata(
            path: pathScreenshot,
            takenAt: date(2024, 3, 1),
            cameraMake: nil,
            cameraModel: nil,
            latitude: nil,
            longitude: nil,
            hasGPS: false,
            width: 800,
            height: 600,
            isScreenshot: true
        )

        try await store.upsertCatalogRow(
            path: pathBeach,
            sourceId: "src-b",
            modTime: date(2024, 8, 1),
            fileSize: 200
        )
        try await store.updateMetadata(
            path: pathBeach,
            takenAt: date(2024, 8, 1),
            cameraMake: "Sony",
            cameraModel: "ILCE-7M3",
            latitude: 21.3069,
            longitude: -157.8583,
            hasGPS: true,
            width: 4000,
            height: 3000,
            isScreenshot: false
        )
        try await store.updatePlaceLabel(path: pathBeach, placeLabel: "Honolulu, United States")

        try await store.upsertCatalogRow(
            path: pathOther,
            sourceId: "src-c",
            modTime: date(2022, 1, 1),
            fileSize: 80
        )
        try await store.updateMetadata(
            path: pathOther,
            takenAt: date(2022, 1, 1),
            cameraMake: nil,
            cameraModel: nil,
            latitude: nil,
            longitude: nil,
            hasGPS: false,
            width: nil,
            height: nil,
            isScreenshot: false
        )
    }
}