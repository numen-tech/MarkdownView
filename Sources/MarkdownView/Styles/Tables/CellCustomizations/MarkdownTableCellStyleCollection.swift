//
//  MarkdownTableCellStyleCollection.swift
//  MarkdownView
//
//  Created by Yanan Li on 2025/4/18.
//

import SwiftUI

@dynamicMemberLookup
struct MarkdownTableCellStyleCollection: Sendable {
    typealias Storage = [MarkdownTableCellStyle.Position : MarkdownTableCellStyle]
    fileprivate var storage: Storage = [:] {
        willSet { cacheBox.reset() }
    }
    
    private class CacheBox: /* NSLock */ @unchecked Sendable {
        enum CacheKey: Hashable {
            case minXs
            case maxXs
            case minYs
            case maxYs
            case widths
            case heights
            case cells
            case offsets(MarkdownTableCellStyle.Position)
        }
        
        private var caches: [CacheKey : Any] = [:]
        private let lock = NSLock()
        
        subscript(key: CacheKey) -> Any? {
            lock.lock()
            defer { lock.unlock() }
            return caches[key]
        }
        
        func updateValue(_ value: Any, forKey key: CacheKey) {
            lock.lock()
            caches[key] = value
            lock.unlock()
        }
        
        func reset() {
            lock.lock()
            caches = [:]
            lock.unlock()
        }
    }
    private var cacheBox = CacheBox()
    
    subscript<T>(dynamicMember keyPath: KeyPath<Storage, T>) -> T {
        storage[keyPath: keyPath]
    }
    
    subscript(storageKey: MarkdownTableCellStyle.Position) -> MarkdownTableCellStyle? {
        get { storage[storageKey] }
        set { storage[storageKey] = newValue }
    }
    
    var cells: [MarkdownTableCellStyle] {
        if let cached = cacheBox[.cells] {
            return cached as! [MarkdownTableCellStyle]
        }
        
        let cells = Array(storage.values)
        cacheBox.updateValue(cells, forKey: .cells)
        return cells
    }
    
    var minXs: [CGFloat] {
        if let cached = cacheBox[.minXs] {
            return cached as! [CGFloat]
        }
        
        let columns = Set(cells.map(\.position.column)).count
        let minXs = (0..<columns).map { column in
            cells.filter { $0.position.column == column }.map(\.rect.minX).min() ?? 0
        }
        cacheBox.updateValue(minXs, forKey: .minXs)
        return minXs
    }
    
    var maxXs: [CGFloat] {
        if let cached = cacheBox[.maxXs] {
            return cached as! [CGFloat]
        }
        
        let columns = Set(cells.map(\.position.column)).count
        let maxXs = (0..<columns).map { column in
            cells.filter { $0.position.column == column }.map(\.rect.maxX).max() ?? 0
        }
        cacheBox.updateValue(maxXs, forKey: .maxXs)
        return maxXs
    }
    
    var minYs: [CGFloat] {
        if let cached = cacheBox[.minYs] {
            return cached as! [CGFloat]
        }
        
        let rows = Set(cells.map(\.position.row)).count
        let minYs = (0..<rows).map { row in
            cells.filter { $0.position.row == row }.map(\.rect.minY).min() ?? 0
        }
        cacheBox.updateValue(minYs, forKey: .minYs)
        return minYs
    }
    
    var maxYs: [CGFloat] {
        if let cached = cacheBox[.maxYs] {
            return cached as! [CGFloat]
        }
        
        let rows = Set(cells.map(\.position.row)).count
        let maxYs = (0..<rows).map { row in
            cells.filter { $0.position.row == row }.map(\.rect.maxY).max() ?? 0
        }
        cacheBox.updateValue(maxYs, forKey: .maxYs)
        return maxYs
    }
    
    var widths: [CGFloat] {
        if let cached = cacheBox[.widths] {
            return cached as! [CGFloat]
        }
        
        let normalWidths = zip(maxXs, minXs).map(-)
        
        var widths = normalWidths
        // numen fork (gemma4-qat#1765): each column reaches the near edge of the next one. Cell
        // frames are physical, so under a right-to-left layout the next column lies to the left
        // and the gap is on this column's left side.
        for index in widths.indices.dropLast() {
            widths[index] += Self.isReversed(at: index, minXs: minXs)
                ? minXs[index] - maxXs[index + 1]
                : minXs[index + 1] - maxXs[index]
        }
        cacheBox.updateValue(widths, forKey: .widths)
        return widths
    }
    
    var heights: [CGFloat] {
        if let cached = cacheBox[.heights] {
            return cached as! [CGFloat]
        }
        
        let normalHeights = zip(maxYs, minYs).map(-)
        
        var heights = normalHeights
        let additionalHeights = zip(minYs.dropFirst(), maxYs.dropLast()).map(-)
        
        for (index, additionalHeight) in additionalHeights.enumerated() {
            heights[index] += additionalHeight
        }
        cacheBox.updateValue(heights, forKey: .heights)
        return heights
    }
    
    /// Whether column `index + 1` lies to the left of column `index` (a right-to-left table).
    private static func isReversed(at index: Int, minXs: [CGFloat]) -> Bool {
        index + 1 < minXs.count && minXs[index + 1] < minXs[index]
    }

    func offset(for position: MarkdownTableCellStyle.Position) -> CGSize {
        guard storage[position] != nil else { return .zero }
        
        if let cached = cacheBox[.offsets(position)] {
            return cached as! CGSize
        }
        
        // numen fork (gemma4-qat#1765): a right-to-left column's span starts at the next
        // column's right edge (`widths`). Physical points: the layers are drawn left to right.
        let column = position.column
        let x = column + 1 < minXs.count && Self.isReversed(at: column, minXs: minXs)
            ? maxXs[column + 1]
            : minXs[column]
        let offset = CGSize(
            width: x,
            height: minYs[position.row]
        )
        cacheBox.updateValue(offset, forKey: .offsets(position))
        return offset
    }
}

// MARK: - Preference Key

struct MarkdownTableCellStyleCollectionPreference: PreferenceKey {
    static let defaultValue: MarkdownTableCellStyleCollection = MarkdownTableCellStyleCollection()
    
    static func reduce(value: inout MarkdownTableCellStyleCollection, nextValue: () -> MarkdownTableCellStyleCollection) {
        value.storage.merge(nextValue().storage, uniquingKeysWith: { $1 })
    }
}

