import AppKit
import Vision

enum AutoRedact {
    /// Canvas-point rects (inside `selection`) of text lines that look sensitive.
    /// Runs on the rendered selection so existing redacts already hide their text and re-runs do not stack.
    static func redactions(in rendered: CGImage, selection: NSRect) throws -> [NSRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Correction would "fix" key-like tokens into dictionary words and hide them from the detector.
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: rendered, options: [:]).perform([request])

        let observations = request.results ?? []
        return observations
            .filter { $0.topCandidates(3).contains { SecretDetector.isSensitive($0.string) } }
            .map { observation -> NSRect in
                let b = observation.boundingBox
                return NSRect(x: selection.minX + b.minX * selection.width,
                              y: selection.minY + b.minY * selection.height,
                              width: b.width * selection.width,
                              height: b.height * selection.height)
                    .insetBy(dx: -2, dy: -2)
                    .intersection(selection)
            }
            .filter { !$0.isNull && !$0.isEmpty }
    }
}
