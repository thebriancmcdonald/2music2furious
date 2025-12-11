//
//  DocumentImporter.swift
//  2 Music 2 Furious
//
//  Imports documents (ePub, PDF, HTML, TXT) and converts to Article format
//

import Foundation
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import Compression

// MARK: - Supported Document Types

enum DocumentType: String, CaseIterable {
    case epub = "epub"
    case pdf = "pdf"
    case html = "html"
    case txt = "txt"
    case htm = "htm"

    var utType: UTType {
        switch self {
        case .epub: return UTType(filenameExtension: "epub") ?? .data
        case .pdf: return .pdf
        case .html, .htm: return .html
        case .txt: return .plainText
        }
    }

    static var allUTTypes: [UTType] {
        [.pdf, .html, .plainText, .epub, UTType(filenameExtension: "epub")].compactMap { $0 }
    }
}

// MARK: - Document Importer

class DocumentImporter {

    enum ImportError: LocalizedError {
        case unsupportedFormat
        case fileReadError
        case parsingError(String)
        case emptyContent

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Unsupported file format"
            case .fileReadError: return "Could not read file"
            case .parsingError(let msg): return "Parsing error: \(msg)"
            case .emptyContent: return "File contains no readable text"
            }
        }
    }

    // MARK: - Main Import Method

    static func importDocument(from url: URL) async throws -> Article {
        let ext = url.pathExtension.lowercased()

        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        switch ext {
        case "epub":
            return try await importEPub(from: url)
        case "pdf":
            return try importPDF(from: url)
        case "html", "htm":
            return try importHTML(from: url)
        case "txt":
            return try importPlainText(from: url)
        default:
            throw ImportError.unsupportedFormat
        }
    }

    // MARK: - ePub Import

    static func importEPub(from url: URL) async throws -> Article {
        // Copy to temp location for extraction
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Unzip ePub (ePub is a ZIP file)
        try MiniZip.unzip(fileAt: url, to: tempDir)

        // Parse container.xml to find content.opf
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerPath.path) else {
            throw ImportError.parsingError("Invalid ePub: missing container.xml")
        }

        let containerData = try Data(contentsOf: containerPath)
        let containerParser = EPubContainerParser(data: containerData)
        guard let opfPath = containerParser.rootFilePath else {
            throw ImportError.parsingError("Could not find OPF file path")
        }

        // Parse content.opf for metadata and spine
        let opfURL = tempDir.appendingPathComponent(opfPath)
        let opfData = try Data(contentsOf: opfURL)
        let opfParser = EPubOPFParser(data: opfData)

        let title = opfParser.title ?? url.deletingPathExtension().lastPathComponent
        let author = opfParser.author

        // Get content directory (OPF is usually in a subdirectory)
        let contentDir = opfURL.deletingLastPathComponent()

        // Parse chapters from spine
        var chapters: [ArticleChapter] = []

        for (index, spineItem) in opfParser.spineItems.enumerated() {
            guard let href = opfParser.manifestItems[spineItem] else { continue }

            let chapterURL = contentDir.appendingPathComponent(href)
            guard FileManager.default.fileExists(atPath: chapterURL.path) else { continue }

            do {
                let chapterData = try Data(contentsOf: chapterURL)
                let (chapterTitle, chapterContent) = parseXHTMLContent(data: chapterData, fallbackTitle: "Chapter \(index + 1)")

                if !chapterContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chapters.append(ArticleChapter(
                        title: chapterTitle,
                        content: chapterContent
                    ))
                }
            } catch {
                continue // Skip unreadable chapters
            }
        }

        guard !chapters.isEmpty else {
            throw ImportError.emptyContent
        }

        return Article(
            title: title,
            source: "Uploaded ePub",
            author: author,
            chapters: chapters
        )
    }

    // MARK: - PDF Import

    static func importPDF(from url: URL) throws -> Article {
        guard let document = PDFDocument(url: url) else {
            throw ImportError.fileReadError
        }

        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            ?? url.deletingPathExtension().lastPathComponent

        let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String

        var fullText = ""
        var chapters: [ArticleChapter] = []

        // Extract text page by page
        let pageCount = document.pageCount

        if pageCount <= 10 {
            // Small PDF - single chapter
            for i in 0..<pageCount {
                if let page = document.page(at: i),
                   let pageText = page.string {
                    fullText += pageText + "\n\n"
                }
            }

            guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ImportError.emptyContent
            }

            chapters.append(ArticleChapter(title: title, content: fullText.trimmingCharacters(in: .whitespacesAndNewlines)))
        } else {
            // Large PDF - chapter per ~10 pages
            let pagesPerChapter = 10
            var chapterIndex = 1

            for startPage in stride(from: 0, to: pageCount, by: pagesPerChapter) {
                var chapterText = ""
                let endPage = min(startPage + pagesPerChapter, pageCount)

                for i in startPage..<endPage {
                    if let page = document.page(at: i),
                       let pageText = page.string {
                        chapterText += pageText + "\n\n"
                    }
                }

                if !chapterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chapters.append(ArticleChapter(
                        title: "Pages \(startPage + 1)-\(endPage)",
                        content: chapterText.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                    chapterIndex += 1
                }
            }
        }

        guard !chapters.isEmpty else {
            throw ImportError.emptyContent
        }

        return Article(
            title: title,
            source: "Uploaded PDF",
            author: author,
            chapters: chapters
        )
    }

    // MARK: - HTML Import

    static func importHTML(from url: URL) throws -> Article {
        let data = try Data(contentsOf: url)
        let (title, content) = parseHTMLContent(data: data, fallbackTitle: url.deletingPathExtension().lastPathComponent)

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyContent
        }

        // Try to split by headers
        let articleManager = ArticleManager.shared
        let chapters = articleManager.splitIntoChapters(title: title, content: content)

        return Article(
            title: title,
            source: "Uploaded HTML",
            chapters: chapters
        )
    }

    // MARK: - Plain Text Import

    static func importPlainText(from url: URL) throws -> Article {
        let content = try String(contentsOf: url, encoding: .utf8)

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyContent
        }

        let title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        // Try to split by headers or double newlines
        let articleManager = ArticleManager.shared
        let chapters = articleManager.splitIntoChapters(title: title, content: content)

        return Article(
            title: title,
            source: "Uploaded Text",
            chapters: chapters
        )
    }

    // MARK: - HTML/XHTML Parsing Helpers

    private static func parseXHTMLContent(data: Data, fallbackTitle: String) -> (title: String, content: String) {
        guard let htmlString = String(data: data, encoding: .utf8) else {
            return (fallbackTitle, "")
        }
        return parseHTMLString(htmlString, fallbackTitle: fallbackTitle)
    }

    private static func parseHTMLContent(data: Data, fallbackTitle: String) -> (title: String, content: String) {
        // Try different encodings
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .windowsCP1252]

        for encoding in encodings {
            if let htmlString = String(data: data, encoding: encoding) {
                return parseHTMLString(htmlString, fallbackTitle: fallbackTitle)
            }
        }

        return (fallbackTitle, "")
    }

    private static func parseHTMLString(_ html: String, fallbackTitle: String) -> (title: String, content: String) {
        var title = fallbackTitle
        var content = html

        // Extract title from <title> tag
        if let titleRange = html.range(of: "<title[^>]*>(.*?)</title>", options: .regularExpression, range: nil, locale: nil) {
            let titleMatch = String(html[titleRange])
            title = titleMatch
                .replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "</title>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Remove script and style tags
        content = content.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        content = content.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Convert <br>, <p>, <div> to newlines
        content = content.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        content = content.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        content = content.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        content = content.replacingOccurrences(of: "</h[1-6]>", with: "\n\n", options: .regularExpression)

        // Convert headers to markdown-style for chapter detection
        content = content.replacingOccurrences(of: "<h1[^>]*>([^<]*)", with: "## $1", options: .regularExpression)
        content = content.replacingOccurrences(of: "<h2[^>]*>([^<]*)", with: "## $1", options: .regularExpression)
        content = content.replacingOccurrences(of: "<h3[^>]*>([^<]*)", with: "### $1", options: .regularExpression)

        // Remove remaining HTML tags
        content = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        content = content
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        // Clean up whitespace
        content = content.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if title.isEmpty { title = fallbackTitle }

        return (title, content)
    }
}

