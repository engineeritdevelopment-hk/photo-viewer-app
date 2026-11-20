import Foundation

/// Next/previous and position label for the fullscreen viewer.
enum ViewerNavigation {
    static func steppedPath(from path: String, in paths: [String], by delta: Int) -> String? {
        guard let index = paths.firstIndex(of: path) else { return nil }
        let next = index + delta
        guard paths.indices.contains(next) else { return nil }
        return paths[next]
    }

    static func positionLabel(path: String, paths: [String]) -> String? {
        guard let index = paths.firstIndex(of: path) else { return nil }
        return "\(index + 1) of \(paths.count)"
    }
}
