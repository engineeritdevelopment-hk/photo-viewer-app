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
    ]

    static let defaultFolder = "Other"

    /// First anchor folder whose keyword appears in `text` (case-insensitive substring).
    static func matchCategory(in text: String) -> String? {
        let lowered = text.lowercased()
        for (folder, keywords) in anchors {
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