// MARK: - ePub XML Parsers

class EPubContainerParser: NSObject, XMLParserDelegate {
    private var parser: XMLParser
    var rootFilePath: String?

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "rootfile" {
            rootFilePath = attributeDict["full-path"]
        }
    }
}

class EPubOPFParser: NSObject, XMLParserDelegate {
    private var parser: XMLParser

    var title: String?
    var author: String?
    var manifestItems: [String: String] = [:] // id -> href
    var spineItems: [String] = [] // ordered item ids

    private var currentElement = ""
    private var currentText = ""

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifestItems[id] = href
            }
        } else if elementName == "itemref" {
            if let idref = attributeDict["idref"] {
                spineItems.append(idref)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "dc:title" || elementName == "title" {
            if title == nil && !text.isEmpty {
                title = text
            }
        } else if elementName == "dc:creator" || elementName == "creator" {
            if author == nil && !text.isEmpty {
                author = text
            }
        }
    }
}

// MARK: - Minimal ZIP Extraction (No External Dependencies)

enum MiniZip {
    enum ZipError: Error {
        case invalidArchive
        case decompressionFailed
        case fileCreationFailed
    }

    static func unzip(fileAt sourceURL: URL, to destinationURL: URL) throws {
        let fileHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? fileHandle.close() }

