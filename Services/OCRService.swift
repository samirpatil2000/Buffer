import Foundation
import AppKit
import Vision

/// Service for extracting text from images using Apple's Vision framework (on-device OCR)
class OCRService {
    static let shared = OCRService()
    
    private init() {}
    
    /// Recognize text in an image asynchronously
    /// - Parameter image: The NSImage to extract text from
    /// - Returns: Recognized text string, or nil if no text found
    func recognizeText(from image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("[Buffer OCR] Failed to get CGImage from NSImage")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
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
                    print("[Buffer OCR] Recognition error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
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
