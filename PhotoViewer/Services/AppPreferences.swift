import Foundation

enum AppPreferences {
    private static let lastOpenedProjectIdKey = "lastOpenedProjectId"
    static let showPeopleBarKey = "showPeopleBar"
    static let photoSortKey = "photoSort"

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
}