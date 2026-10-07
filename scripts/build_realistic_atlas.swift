import AppKit
import CoreGraphics
import Foundation

// Rebuild the 2x menu-bar atlas from the transparent photographic pose sheets.
// Run from the repository root: swift scripts/build_realistic_atlas.swift
private struct Sheet {
    let image: CGImage
    let bitmap: NSBitmapImageRep
    let rows: [Int]
    let columns: [[Int]]

    init(path: String, rows: [Int], columns: [[Int]]) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let bitmap = NSBitmapImageRep(data: data), let image = bitmap.cgImage,
              bitmap.pixelsWide == columns[0].last, bitmap.pixelsHigh == rows.last else {
            throw NSError(domain: "CatoshiAtlas", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid source sheet: \(path)"])
        }
        self.bitmap = bitmap
        self.image = image
        self.rows = rows
        self.columns = columns
    }

    func pose(row: Int, column: Int) -> CGImage {
        let x0 = columns[row][column]
        let x1 = columns[row][column + 1]
        let y0 = rows[row]
        let y1 = rows[row + 1]
        var minX = x1, minY = y1, maxX = x0, maxY = y0
        for y in y0..<y1 {
            for x in x0..<x1 where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        precondition(maxX >= minX && maxY >= minY, "Empty pose \(row), \(column)")
        let rect = CGRect(
            x: max(x0, minX - 2),
            y: max(y0, minY - 2),
            width: min(x1, maxX + 3) - max(x0, minX - 2),
            height: min(y1, maxY + 3) - max(y0, minY - 2)
        )
        guard let crop = image.cropping(to: rect) else { fatalError("Cannot crop pose \(row), \(column)") }
        return crop
    }
}

private struct Frame {
    let name: String
    let x: Int
    let width: Int
    let sheet: Int
    let row: Int
    let column: Int
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sources = root.appendingPathComponent("artwork/realistic")
private let sheets = try [
    Sheet(
        path: sources.appendingPathComponent("calico-poses.png").path,
        rows: [0, 364, 724, 1086],
        columns: [[0, 387, 724, 1067, 1448], [0, 362, 724, 1086, 1448], [0, 367, 724, 1086, 1448]]
    ),
    Sheet(
        path: sources.appendingPathComponent("calico-motion.png").path,
        rows: [0, 362, 724, 1086],
        columns: [[0, 377, 724, 1086, 1448], [0, 394, 757, 1086, 1448], [0, 394, 736, 1086, 1448]]
    ),
    Sheet(
        path: sources.appendingPathComponent("calico-sitting.png").path,
        rows: [0, 724],
        columns: [[0, 543, 1086, 1629, 2172]]
    )
]

// Names and pixel slots match CatoshiAtlasCatalog in CatoshiAssets.swift.
private let frames: [Frame] = [
    .init(name: "idle", x: 0, width: 59, sheet: 0, row: 0, column: 0),
    .init(name: "sit", x: 61, width: 32, sheet: 0, row: 0, column: 1),
    .init(name: "loaf", x: 95, width: 81, sheet: 0, row: 0, column: 2),
    .init(name: "stretch", x: 178, width: 54, sheet: 0, row: 0, column: 3),
    .init(name: "groom", x: 234, width: 36, sheet: 0, row: 1, column: 0),
    .init(name: "sleep", x: 272, width: 77, sheet: 0, row: 1, column: 1),
    .init(name: "happy", x: 351, width: 64, sheet: 0, row: 1, column: 2),
    .init(name: "zoom1", x: 417, width: 82, sheet: 1, row: 0, column: 2),
    .init(name: "zoom2", x: 501, width: 86, sheet: 1, row: 0, column: 3),
    .init(name: "run1", x: 589, width: 65, sheet: 1, row: 0, column: 0),
    .init(name: "run2", x: 656, width: 65, sheet: 1, row: 0, column: 1),
    .init(name: "scared", x: 723, width: 61, sheet: 0, row: 1, column: 3),
    .init(name: "flee", x: 786, width: 98, sheet: 1, row: 1, column: 0),
    .init(name: "turn1", x: 886, width: 45, sheet: 1, row: 1, column: 1),
    .init(name: "turn2", x: 933, width: 32, sheet: 1, row: 1, column: 2),
    .init(name: "turn3", x: 967, width: 45, sheet: 1, row: 1, column: 3),
    .init(name: "walk1", x: 1014, width: 59, sheet: 0, row: 2, column: 0),
    .init(name: "walk2", x: 1075, width: 59, sheet: 0, row: 2, column: 1),
    .init(name: "walk3", x: 1136, width: 59, sheet: 0, row: 2, column: 2),
    .init(name: "walk4", x: 1197, width: 59, sheet: 0, row: 2, column: 3),
    .init(name: "idleBlink", x: 1258, width: 59, sheet: 1, row: 2, column: 0),
    .init(name: "idleEar", x: 1319, width: 59, sheet: 1, row: 2, column: 1),
    .init(name: "idleTail", x: 1380, width: 59, sheet: 1, row: 2, column: 2),
    .init(name: "sitBlink", x: 1441, width: 32, sheet: 2, row: 0, column: 0),
    .init(name: "sitEar", x: 1475, width: 32, sheet: 2, row: 0, column: 1),
    .init(name: "sitTail", x: 1509, width: 32, sheet: 2, row: 0, column: 2),
    .init(name: "loafBlink", x: 1543, width: 81, sheet: 1, row: 2, column: 3)
]

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil, width: 1624, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Cannot create atlas canvas") }
context.interpolationQuality = .high
context.setShouldAntialias(true)

for frame in frames {
    let crop = sheets[frame.sheet].pose(row: frame.row, column: frame.column)
    let scale = min(CGFloat(frame.width - 2) / CGFloat(crop.width), 38 / CGFloat(crop.height))
    let width = CGFloat(crop.width) * scale
    let height = CGFloat(crop.height) * scale
    context.draw(crop, in: CGRect(x: CGFloat(frame.x) + (CGFloat(frame.width) - width) / 2, y: 1, width: width, height: height))
}

guard let atlas = context.makeImage() else {
    fatalError("Cannot encode atlas")
}
let cleaned = NSBitmapImageRep(cgImage: atlas)
let transparent = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0)
var removedPixels = 0
for frame in frames {
    let count = frame.width * 40
    var solid = [Bool](repeating: false, count: count)
    for y in 0..<40 {
        for x in 0..<frame.width {
            let absoluteX = frame.x + x
            let alpha = cleaned.colorAt(x: absoluteX, y: y)?.alphaComponent ?? 0
            if alpha >= 0.12 {
                solid[y * frame.width + x] = true
            } else if alpha > 0 {
                cleaned.setColor(transparent, atX: absoluteX, y: y)
                removedPixels += 1
            }
        }
    }

    var visited = [Bool](repeating: false, count: count)
    for start in 0..<count where solid[start] && !visited[start] {
        var component = [start]
        visited[start] = true
        var cursor = 0
        while cursor < component.count {
            let index = component[cursor]
            let x = index % frame.width
            let y = index / frame.width
            for ny in max(0, y - 1)...min(39, y + 1) {
                for nx in max(0, x - 1)...min(frame.width - 1, x + 1) {
                    let next = ny * frame.width + nx
                    if solid[next] && !visited[next] {
                        visited[next] = true
                        component.append(next)
                    }
                }
            }
            cursor += 1
        }
        if component.count < 6 {
            for index in component {
                cleaned.setColor(transparent, atX: frame.x + index % frame.width, y: index / frame.width)
                removedPixels += 1
            }
        }
    }
}
guard let png = cleaned.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode atlas")
}
let output = root.appendingPathComponent("Resources/CatoshiAtlas_realistic.png")
try png.write(to: output)
print("Realistic Catoshi atlas: \(output.path); \(frames.count) frames; 1624x40; \(removedPixels) stray pixels removed")
