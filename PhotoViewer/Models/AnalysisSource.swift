import Foundation

enum AnalysisSource: String, Codable, Sendable, CaseIterable {
    case metadata = "Metadata"
    case ocrAndNLP = "OCR + NLP"
    case onDeviceAI = "On-Device AI"

    var badgeColorName: String {
        switch self {
        case .metadata: return "gray"
        case .ocrAndNLP: return "blue"
        case .onDeviceAI: return "purple"
        }
    }
}

enum SemanticFolders {
    static let anchors: [String: [String]] = [
        "Food": [
            "food", "meal", "dish", "cuisine", "restaurant", "dining", "breakfast", "lunch", "dinner",
            "dessert", "pizza", "sushi", "bakery", "grocery", "kitchen", "cooking", "recipe", "snack",
            "barbecue", "noodle", "seafood", "salad", "sandwich", "cake", "coffee", "wine", "beer",
            "fruit", "vegetable", "burger", "pasta", "steak", "brunch", "takeout", "menu",
        ],
        "Finance & Receipts": ["invoice", "receipt", "payment", "tax", "bank", "finance", "bill"],
        "Work & Projects": ["project", "meeting", "report", "work", "client", "proposal", "contract"],
        "Travel & Tickets": ["flight", "hotel", "travel", "ticket", "itinerary", "booking", "passport"],
        "Study & Notes": ["study", "notes", "lecture", "homework", "course", "research", "essay"],
        "Screenshots": ["screenshot", "screen", "capture", "snapshot"],
        "Media": ["photo", "video", "music", "audio", "movie", "picture"],
        "Archives": ["archive", "zip", "backup", "compressed"],
        "Installers": ["install", "setup", "dmg", "package"],
        "Code": ["code", "swift", "python", "script", "developer", "git"],
        "Events": [
            "wedding", "ceremony", "celebration", "party", "festival", "concert", "parade",
            "banquet", "bouquet",
        ],
        "Nature": [
            "plant", "flower", "tree", "animal", "bird", "dog", "cat", "landscape", "mountain",
            "beach", "ocean", "sky", "sunset", "wildlife",
        ],
        "Places": [
            "building", "structure", "architecture", "cityscape", "skyline", "temple", "church",
            "bridge", "room",
        ],
        "People": [
            "people", "person", "adult", "child", "baby", "portrait", "crowd", "bride", "groom",
            "face", "suit", "gown", "kimono",
        ],
    ]

    /// Specific scenes win over generic ones. Dictionary order is not reliable.
    static let matchPriority: [String] = [
        "Finance & Receipts",
        "Travel & Tickets",
        "Work & Projects",
        "Study & Notes",
        "Code",
        "Archives",
        "Installers",
        "Food",
        "Events",
        "Nature",
        "Places",
        "People",
        "Screenshots",
        "Media",
    ]

    static let defaultFolder = "Other"

    /// First priority folder whose keyword appears in `text` (case-insensitive substring).
    static func matchCategory(in text: String) -> String? {
        let lowered = text.lowercased()
        for folder in matchPriority {
            guard let keywords = anchors[folder] else { continue }
            if keywords.contains(where: { lowered.contains($0) }) {
                return folder
            }
        }
        return nil
    }
}

enum TypeFolders {
    static func folder(for category: String) -> String {
        category
    }
}