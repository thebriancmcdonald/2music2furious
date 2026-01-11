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
import UIKit

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
        let heroImageURL: String?  // og:image meta tag for header image
    }
    
    /// Result from full extraction pipeline
    struct ExtractionResult {
        let title: String
        let author: String?
        let plainText: String
        let formattingSpans: [FormattingSpan]
        let images: [ArticleImage]
    }
    
    // MARK: - Main Extraction Method
    
    /// Extracts article content from a URL
    /// Uses Readability.js via WKWebView, then SwiftSoup to parse
    static func extract(from url: URL) async throws -> Article {
        // Step 1: Fetch and run Readability.js
        let readabilityResult = try await extractWithReadability(url: url)

        // Step 2: Parse clean HTML into text + spans + images with SwiftSoup
        var parsed = try parseHTMLWithSwiftSoup(
            html: readabilityResult.content,
            baseURL: url
        )

        // Step 2.5: Prepend hero image from og:image if available
        if let heroURL = readabilityResult.heroImageURL, !heroURL.isEmpty {
            // Resolve relative URLs for hero image
            var resolvedHeroURL = heroURL
            if heroURL.hasPrefix("//") {
                resolvedHeroURL = "\(url.scheme ?? "https"):\(heroURL)"
            } else if heroURL.hasPrefix("/") {
                resolvedHeroURL = "\(url.scheme ?? "https")://\(url.host ?? "")\(heroURL)"
            }

            // Check if this URL is already in the parsed images (avoid duplicates)
            let isDuplicate = parsed.images.contains { image in
                // Compare URLs ignoring query parameters and protocol
                let heroNormalized = resolvedHeroURL
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                    .components(separatedBy: "?").first ?? ""
                let imgNormalized = image.originalURL
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                    .components(separatedBy: "?").first ?? ""
                return heroNormalized == imgNormalized
            }

            if !isDuplicate {
                print("🖼️ [HERO] Adding hero image from og:image: \(resolvedHeroURL)")

                // Create hero image at position 0
                let heroImage = ArticleImage(
                    location: 0,
                    localPath: nil,
                    originalURL: resolvedHeroURL,
                    caption: nil,
                    altText: "Hero image"
                )

                // Prepend placeholder to content and shift all other positions
                let heroPlaceholder = "\u{FFFC}\n\n"
                let shiftAmount = heroPlaceholder.count

                // Shift all existing image positions
                var shiftedImages = parsed.images.map { image in
                    ArticleImage(
                        id: image.id,
                        location: image.location + shiftAmount,
                        localPath: image.localPath,
                        originalURL: image.originalURL,
                        caption: image.caption,
                        altText: image.altText
                    )
                }

                // Shift all formatting spans
                let shiftedSpans = parsed.spans.map { span in
                    FormattingSpan(
                        location: span.location + shiftAmount,
                        length: span.length,
                        style: span.style,
                        url: span.url
                    )
                }

                // Insert hero image at the beginning
                shiftedImages.insert(heroImage, at: 0)

                // Update parsed result with shifted content
                parsed = ParsedHTML(
                    plainText: heroPlaceholder + parsed.plainText,
                    spans: shiftedSpans,
                    images: shiftedImages
                )
            } else {
                print("🖼️ [HERO] Skipping og:image - already in article content")
            }
        }

        // Step 3: Download images asynchronously
        let downloadedImages = await downloadImages(parsed.images)

        // Step 4: Build Article
        let chapter = ArticleChapter(
            title: readabilityResult.title,
            content: parsed.plainText,
            formattingSpans: parsed.spans,
            images: downloadedImages.isEmpty ? nil : downloadedImages
        )

        return Article(
            title: readabilityResult.title,
            source: url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web",
            sourceURL: url,
            author: readabilityResult.author,
            chapters: [chapter]
        )
    }

    // MARK: - Image Downloading

    /// Downloads images and saves them locally, returning updated ArticleImage objects
    private static func downloadImages(_ images: [ArticleImage]) async -> [ArticleImage] {
        guard !images.isEmpty else { return [] }

        return await withTaskGroup(of: ArticleImage?.self) { group in
            for image in images {
                group.addTask {
                    await downloadImage(image)
                }
            }

            var results: [ArticleImage] = []
            for await result in group {
                if let image = result {
                    results.append(image)
                }
            }
            // Sort by location to maintain order
            return results.sorted { $0.location < $1.location }
        }
    }

    /// Downloads a single image and saves it to the app's documents directory
    private static func downloadImage(_ image: ArticleImage) async -> ArticleImage? {
        guard let url = URL(string: image.originalURL) else {
            print("🖼️ [IMAGE] Invalid URL: \(image.originalURL)")
            return nil
        }

        print("🖼️ [IMAGE] Downloading: \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // Verify it's an image
            guard let httpResponse = response as? HTTPURLResponse else {
                print("🖼️ [IMAGE] Not HTTP response")
                return nil
            }

            print("🖼️ [IMAGE] Status: \(httpResponse.statusCode), MIME: \(httpResponse.mimeType ?? "unknown"), Size: \(data.count) bytes")

            guard httpResponse.statusCode == 200,
                  let mimeType = httpResponse.mimeType,
                  mimeType.hasPrefix("image/") else {
                print("🖼️ [IMAGE] Rejected - not a valid image response")
                return nil
            }

            // Determine file extension from mime type
            let ext: String
            switch mimeType {
            case "image/jpeg": ext = "jpg"
            case "image/png": ext = "png"
            case "image/gif": ext = "gif"
            case "image/webp": ext = "webp"
            case "image/avif": ext = "avif"
            default: ext = "jpg"
            }

            // Save to documents/images directory
            let filename = "\(image.id.uuidString).\(ext)"
            let imagesDir = getImagesDirectory()
            let filePath = imagesDir.appendingPathComponent(filename)

            try data.write(to: filePath)
            print("🖼️ [IMAGE] Saved to: \(filePath.path)")

            // Verify the image can be loaded
            if let testLoad = UIImage(contentsOfFile: filePath.path) {
                print("🖼️ [IMAGE] ✅ Verified loadable: \(testLoad.size)")
            } else {
                print("🖼️ [IMAGE] ⚠️ Saved but UIImage cannot load it (format issue?)")
            }

            // Return updated image with local path
            return ArticleImage(
                id: image.id,
                location: image.location,
                localPath: filename,
                originalURL: image.originalURL,
                caption: image.caption,
                altText: image.altText
            )
        } catch {
            print("🖼️ [IMAGE] ❌ Download failed: \(error)")
            // Return original without local path - can be loaded from URL later
            return image
        }
    }

    /// Gets the app's images directory, creating it if needed
    static func getImagesDirectory() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesDir = documentsDir.appendingPathComponent("ArticleImages", isDirectory: true)

        if !FileManager.default.fileExists(atPath: imagesDir.path) {
            try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }

        return imagesDir
    }

    /// Loads an image from local storage or returns nil
    static func loadImage(for articleImage: ArticleImage) -> UIImage? {
        guard let localPath = articleImage.localPath else { return nil }
        let imagesDir = getImagesDirectory()
        let filePath = imagesDir.appendingPathComponent(localPath)
        return UIImage(contentsOfFile: filePath.path)
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
        let images: [ArticleImage]
    }

    /// Parses clean HTML from Readability into plain text + formatting spans
    static func parseHTMLWithSwiftSoup(html: String, baseURL: URL?) throws -> ParsedHTML {
        // First decode any HTML entities in the raw HTML before parsing
        let decodedHTML = decodeHTMLEntities(html)
        let doc = try SwiftSoup.parse(decodedHTML)

        var plainText = ""
        var spans: [FormattingSpan] = []
        var images: [ArticleImage] = []

        // Process the body (or root element)
        if let body = doc.body() {
            var needsSpaceBefore = false
            try processNode(body, plainText: &plainText, spans: &spans, images: &images, baseURL: baseURL, activeStyles: [], needsSpaceBefore: &needsSpaceBefore)
        }

        // Clean up trailing whitespace
        plainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Final newline cleanup - collapse 3+ newlines into 2
        while plainText.contains("\n\n\n") {
            plainText = plainText.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Final pass: decode any remaining HTML entities in the plain text
        plainText = decodeHTMLEntities(plainText)

        return ParsedHTML(plainText: plainText, spans: spans, images: images)
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
        images: inout [ArticleImage],
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

        // Skip these elements entirely (removed figure/figcaption - we handle those now)
        let skipTags = ["script", "style", "nav", "footer", "header", "aside", "form", "iframe", "noscript", "svg", "button", "input", "select", "textarea"]
        if skipTags.contains(tagName) {
            return
        }

        // Handle <figure> elements specially - extract image and caption together
        if tagName == "figure" {
            try processFigure(element, plainText: &plainText, spans: &spans, images: &images, baseURL: baseURL, needsSpaceBefore: &needsSpaceBefore)
            return
        }

        // Handle standalone <img> tags (not in a figure)
        if tagName == "img" {
            processImage(element, plainText: &plainText, images: &images, baseURL: baseURL, caption: nil, needsSpaceBefore: &needsSpaceBefore)
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
            try processNode(child, plainText: &plainText, spans: &spans, images: &images, baseURL: baseURL, activeStyles: newActiveStyles, needsSpaceBefore: &needsSpaceBefore)
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
    
    // MARK: - Figure and Image Processing

    /// Process a <figure> element, extracting image and caption
    private static func processFigure(
        _ element: Element,
        plainText: inout String,
        spans: inout [FormattingSpan],
        images: inout [ArticleImage],
        baseURL: URL?,
        needsSpaceBefore: inout Bool
    ) throws {
        // Ensure we start on a new line
        ensureParagraphBreak(&plainText)
        needsSpaceBefore = false

        // Find the image within the figure
        let imgElements = try element.select("img")
        let imgElement = imgElements.first()

        // Find the caption (figcaption or any text)
        var captionText: String? = nil
        if let figcaption = try element.select("figcaption").first() {
            captionText = try figcaption.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Process the image if found
        if let img = imgElement {
            processImage(img, plainText: &plainText, images: &images, baseURL: baseURL, caption: captionText, needsSpaceBefore: &needsSpaceBefore)
        }

        // Add caption text with caption formatting (for display, skipped in TTS)
        if let caption = captionText, !caption.isEmpty {
            let captionStart = plainText.count
            plainText.append(caption)
            spans.append(FormattingSpan(
                location: captionStart,
                length: caption.count,
                style: .caption
            ))
            plainText.append("\n")
        }

        ensureParagraphBreak(&plainText)
        needsSpaceBefore = false
    }

    /// Process an <img> element
    private static func processImage(
        _ element: Element,
        plainText: inout String,
        images: inout [ArticleImage],
        baseURL: URL?,
        caption: String?,
        needsSpaceBefore: inout Bool
    ) {
        // Get image URL - try src first, then data-src (lazy loading)
        var imgSrc = try? element.attr("src")
        if imgSrc == nil || imgSrc?.isEmpty == true {
            imgSrc = try? element.attr("data-src")
        }

        guard let src = imgSrc, !src.isEmpty else { return }

        // Resolve relative URLs
        var resolvedURL = src
        if let base = baseURL {
            if src.hasPrefix("//") {
                resolvedURL = "\(base.scheme ?? "https"):\(src)"
            } else if src.hasPrefix("/") {
                resolvedURL = "\(base.scheme ?? "https")://\(base.host ?? "")\(src)"
            } else if !src.hasPrefix("http") {
                resolvedURL = base.deletingLastPathComponent().appendingPathComponent(src).absoluteString
            }
        }

        // Get alt text
        let altText = try? element.attr("alt")

        // Insert a placeholder character for the image position
        // We use a special Unicode character that will be replaced with the image in the UI
        let imagePosition = plainText.count
        plainText.append("\u{FFFC}")  // Object Replacement Character (used by NSTextAttachment)
        plainText.append("\n")

        // Add the image record
        let image = ArticleImage(
            location: imagePosition,
            localPath: nil,  // Will be set after downloading
            originalURL: resolvedURL,
            caption: caption,
            altText: altText
        )
        images.append(image)
        print("🖼️ [PARSE] Found image: \(resolvedURL) at position \(imagePosition)")

        needsSpaceBefore = false
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
                // Extract og:image meta tag for hero image
                var heroImage = null;
                var ogImage = document.querySelector('meta[property="og:image"]');
                if (ogImage) {
                    heroImage = ogImage.getAttribute('content');
                }
                // Fallback to twitter:image if no og:image
                if (!heroImage) {
                    var twitterImage = document.querySelector('meta[name="twitter:image"]');
                    if (twitterImage) {
                        heroImage = twitterImage.getAttribute('content');
                    }
                }

                var documentClone = document.cloneNode(true);
                var article = new Readability(documentClone).parse();
                if (article) {
                    return JSON.stringify({
                        success: true,
                        title: article.title || '',
                        author: article.byline || null,
                        content: article.content || '',
                        excerpt: article.excerpt || null,
                        heroImageURL: heroImage
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
                excerpt: json["excerpt"] as? String,
                heroImageURL: json["heroImageURL"] as? String
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
