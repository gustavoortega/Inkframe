import AppKit
import Vision

enum AutoRedact {
    /// Vision downsamples large images and drops small text, so a full-screen capture is read in tiles of about this size.
    private static let tileSide: CGFloat = 1600
    /// Overlap per side, as a fraction of the image, so a line cut by a tile border is whole in the neighbour.
    private static let tileOverlap: CGFloat = 0.04

    /// Canvas-point rects (inside `selection`) of text lines that look sensitive.
    /// Runs on the rendered selection so existing redacts already hide their text and re-runs do not stack.
    static func redactions(in rendered: CGImage, selection: NSRect) throws -> [NSRect] {
        let handler = VNImageRequestHandler(cgImage: rendered, options: [:])
        var boxes: [CGRect] = []
        for tile in tiles(width: CGFloat(rendered.width), height: CGFloat(rendered.height)) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Correction would "fix" key-like tokens into dictionary words and hide them from the detector.
            request.usesLanguageCorrection = false
            request.regionOfInterest = tile
            try handler.perform([request])
            boxes += (request.results ?? [])
                .filter { $0.topCandidates(3).contains { SecretDetector.isSensitive($0.string) } }
                // Boxes are normalized to the region of interest, not the whole image.
                .map { b in
                    CGRect(x: tile.minX + b.boundingBox.minX * tile.width,
                           y: tile.minY + b.boundingBox.minY * tile.height,
                           width: b.boundingBox.width * tile.width,
                           height: b.boundingBox.height * tile.height)
                }
        }
        var seen = Set<[Int]>()
        return boxes
            .map { b -> NSRect in
                NSRect(x: selection.minX + b.minX * selection.width,
                       y: selection.minY + b.minY * selection.height,
                       width: b.width * selection.width,
                       height: b.height * selection.height)
                    .insetBy(dx: -2, dy: -2)
                    .intersection(selection)
            }
            .filter { !$0.isNull && !$0.isEmpty }
            // Overlapping tiles report the same line twice; the toast count should not.
            .filter { seen.insert([$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) }).inserted }
    }

    /// Normalized regions of interest covering the image.
    private static func tiles(width: CGFloat, height: CGFloat) -> [CGRect] {
        let columns = max(1, Int((width / tileSide).rounded(.up)))
        let rows = max(1, Int((height / tileSide).rounded(.up)))
        var result: [CGRect] = []
        for column in 0..<columns {
            for row in 0..<rows {
                let minX = max(0, CGFloat(column) / CGFloat(columns) - tileOverlap)
                let maxX = min(1, CGFloat(column + 1) / CGFloat(columns) + tileOverlap)
                let minY = max(0, CGFloat(row) / CGFloat(rows) - tileOverlap)
                let maxY = min(1, CGFloat(row + 1) / CGFloat(rows) + tileOverlap)
                result.append(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
            }
        }
        return result
    }
}