        let data = fileHandle.readDataToEndOfFile()

        // ZIP file structure: series of local file headers followed by file data
        var offset = 0

        while offset < data.count - 4 {
            // Check for local file header signature (0x04034b50)
            let sig = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }

            if sig == 0x04034b50 {
                // Parse local file header
                let minVersion = data.subdata(in: offset+4..<offset+6).withUnsafeBytes { $0.load(as: UInt16.self) }
                let flags = data.subdata(in: offset+6..<offset+8).withUnsafeBytes { $0.load(as: UInt16.self) }
                let compressionMethod = data.subdata(in: offset+8..<offset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
                let compressedSize = data.subdata(in: offset+18..<offset+22).withUnsafeBytes { $0.load(as: UInt32.self) }
                let uncompressedSize = data.subdata(in: offset+22..<offset+26).withUnsafeBytes { $0.load(as: UInt32.self) }
                let fileNameLength = data.subdata(in: offset+26..<offset+28).withUnsafeBytes { $0.load(as: UInt16.self) }
                let extraFieldLength = data.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) }

                let fileNameStart = offset + 30
                let fileNameEnd = fileNameStart + Int(fileNameLength)
                let fileName = String(data: data.subdata(in: fileNameStart..<fileNameEnd), encoding: .utf8) ?? ""

                let dataStart = fileNameEnd + Int(extraFieldLength)
                let dataEnd = dataStart + Int(compressedSize)

                // Skip directories (end with /)
                if !fileName.hasSuffix("/") && dataEnd <= data.count {
                    let fileData = data.subdata(in: dataStart..<dataEnd)

                    let decompressedData: Data
                    if compressionMethod == 0 {
                        // Stored (no compression)
                        decompressedData = fileData
                    } else if compressionMethod == 8 {
                        // Deflate
                        decompressedData = try decompress(fileData, expectedSize: Int(uncompressedSize))
                    } else {
                        // Unsupported compression, skip
                        offset = dataEnd
                        continue
                    }

                    // Create file
                    let filePath = destinationURL.appendingPathComponent(fileName)
                    let dirPath = filePath.deletingLastPathComponent()

                    try FileManager.default.createDirectory(at: dirPath, withIntermediateDirectories: true)
                    try decompressedData.write(to: filePath)
                }

                offset = dataEnd
            } else if sig == 0x02014b50 {
                // Central directory header - we're done with files
                break
            } else {
                offset += 1
            }
        }
    }

    private static func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        // Use Apple's compression framework for deflate
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                expectedSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw ZipError.decompressionFailed
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}

// MARK: - Web Article Extractor

class WebArticleExtractor {

