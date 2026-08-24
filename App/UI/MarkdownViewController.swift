//
//  MarkdownViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import WebKit
import UniformTypeIdentifiers

// Renders a Markdown document and exports it as a paginated PDF
final class MarkdownViewController: UIViewController {

    private let markdown: String
    private let documentTitle: String
    private let webView = WKWebView()

    init(markdown: String, title: String) {
        self.markdown = markdown
        self.documentTitle = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        // Regex-pass conversion is heavy for a 900KB textbook — render off the main thread
        let source = markdown
        Task.detached(priority: .userInitiated) { [weak self] in
            let html = Self.html(from: source)
            await MainActor.run { [weak self] in
                self?.webView.loadHTMLString(html, baseURL: nil)
            }
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.exportPDF() }
        )
    }

    // MARK: - PDF export

    private func exportPDF() {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)

        // A4 at 72 dpi with 36 pt margins
        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper.insetBy(dx: 36, dy: 36), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, .zero, nil)
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(documentTitle).pdf")
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        present(picker, animated: true)
    }

    // MARK: - Markdown → HTML

    // Minimal converter for the subset our prompts constrain the model to: #/##/### headings, - lists, > quotes, **bold**, `code`, paragraphs.
    static func html(from markdown: String) -> String {
        var body = ""
        var inList = false
        var inQuote = false

        func closeBlocks() {
            if inList { body += "</ul>\n"; inList = false }
            if inQuote { body += "</blockquote>\n"; inQuote = false }
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                closeBlocks()
                continue
            }
            if line.hasPrefix("### ") {
                closeBlocks()
                body += "<h3>\(inline(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("## ") {
                closeBlocks()
                body += "<h2>\(inline(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("# ") {
                closeBlocks()
                body += "<h1>\(inline(String(line.dropFirst(2))))</h1>\n"
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if inQuote { body += "</blockquote>\n"; inQuote = false }
                if !inList { body += "<ul>\n"; inList = true }
                body += "<li>\(inline(String(line.dropFirst(2))))</li>\n"
            } else if line.hasPrefix("> ") || line == ">" {
                if inList { body += "</ul>\n"; inList = false }
                if !inQuote { body += "<blockquote>\n"; inQuote = true }
                body += "<p>\(inline(String(line.dropFirst(min(2, line.count)))))</p>\n"
            } else {
                closeBlocks()
                body += "<p>\(inline(line))</p>\n"
            }
        }
        closeBlocks()

        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { font-family: -apple-system, 'PingFang SC', sans-serif; line-height: 1.75;
               max-width: 720px; margin: 0 auto; padding: 28px 24px 60px;
               color: #1d1d1f; background: #fff; }
        @media (prefers-color-scheme: dark) {
            body { color: #e8e8ed; background: #1c1c1e; }
            h2 { border-color: #3a3a3c; }
            blockquote { background: #2c2c2e; border-color: #48484a; }
            code { background: #2c2c2e; }
        }
        h1 { font-size: 26px; }
        h2 { font-size: 20px; margin-top: 1.6em; padding-bottom: 6px; border-bottom: 1px solid #e5e5ea; }
        h3 { font-size: 17px; margin-top: 1.2em; }
        blockquote { margin: 10px 0; padding: 8px 14px; background: #f5f5f7;
                     border-left: 3px solid #c7c7cc; border-radius: 4px; }
        blockquote p { margin: 4px 0; }
        li { margin: 4px 0; }
        code { background: #f5f5f7; padding: 1px 5px; border-radius: 4px; font-size: 0.92em; }
        </style></head><body>\(body)</body></html>
        """
    }

    private static func inline(_ text: String) -> String {
        var escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        // **bold**
        while let range = escaped.range(of: #"\*\*([^*]+)\*\*"#, options: .regularExpression) {
            let content = String(escaped[range]).dropFirst(2).dropLast(2)
            escaped.replaceSubrange(range, with: "<strong>\(content)</strong>")
        }
        // `code`
        while let range = escaped.range(of: #"`([^`]+)`"#, options: .regularExpression) {
            let content = String(escaped[range]).dropFirst(1).dropLast(1)
            escaped.replaceSubrange(range, with: "<code>\(content)</code>")
        }
        return escaped
    }
}
