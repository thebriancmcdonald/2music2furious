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
