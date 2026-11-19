import Foundation
import AppKit
import Vision
import os

/// Service for extracting text from images using Apple's Vision framework (on-device OCR)
class OCRService {
    static let shared = OCRService()

    /// Failures are written to the unified log (not print, which a GUI app discards) so the real
    /// reason is visible later with: log show --predicate 'category == "OCR"' --last 1d
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.samirpatil.Buffer", category: "OCR")

    private init() {}

    enum OCRError: LocalizedError {
        case unreadableImage

        var errorDescription: String? { "The image could not be converted for text recognition." }
    }

    /// What OCR concluded for an item's images, kept separate from "no text" on purpose. A failed
    /// run says nothing about whether the image has text, so it must not be stored as "no text".
    enum Summary: Equatable {
        case found([String])
        case noText
        case failed

        /// What auto-OCR persists for this verdict, or nil to leave the item unprocessed so it is
        /// retried. The empty string is the no-text sentinel, deliberately distinct from the manual
        /// button's human-facing "No text found" message, because that message is itself text that
        /// could spuriously match a search. Pieces are joined with blank lines so several pictures
        /// stay individually searchable.
        var storedText: String? {
            switch self {
            case .found(let pieces): return pieces.joined(separator: "\n\n")
            case .noText: return ""
            case .failed: return nil
            }
        }
    }

    /// Fold the per-image outcomes into one verdict. Any recognized text wins (partial results are
    /// still searchable), and a failure only matters when nothing was found, because then we cannot
    /// claim the images have no text.
    static func summarize(_ outcomes: [Result<String?, Error>]) -> Summary {
        let pieces = outcomes.compactMap { outcome -> String? in
            if case .success(let text?) = outcome, !text.isEmpty { return text }
            return nil
        }
        if !pieces.isEmpty { return .found(pieces) }

        let anyFailed = outcomes.contains { outcome in
            if case .failure = outcome { return true }
            return false
        }
        return anyFailed ? .failed : .noText
    }

    /// OCR every image and summarize. Images are processed one after another, never in parallel.
    func recognize(_ images: [NSImage]) async -> Summary {
        var outcomes: [Result<String?, Error>] = []
        for image in images {
            do {
                outcomes.append(.success(try await recognizeText(from: image)))
            } catch {
                outcomes.append(.failure(error))
            }
        }
        return OCRService.summarize(outcomes)
    }

    /// Recognize text in an image asynchronously
    /// - Parameter image: The NSImage to extract text from
    /// - Returns: Recognized text string, or nil if the image was processed and has no text
    /// - Throws: When the image could not be processed at all (distinct from "no text found")
    func recognizeText(from image: NSImage) async throws -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            OCRService.log.error("OCR skipped: could not get a CGImage from the NSImage")
            throw OCRError.unreadableImage
        }
        let dimensions = "\(cgImage.width)x\(cgImage.height)"

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // No completion handler on purpose. When Vision fails it reports the error through
                // BOTH the request's completion handler and the error thrown by perform(), so a
                // handler that resumes the continuation plus a catch that resumes it again trapped
                // the whole app ("resume called twice") on any image Vision could not process.
                // Reading results after perform() returns leaves a single path that resumes once.
                let request = VNRecognizeTextRequest()
                // Use accurate recognition for best results
                request.recognitionLevel = .accurate
                // Support multiple languages automatically
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    OCRService.log.error("OCR failed for \(dimensions, privacy: .public) image: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                    return
                }

                // Collect the top candidate from each observation
                let recognizedStrings = (request.results ?? []).compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: recognizedStrings.isEmpty ? nil : recognizedStrings.joined(separator: "\n"))
            }
        }
    }
}
