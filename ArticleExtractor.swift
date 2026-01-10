//
//  ArticleExtractor.swift
//  2 Music 2 Furious
//
//  Extracts article content from web pages using Mozilla's Readability.js
//  Then parses the clean HTML into plain text + formatting spans using SwiftSoup
//
//  SETUP REQUIRED:
//  1. Add SwiftSoup via SPM: https://github.com/scinfu/SwiftSoup
//  2. Add Readability.js to your bundle (see instructions in project)
//

import Foundation
import WebKit
import SwiftSoup

// MARK: - Article Extractor

/// Extracts clean article content from web pages using Readability.js
/// and converts to plain text with formatting spans for TTS-synced rich display
class ArticleExtractor: NSObject {
    
    enum ExtractionError: LocalizedError {
        case invalidURL
        case networkError(String)
        case readabilityFailed
        case noContent
        case parsingError(String)
        case resourceNotFound(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .networkError(let msg): return "Network error: \(msg)"
            case .readabilityFailed: return "Could not extract article content"
            case .noContent: return "No readable content found"
            case .parsingError(let msg): return "Parsing error: \(msg)"
            case .resourceNotFound(let name): return "Missing resource: \(name)"
            }
        }
    }
    
    /// Result from Readability.js extraction
    struct ReadabilityResult {
        let title: String
        let author: String?
        let content: String  // Clean HTML
        let excerpt: String?
    }
    
    /// Result from full extraction pipeline
    struct ExtractionResult {
        let title: String
        let author: String?
        let plainText: String
        let formattingSpans: [FormattingSpan]
    }
    
    // MARK: - Main Extraction Method
    
    /// Extracts article content from a URL
    /// Uses Readability.js via WKWebView, then SwiftSoup to parse
    static func extract(from url: URL) async throws -> Article {
        // Step 1: Fetch and run Readability.js
        let readabilityResult = try await extractWithReadability(url: url)
        
        // Step 2: Parse clean HTML into text + spans with SwiftSoup
        let parsed = try parseHTMLWithSwiftSoup(
            html: readabilityResult.content,
            baseURL: url
        )
        
        // Step 3: Build Article
        let chapter = ArticleChapter(
            title: readabilityResult.title,
            content: parsed.plainText,
            formattingSpans: parsed.spans
        )
        
        return Article(
            title: readabilityResult.title,
            source: url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web",
            sourceURL: url,
            author: readabilityResult.author,
            chapters: [chapter]
        )
    }
    
    // MARK: - Readability.js Extraction
    
    /// Uses WKWebView to load page and run Readability.js
    private static func extractWithReadability(url: URL) async throws -> ReadabilityResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let extractor = ReadabilityWebViewExtractor(url: url) { result in
                    continuation.resume(with: result)
                }
                extractor.start()
            }
        }
    }
    
    // MARK: - SwiftSoup HTML Parsing

    struct ParsedHTML {
        let plainText: String
        let spans: [FormattingSpan]
    }

    /// Parses clean HTML from Readability into plain text + formatting spans
    static func parseHTMLWithSwiftSoup(html: String, baseURL: URL?) throws -> ParsedHTML {
        // First decode any HTML entities in the raw HTML before parsing
        let decodedHTML = decodeHTMLEntities(html)
        let doc = try SwiftSoup.parse(decodedHTML)

        var plainText = ""
        var spans: [FormattingSpan] = []

        // Process the body (or root element)
        if let body = doc.body() {
            var needsSpaceBefore = false
            try processNode(body, plainText: &plainText, spans: &spans, baseURL: baseURL, activeStyles: [], needsSpaceBefore: &needsSpaceBefore)
        }

        // Clean up trailing whitespace
        plainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Final newline cleanup - collapse 3+ newlines into 2
        while plainText.contains("\n\n\n") {
            plainText = plainText.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Final pass: decode any remaining HTML entities in the plain text
        plainText = decodeHTMLEntities(plainText)

        return ParsedHTML(plainText: plainText, spans: spans)
    }

    /// Decodes HTML entities like &#x27; &amp; &quot; etc. to their actual characters
    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string

        // Decode numeric entities (hex): &#x27; &#x2019; etc.
        let hexPattern = "&#x([0-9A-Fa-f]+);"
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range).reversed()
            for match in matches {
                if let hexRange = Range(match.range(at: 1), in: result),
                   let codePoint = UInt32(result[hexRange], radix: 16),
                   let scalar = Unicode.Scalar(codePoint) {
                    let char = String(Character(scalar))
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: char)
                    }
                }
            }
        }

        // Decode numeric entities (decimal): &#39; &#8217; etc.
        let decPattern = "&#([0-9]+);"
        if let regex = try? NSRegularExpression(pattern: decPattern) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range).reversed()
            for match in matches {
                if let decRange = Range(match.range(at: 1), in: result),
                   let codePoint = UInt32(result[decRange]),
                   let scalar = Unicode.Scalar(codePoint) {
                    let char = String(Character(scalar))
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: char)
                    }
                }
            }
        }

        // Decode common named entities
        let namedEntities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&ndash;": "–",
            "&mdash;": "—",
            "&lsquo;": "'",
            "&rsquo;": "'",
            "&ldquo;": "\u{201C}",
            "&rdquo;": "\u{201D}",
            "&hellip;": "…",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™",
            "&bull;": "•",
            "&middot;": "·",
            "&times;": "×",
            "&divide;": "÷",
            "&euro;": "€",
            "&pound;": "£",
            "&yen;": "¥",
            "&cent;": "¢",
        ]

        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        return result
    }
    
    /// Recursively processes DOM nodes, building plain text and tracking formatting
    private static func processNode(
        _ node: Node,
        plainText: inout String,
        spans: inout [FormattingSpan],
        baseURL: URL?,
        activeStyles: [(style: FormattingStyle, start: Int, url: String?)],
        needsSpaceBefore: inout Bool
    ) throws {

        // Handle text nodes
        if let textNode = node as? TextNode {
            let text = textNode.text()

            // Collapse whitespace but preserve structure
            let cleaned = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

            // Check if this text node is whitespace-only (important for spacing between inline elements)
            let isWhitespaceOnly = cleaned.trimmingCharacters(in: .whitespaces).isEmpty

            if isWhitespaceOnly {
                // Mark that the next text needs a space before it
                if !cleaned.isEmpty {
                    needsSpaceBefore = true
                }
                return
            }

            // We have actual content
            let trimmed = cleaned.trimmingCharacters(in: .whitespaces)

            // Add space before if needed (from previous whitespace-only node or leading space)
            let shouldAddSpaceBefore = (needsSpaceBefore || cleaned.hasPrefix(" ")) &&
                                        !plainText.isEmpty &&
                                        !plainText.hasSuffix(" ") &&
                                        !plainText.hasSuffix("\n")

            if shouldAddSpaceBefore {
                plainText.append(" ")
            }
            needsSpaceBefore = false

            plainText.append(trimmed)

            // Track trailing space for next node
            if cleaned.hasSuffix(" ") {
                needsSpaceBefore = true
            }
            return
        }
        
        // Handle element nodes
        guard let element = node as? Element else { return }
        
        let tagName = element.tagName().lowercased()
        
        // Skip these elements entirely
        let skipTags = ["script", "style", "nav", "footer", "header", "aside", "form", "iframe", "noscript", "svg", "figure", "figcaption", "button", "input", "select", "textarea"]
        if skipTags.contains(tagName) {
            return
        }
        
        // Track formatting styles
        var newActiveStyles = activeStyles
        let currentPosition = plainText.count
        
        // Determine if this tag adds formatting
        var tagStyle: FormattingStyle? = nil
        var linkURL: String? = nil
        
        switch tagName {
        case "b", "strong":
            tagStyle = .bold
        case "i", "em":
            tagStyle = .italic
        case "h1":
            tagStyle = .header1
            ensureNewline(&plainText)
            needsSpaceBefore = false
        case "h2":
            tagStyle = .header2
            ensureNewline(&plainText)
            needsSpaceBefore = false
        case "h3", "h4", "h5", "h6":
            tagStyle = .header3
            ensureNewline(&plainText)
            needsSpaceBefore = false
        case "blockquote":
            tagStyle = .blockquote
            ensureNewline(&plainText)
            needsSpaceBefore = false
        case "a":
            tagStyle = .link
            linkURL = try? element.attr("href")
            // Resolve relative URLs
            if let href = linkURL, let base = baseURL {
                if href.hasPrefix("/") {
                    linkURL = "\(base.scheme ?? "https")://\(base.host ?? "")\(href)"
                } else if !href.hasPrefix("http") && !href.hasPrefix("mailto:") && !href.hasPrefix("#") {
                    linkURL = base.deletingLastPathComponent().appendingPathComponent(href).absoluteString
                }
            }
        case "code":
            tagStyle = .code
        case "pre":
            tagStyle = .preformatted
            ensureNewline(&plainText)
            needsSpaceBefore = false
        case "li":
            ensureNewline(&plainText)
            needsSpaceBefore = false
            plainText.append("• ")
        case "p", "div":
            ensureParagraphBreak(&plainText)
            needsSpaceBefore = false
        case "br":
            plainText.append("\n")
            needsSpaceBefore = false
        case "hr":
            ensureNewline(&plainText)
            plainText.append("───\n")
            needsSpaceBefore = false
        default:
            break
        }
        
        // Push style onto stack if this tag adds formatting
        if let style = tagStyle {
            newActiveStyles.append((style: style, start: plainText.count, url: linkURL))
        }
        
        // Process children
        for child in node.getChildNodes() {
            try processNode(child, plainText: &plainText, spans: &spans, baseURL: baseURL, activeStyles: newActiveStyles, needsSpaceBefore: &needsSpaceBefore)
        }
        
        // Pop style and create span
        if let style = tagStyle {
            let startPosition = newActiveStyles.last { $0.style == style }?.start ?? currentPosition
            let length = plainText.count - startPosition
            
            if length > 0 {
                spans.append(FormattingSpan(
                    location: startPosition,
                    length: length,
                    style: style,
                    url: linkURL
                ))
            }
        }
        
        // Add spacing after block elements
        switch tagName {
        case "p", "div", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6":
            ensureParagraphBreak(&plainText)
            needsSpaceBefore = false  // Reset after block element
        case "li":
            if !plainText.hasSuffix("\n") {
                plainText.append("\n")
            }
            needsSpaceBefore = false  // Reset after list item
        default:
            break
        }
    }
    
    /// Ensures text ends with at least one newline
    private static func ensureNewline(_ text: inout String) {
        if !text.isEmpty && !text.hasSuffix("\n") {
            text.append("\n")
        }
    }
    
    /// Ensures text ends with paragraph break (double newline)
    private static func ensureParagraphBreak(_ text: inout String) {
        if text.isEmpty { return }
        
        // Remove trailing spaces
        while text.hasSuffix(" ") {
            text.removeLast()
        }
        
        if !text.hasSuffix("\n\n") {
            if text.hasSuffix("\n") {
                text.append("\n")
            } else {
                text.append("\n\n")
            }
        }
    }
}

