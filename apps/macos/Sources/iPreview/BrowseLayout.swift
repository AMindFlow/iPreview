import SwiftUI

enum BrowseLayout {
    case grid(columns: Int)
    case list
    case gallery

    func neighbor(of index: Int, toward key: KeyEquivalent, count: Int) -> Int? {
        let destination: Int
        switch (self, key) {
        case (.grid(let columns), .upArrow): destination = index - columns
        case (.grid(let columns), .downArrow): destination = index + columns
        case (.grid(let columns), .leftArrow) where index % columns > 0: destination = index - 1
        case (.grid(let columns), .rightArrow) where index % columns < columns - 1: destination = index + 1
        case (.list, .upArrow), (.gallery, .leftArrow): destination = index - 1
        case (.list, .downArrow), (.gallery, .rightArrow): destination = index + 1
        default: return nil
        }
        return (0..<count).contains(destination) ? destination : nil
    }
}
