import SwiftUI
import Testing

@testable import MarkdownView

/// numen fork (gemma4-qat#1765): a right-to-left table draws every cell border on its own column
/// (#1746's M3: under right-to-left the borders were placed with `.offset`, which mirrors, from
/// cell frames in physical points, and some dividers vanished or moved).
@MainActor
@Suite("Markdown Table Direction")
struct MarkdownTableDirectionTests {
    @Test("Every column edge has a full-height border", .tags(.rendering), arguments: [
        ("| a | bbbbbbbb | c |\n|---|---|---|\n| 1 | 2 | 33333333 |\n| 4 | 5 | 6 |", LayoutDirection.leftToRight),
        ("| a | bbbbbbbb | c |\n|---|---|---|\n| 1 | 2 | 33333333 |\n| 4 | 5 | 6 |", .rightToLeft),
        ("| ا | بببببببب | ج |\n|---|---|---|\n| 1 | 2 | 33333333 |\n| 4 | 5 | 6 |", .leftToRight),
        ("| ا | بببببببب | ج |\n|---|---|---|\n| 1 | 2 | 33333333 |\n| 4 | 5 | 6 |", .rightToLeft),
    ])
    func borders(markdown: String, layoutDirection: LayoutDirection) throws {
        let view = MarkdownView(markdown)
            .markdownTableStyle(.github)
            .frame(width: 400)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.layoutDirection, layoutDirection)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        // Three columns: two outer edges and two dividers.
        #expect(Self.borderColumns(in: image).count == 4)
    }

    @Test("A numeric table in a right-to-left quote keeps a left column on the left", .tags(.rendering), arguments: [
        LayoutDirection.leftToRight, .rightToLeft,
    ])
    func inheritedDirectionColumnAlignment(layoutDirection: LayoutDirection) throws {
        // The table has no strong letter and lays out in the quote's direction (right to left);
        // `:---` keeps the column's text on the physical left (Codex P2 on numen-tech/MarkdownView#8).
        let view = MarkdownView("> مرحبا\n>\n> | 8888888888 |\n> |:---|\n> | 8 |")
            .markdownTableStyle(.github)
            .frame(width: 400)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.layoutDirection, layoutDirection)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let lines = Self.inkLines(in: image)
        try #require(lines.count >= 3)
        let header = lines[lines.count - 2], body = lines[lines.count - 1]
        // Left-aligned: the short cell starts where the long one does, not where it ends.
        #expect(abs(body.minX - header.minX) < abs(body.maxX - header.maxX))
        #expect(abs(body.minX - header.minX) <= 4)
    }

    /// The horizontal extent of each band of dark (text) pixels, top to bottom.
    static func inkLines(in image: CGImage) -> [(minX: Int, maxX: Int)] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var lines: [(minX: Int, maxX: Int)] = []
        var inLine = false
        for y in 0..<height {
            var minX = Int.max, maxX = -1
            for x in 0..<width {
                let i = (y * width + x) * 4
                if data[i] < 110, data[i + 1] < 110, data[i + 2] < 110 { minX = min(minX, x); maxX = max(maxX, x) }
            }
            if maxX >= 0 {
                if inLine { lines[lines.count - 1] = (min(lines[lines.count - 1].minX, minX), max(lines[lines.count - 1].maxX, maxX)) }
                else { lines.append((minX, maxX)) }
                inLine = true
            } else {
                inLine = false
            }
        }
        return lines
    }

    /// The x positions where a light blue-grey border line runs over more than half the image
    /// height, adjacent pixel columns merged.
    static func borderColumns(in image: CGImage) -> [Int] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var columns: [Int] = []
        for x in 0..<width {
            var count = 0
            for y in 0..<height {
                let i = (y * width + x) * 4
                let (r, b) = (Int(data[i]), Int(data[i + 2]))
                // GitHub's border colour at half opacity over white is about (232, 236, 240):
                // bluer than the grey of anti-aliased text.
                if r > 195, r < 250, b - r >= 4 { count += 1 }
            }
            if count * 2 > height, columns.last.map({ x - $0 > 1 }) ?? true { columns.append(x) }
            else if count * 2 > height { columns[columns.count - 1] = x }
        }
        return columns
    }
}
