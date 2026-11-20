import Foundation
import CoreGraphics

/// Physical page sizes for notebooks, measured in PostScript points (1/72 inch).
enum PaperSize: String, Codable, CaseIterable, Identifiable {
    case letter
    case a4
    case a5
    case legal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .letter: "Letter (8.5 × 11 in)"
        case .a4: "A4 (210 × 297 mm)"
        case .a5: "A5 (148 × 210 mm)"
        case .legal: "Legal (8.5 × 14 in)"
        }
    }

    var size: CGSize {
        switch self {
        case .letter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .a5: CGSize(width: 419.53, height: 595.28)
        case .legal: CGSize(width: 612, height: 1008)
        }
    }
}

/// The printed pattern on a notebook page.
enum PaperStyle: String, Codable, CaseIterable, Identifiable {
    case blank
    case ruled
    case grid
    case dotted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: "Blank"
        case .ruled: "Ruled"
        case .grid: "Grid"
        case .dotted: "Dotted"
        }
    }

    var systemImageName: String {
        switch self {
        case .blank: "doc"
        case .ruled: "line.3.horizontal"
        case .grid: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        }
    }
}