// MARK: - WKWebView Readability Extractor

/// Helper class that manages WKWebView lifecycle for Readability.js extraction
private class ReadabilityWebViewExtractor: NSObject, WKNavigationDelegate {
    
    private var webView: WKWebView?
    private let url: URL
    private let completion: (Result<ArticleExtractor.ReadabilityResult, Error>) -> Void
    private var hasCompleted = false
    
    // Keep strong reference to self until completion
    private static var activeExtractors: [ReadabilityWebViewExtractor] = []
    
    init(url: URL, completion: @escaping (Result<ArticleExtractor.ReadabilityResult, Error>) -> Void) {
        self.url = url
        self.completion = completion
        super.init()
    }
    
    func start() {
        // Keep self alive
        ReadabilityWebViewExtractor.activeExtractors.append(self)
        
        // Create offscreen webview
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        
        // Load the URL
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        webView.load(request)
        
        // Timeout after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.completeWith(error: ArticleExtractor.ExtractionError.networkError("Timeout"))
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Page loaded, now inject and run Readability.js
        runReadability()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completeWith(error: ArticleExtractor.ExtractionError.networkError(error.localizedDescription))
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completeWith(error: ArticleExtractor.ExtractionError.networkError(error.localizedDescription))
    }
    
    private func runReadability() {
        guard let readabilityJS = loadReadabilityJS() else {
            completeWith(error: ArticleExtractor.ExtractionError.resourceNotFound("Readability.js"))
            return
        }
        
        // JavaScript to inject Readability.js and extract content
        let extractionScript = """
        \(readabilityJS)
        
        (function() {
            try {
                var documentClone = document.cloneNode(true);
                var article = new Readability(documentClone).parse();
                if (article) {
                    return JSON.stringify({
                        success: true,
                        title: article.title || '',
                        author: article.byline || null,
                        content: article.content || '',
                        excerpt: article.excerpt || null
                    });
                } else {
                    return JSON.stringify({success: false, error: 'Readability returned null'});
                }
            } catch(e) {
                return JSON.stringify({success: false, error: e.toString()});
            }
        })();
        """
        
        webView?.evaluateJavaScript(extractionScript) { [weak self] result, error in
            if let error = error {
                self?.completeWith(error: ArticleExtractor.ExtractionError.parsingError(error.localizedDescription))
                return
            }
            
            guard let jsonString = result as? String,
                  let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  json["success"] as? Bool == true else {
                self?.completeWith(error: ArticleExtractor.ExtractionError.readabilityFailed)
                return
            }
            
            let readabilityResult = ArticleExtractor.ReadabilityResult(
                title: json["title"] as? String ?? "Untitled",
                author: json["author"] as? String,
                content: json["content"] as? String ?? "",
                excerpt: json["excerpt"] as? String
            )
            
            if readabilityResult.content.isEmpty {
                self?.completeWith(error: ArticleExtractor.ExtractionError.noContent)
            } else {
                self?.completeWith(result: readabilityResult)
            }
        }
    }
    
