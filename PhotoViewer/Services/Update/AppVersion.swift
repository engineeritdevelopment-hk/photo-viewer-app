import Foundation

/// Marketing version (`CFBundleShortVersionString`), compared numerically by component.
struct AppVersion: Comparable, Sendable {
    let components: [Int]

    var displayString: String {
        components.map(String.init).joined(separator: ".")
    }

    static func current() -> AppVersion? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        return parse(raw)
    }

    static func parse(_ raw: String) -> AppVersion? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }

        var components: [Int] = []
        for piece in trimmed.split(separator: ".") {
            let digits = piece.prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits) else { return nil }
            components.append(value)
        }
        guard !components.isEmpty else { return nil }
        return AppVersion(components: components)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< maxCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}