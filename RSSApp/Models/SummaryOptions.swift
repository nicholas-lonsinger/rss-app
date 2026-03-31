import Foundation

enum SummaryLength: String, CaseIterable, Hashable {
    case brief = "Brief"
    case standard = "Standard"
    case detailed = "Detailed"

    var maxTokens: Int {
        switch self {
        case .brief: return 80
        case .standard: return 200
        case .detailed: return 450
        }
    }

    var promptInstruction: String {
        switch self {
        case .brief: return "1–2 sentences"
        case .standard: return "one paragraph"
        case .detailed: return "2–3 paragraphs"
        }
    }
}

enum SummaryFormat: String, CaseIterable, Hashable {
    case prose = "Prose"
    case bullets = "Bullets"

    var promptInstruction: String {
        switch self {
        case .prose: return "as flowing prose"
        case .bullets: return "as a markdown bulleted list (use - for each item)"
        }
    }
}

struct SummaryOptions: Hashable {
    var length: SummaryLength = .standard
    var format: SummaryFormat = .prose
}
