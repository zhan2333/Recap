//
//  TextbookImporter.swift
//  AnalysisKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation
import PDFKit
import Vision

/// Extracts full text from a textbook PDF. Pages with a real text layer use
/// it directly; scanned pages fall back to Vision OCR. Output keeps PDF page
/// markers so answers can cite where they came from.
public struct TextbookImporter {

    public enum ImportError: Error, LocalizedError {
        case cannotOpen(URL)

        public var errorDescription: String? {
            switch self {
            case .cannotOpen(let url): "无法打开 PDF：\(url.lastPathComponent)"
            }
        }
    }

    /// - Parameter onProgress: (finishedPages, totalPages), called on an arbitrary thread.
    public static func extractText(
        from pdfURL: URL,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> String {
        guard let document = PDFDocument(url: pdfURL) else {
            throw ImportError.cannotOpen(pdfURL)
        }
        let pageCount = document.pageCount

        return try await Task.detached(priority: .userInitiated) {
            var output = ""
            for index in 0..<pageCount {
                guard let page = document.page(at: index) else { continue }
                let layerText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let text: String
                if layerText.count >= 50 {
                    text = layerText
                } else {
                    text = Self.ocr(page: page)
                }
                if !text.isEmpty {
                    output += "【第\(index + 1)页】\n\(text)\n\n"
                }
                onProgress?(index + 1, pageCount)
            }
            return output
        }.value
    }

    private static func ocr(page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return "" }
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        #endif

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return "" }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