    private func loadReadabilityJS() -> String? {
        // Try to load from bundle
        if let path = Bundle.main.path(forResource: "Readability", ofType: "js"),
           let content = try? String(contentsOfFile: path) {
            return content
        }
        
        // Fallback: try without extension (in case it's named differently)
        if let path = Bundle.main.path(forResource: "Readability", ofType: ""),
           let content = try? String(contentsOfFile: path) {
            return content
        }
        
        return nil
    }
    
    private func completeWith(result: ArticleExtractor.ReadabilityResult) {
        guard !hasCompleted else { return }
        hasCompleted = true
        cleanup()
        completion(.success(result))
    }
    
    private func completeWith(error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        cleanup()
        completion(.failure(error))
    }
    
    private func cleanup() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        ReadabilityWebViewExtractor.activeExtractors.removeAll { $0 === self }
    }
}

// MARK: - Convenience Extension for ArticleManager

extension ArticleExtractor {
    
    /// Parses local HTML content (for file imports, not web fetching)
    static func parseLocalHTML(_ html: String, title: String? = nil, baseURL: URL? = nil) throws -> Article {
        // For local files, we skip Readability and parse directly
        // This is simpler since local HTML is usually already clean
        let parsed = try parseHTMLWithSwiftSoup(html: html, baseURL: baseURL)
        
        // Try to extract title from HTML if not provided
        var articleTitle = title ?? "Imported Document"
        if title == nil {
            let doc = try SwiftSoup.parse(html)
            if let titleElement = try doc.select("title").first() {
                articleTitle = try titleElement.text()
            }
        }
        
        let chapter = ArticleChapter(
            title: articleTitle,
            content: parsed.plainText,
            formattingSpans: parsed.spans
        )
        
        return Article(
            title: articleTitle,
            source: "Imported HTML",
            chapters: [chapter]
        )
    }
}