    enum ExtractionError: LocalizedError {
        case invalidURL
        case networkError(String)
        case parsingError
        case noContent

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .networkError(let msg): return "Network error: \(msg)"
            case .parsingError: return "Could not parse article"
            case .noContent: return "No readable content found"
            }
        }
    }

    /// Fetches and extracts article content from a web URL
    static func extractArticle(from url: URL) async throws -> Article {
        // Fetch the HTML
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ExtractionError.networkError("Server returned an error")
        }

        // Detect encoding
        let encoding: String.Encoding = detectEncoding(from: httpResponse, data: data)

        guard let html = String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8) else {
            throw ExtractionError.parsingError
        }

        // Extract article content
        let (title, content, author) = extractContent(from: html, url: url)

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noContent
        }

        // Split into chapters based on headers
        let chapters = ArticleManager.shared.splitIntoChapters(title: title, content: content)

        return Article(
            title: title,
            source: url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web",
            sourceURL: url,
            author: author,
            chapters: chapters
        )
    }

    private static func detectEncoding(from response: HTTPURLResponse, data: Data) -> String.Encoding {
        // Check Content-Type header
        if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           contentType.lowercased().contains("charset=utf-8") {
            return .utf8
        }

        // Check meta tag in HTML
        if let htmlPrefix = String(data: data.prefix(1024), encoding: .ascii) {
            if htmlPrefix.lowercased().contains("charset=utf-8") ||
               htmlPrefix.lowercased().contains("charset=\"utf-8\"") {
                return .utf8
            }
            if htmlPrefix.lowercased().contains("charset=iso-8859-1") ||
               htmlPrefix.lowercased().contains("charset=\"iso-8859-1\"") {
                return .isoLatin1
            }
        }

        return .utf8
    }

    private static func extractContent(from html: String, url: URL) -> (title: String, content: String, author: String?) {
        var title = ""
        var content = ""
        var author: String? = nil

        // Extract title - try multiple sources
        // 1. og:title meta tag
        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            title = ogTitle
        }
        // 2. <title> tag
        else if let titleMatch = html.range(of: "<title[^>]*>(.*?)</title>", options: .regularExpression) {
            title = String(html[titleMatch])
                .replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "</title>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract author
        if let authorMeta = extractMetaContent(from: html, name: "author") {
            author = authorMeta
        } else if let authorMeta = extractMetaContent(from: html, property: "article:author") {
            author = authorMeta
        }

        // Extract main content
        content = extractMainContent(from: html)

        // Clean up title
        if title.isEmpty {
            title = url.lastPathComponent
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: ".html", with: "")
                .replacingOccurrences(of: ".htm", with: "")
            if title.isEmpty {
                title = "Web Article"
            }
        }

        // Remove site name from title (common pattern: "Article Title | Site Name")
        if let pipeRange = title.range(of: " | ") {
            title = String(title[..<pipeRange.lowerBound])
        }
        if let dashRange = title.range(of: " - ", options: .backwards) {
            let beforeDash = String(title[..<dashRange.lowerBound])
            if beforeDash.count > 10 { // Likely the actual title
                title = beforeDash
            }
        }

        return (title.trimmingCharacters(in: .whitespacesAndNewlines),
                content.trimmingCharacters(in: .whitespacesAndNewlines),
                author)
    }

    private static func extractMetaContent(from html: String, property: String? = nil, name: String? = nil) -> String? {
        let pattern: String
        if let property = property {
            pattern = "<meta[^>]*property=[\"']\(property)[\"'][^>]*content=[\"']([^\"']*)[\"']|<meta[^>]*content=[\"']([^\"']*)[\"'][^>]*property=[\"']\(property)[\"']"
        } else if let name = name {
            pattern = "<meta[^>]*name=[\"']\(name)[\"'][^>]*content=[\"']([^\"']*)[\"']|<meta[^>]*content=[\"']([^\"']*)[\"'][^>]*name=[\"']\(name)[\"']"
        } else {
            return nil
        }

        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
            // Try both capture groups
            for i in 1...2 {
                if let range = Range(match.range(at: i), in: html) {
                    let value = String(html[range])
                    if !value.isEmpty {
                        return decodeHTMLEntities(value)
                    }
                }
            }
        }
        return nil
    }

    private static func extractMainContent(from html: String) -> String {
        var content = html

        // Try to find article/main content containers
        let contentSelectors = [
            "<article[^>]*>([\\s\\S]*?)</article>",
            "<main[^>]*>([\\s\\S]*?)</main>",
            "<div[^>]*class=[\"'][^\"']*(?:article|content|post|entry|story)[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",
            "<div[^>]*id=[\"'][^\"']*(?:article|content|post|entry|story)[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>"
        ]

        for selector in contentSelectors {
            if let regex = try? NSRegularExpression(pattern: selector, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                content = String(html[range])
                break
            }
        }

        // If no container found, use body
        if content == html {
            if let bodyMatch = html.range(of: "<body[^>]*>([\\s\\S]*?)</body>", options: .regularExpression),
               let bodyRange = Range(bodyMatch, in: html) {
                content = String(html[bodyRange])
            }
        }

        // Remove unwanted elements
        let removePatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<header[^>]*>[\\s\\S]*?</header>",
            "<aside[^>]*>[\\s\\S]*?</aside>",
            "<form[^>]*>[\\s\\S]*?</form>",
            "<iframe[^>]*>[\\s\\S]*?</iframe>",
            "<noscript[^>]*>[\\s\\S]*?</noscript>",
            "<!--[\\s\\S]*?-->",
            "<div[^>]*class=[\"'][^\"']*(?:comment|sidebar|widget|ad|social|share|related|footer|header|nav|menu)[^\"']*[\"'][^>]*>[\\s\\S]*?</div>"
        ]

        for pattern in removePatterns {
            content = content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Convert headers to markdown style for chapter detection
        content = content.replacingOccurrences(of: "<h1[^>]*>([^<]*)</h1>", with: "\n## $1\n", options: .regularExpression)
        content = content.replacingOccurrences(of: "<h2[^>]*>([^<]*)</h2>", with: "\n## $1\n", options: .regularExpression)
        content = content.replacingOccurrences(of: "<h3[^>]*>([^<]*)</h3>", with: "\n### $1\n", options: .regularExpression)

        // Convert block elements to newlines
        content = content.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        content = content.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        content = content.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        content = content.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        content = content.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: .regularExpression)

        // Remove all remaining HTML tags
        content = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        content = decodeHTMLEntities(content)

        // Clean up whitespace
        content = content.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        content = content.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)

        return content
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&ldquo;", """),
            ("&rdquo;", """),
            ("&lsquo;", "'"),
            ("&rsquo;", "'"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™"),
            ("&bull;", "•"),
            ("&middot;", "·")
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Numeric entities
        let numericPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let numRange = Range(match.range(at: 1), in: result),
                   let codePoint = Int(result[numRange]),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        return result
    }
}
