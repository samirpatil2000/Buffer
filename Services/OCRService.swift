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
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("[Buffer OCR] Recognition error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Collect the top candidate from each observation
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                if recognizedStrings.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    let fullText = recognizedStrings.joined(separator: "\n")
                    continuation.resume(returning: fullText)
                }
            }
            
            // Use accurate recognition for best results
            request.recognitionLevel = .accurate
            // Support multiple languages automatically
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    print("[Buffer OCR] Handler error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
