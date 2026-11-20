import Foundation

enum AppPreferences {
    private static let lastOpenedProjectIdKey = "lastOpenedProjectId"
    static let showPeopleBarKey = "showPeopleBar"
    static let photoSortKey = "photoSort"
    static let sourceFolderViewKey = "sourceFolderView"

    static var sourceFolderView: SourceFolderView {
        get {
            guard let raw = UserDefaults.standard.string(forKey: sourceFolderViewKey),
                  let value = SourceFolderView(rawValue: raw) else {
                return .allNested
            }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sourceFolderViewKey) }
    }
    private static let lastUpdateCheckKey = "lastAutomaticUpdateCheckDate"

    static var showPeopleBar: Bool {
        get {
            if UserDefaults.standard.object(forKey: showPeopleBarKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: showPeopleBarKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showPeopleBarKey) }
    }

    static var lastOpenedProjectId: String? {
        get { UserDefaults.standard.string(forKey: lastOpenedProjectIdKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: lastOpenedProjectIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastOpenedProjectIdKey)
            }
        }
    }

    static func shouldRunAutomaticUpdateCheck() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) >= UpdateConfiguration.automaticCheckInterval
    }

    static func recordAutomaticUpdateCheck() {
        UserDefaults.standard.set(Date(), forKey: lastUpdateCheckKey)
    }

}