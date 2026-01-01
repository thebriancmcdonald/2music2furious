//
//  ArticleManager.swift
//  2 Music 2 Furious
//
//  Article models and management for text-to-speech reader
//  Uses ArticleExtractor + SwiftSoup for rich text parsing
//

import Foundation
import SwiftUI
import Combine

// MARK: - Formatting Models

/// Style types that can be applied to text spans
enum FormattingStyle: String, Codable, Equatable {
    case bold
    case italic
    case boldItalic
    case header1
    case header2
    case header3
    case blockquote
    case listItem
    case link
    case code
    case preformatted
}

/// A span of formatting applied to a range of plain text
/// The plain text is preserved for TTS sync; formatting is applied visually
struct FormattingSpan: Codable, Equatable {
    let location: Int
    let length: Int
    let style: FormattingStyle
    let url: String?  // For links only
    
    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
    
    init(location: Int, length: Int, style: FormattingStyle, url: String? = nil) {
        self.location = location
        self.length = length
        self.style = style
        self.url = url
    }
    
    init(range: NSRange, style: FormattingStyle, url: String? = nil) {
        self.location = range.location
        self.length = range.length
        self.style = style
        self.url = url
    }
}

// MARK: - Article Chapter Model

struct ArticleChapter: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String                        // Plain text for TTS (always used)
    var formattingSpans: [FormattingSpan]?     // Rich formatting overlays (optional)
    var htmlContent: String?                   // Original HTML (kept for potential re-parsing)

    init(id: UUID = UUID(), title: String, content: String, formattingSpans: [FormattingSpan]? = nil, htmlContent: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.formattingSpans = formattingSpans
        self.htmlContent = htmlContent
    }

    var estimatedReadingTime: Int {
        let wordCount = content.split(separator: " ").count
        return max(1, wordCount / 200)
    }

    var wordCount: Int {
        content.split(separator: " ").count
    }
    
    /// Returns true if this chapter has rich formatting
    var hasFormatting: Bool {
        guard let spans = formattingSpans else { return false }
        return !spans.isEmpty
    }
}

// MARK: - Article Model

struct Article: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var source: String
    var sourceURL: URL?
    var author: String?
    var chapters: [ArticleChapter]
    var dateAdded: Date
    var lastReadChapter: Int
    var lastReadPosition: Int
    
    // UI Helper: Is this currently downloading?
    var isDownloading: Bool = false
    
    // Coding keys to exclude 'isDownloading' from JSON persistence
    enum CodingKeys: String, CodingKey {
        case id, title, source, sourceURL, author, chapters, dateAdded, lastReadChapter, lastReadPosition
    }

    init(
        id: UUID = UUID(),
        title: String,
        source: String,
        sourceURL: URL? = nil,
        author: String? = nil,
        chapters: [ArticleChapter],
        dateAdded: Date = Date(),
        lastReadChapter: Int = 0,
        lastReadPosition: Int = 0
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.sourceURL = sourceURL
        self.author = author
        self.chapters = chapters
        self.dateAdded = dateAdded
        self.lastReadChapter = lastReadChapter
        self.lastReadPosition = lastReadPosition
    }

    var totalWordCount: Int {
        chapters.reduce(0) { $0 + $1.wordCount }
    }

    var totalReadingTime: Int {
        max(1, totalWordCount / 200)
    }
    
    var formattedReadingTime: String {
        let minutes = totalReadingTime
        if minutes < 60 { return "\(minutes) min read" }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins > 0 ? "\(hours)h \(mins)m read" : "\(hours)h read"
    }
    
    // Display-friendly source
    var displaySource: String {
        if let url = sourceURL, let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return source
    }
    
    /// Returns true if any chapter has rich formatting
    var hasFormatting: Bool {
        chapters.contains { $0.hasFormatting }
    }
}

// MARK: - Article Manager

class ArticleManager: ObservableObject {
    static let shared = ArticleManager()

    // App Group identifier
    static let appGroupIdentifier = "group.com.2music2furious.shared"

    @Published var articles: [Article] = []
    @Published var isLoaded = false

    private let userDefaults: UserDefaults
    private let articlesKey = "savedArticles"
    private let pendingArticlesKey = "pendingArticles"

    // MARK: - LAZY LOADING: Minimal init
    
    init() {
        // Set up userDefaults immediately (fast, no disk read)
        if let sharedDefaults = UserDefaults(suiteName: ArticleManager.appGroupIdentifier) {
            self.userDefaults = sharedDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
        // Articles loaded lazily via loadIfNeeded()
    }
    
    /// Call this before accessing articles - loads from disk if not already loaded
    func loadIfNeeded() {
        guard !isLoaded else { return }
        loadArticles()
        isLoaded = true
    }

    // MARK: - Pending Article Processing

    func checkForPendingArticles() {
        loadIfNeeded()
        
        guard let data = userDefaults.data(forKey: pendingArticlesKey),
              let pendingArticles = try? JSONDecoder().decode([Article].self, from: data),
              !pendingArticles.isEmpty else { return }

        // 1. Merge new articles
        var newArticlesCount = 0
        for article in pendingArticles {
            if !articles.contains(where: { $0.id == article.id }) {
                articles.insert(article, at: 0)
                newArticlesCount += 1
                
                // 2. Check if this is a "shell" article that needs downloading
                if let url = article.sourceURL,
                   (article.chapters.isEmpty || article.chapters.first?.content.isEmpty == true) {
                    hydrateArticleContent(article)
                }
            }
        }

        if newArticlesCount > 0 {
            // Clear pending queue
            userDefaults.removeObject(forKey: pendingArticlesKey)
            saveArticles()
        }
    }
    
    /// Background task to fetch content for "Shell" articles using ArticleExtractor
    private func hydrateArticleContent(_ article: Article) {
        guard let url = article.sourceURL else { return }
        
        // Mark as downloading
        if let idx = articles.firstIndex(where: { $0.id == article.id }) {
            var updated = articles[idx]
            updated.isDownloading = true
            articles[idx] = updated
        }
        
        Task {
            do {
                // Use the new ArticleExtractor with Readability.js + SwiftSoup
                let extractedArticle = try await ArticleExtractor.extract(from: url)
                
                await MainActor.run {
                    if let idx = self.articles.firstIndex(where: { $0.id == article.id }) {
                        var updated = self.articles[idx]
                        
                        // Update with extracted content
                        if updated.title == "New Article" || updated.title == "Web Article" {
                            updated.title = extractedArticle.title
                        }
                        
                        updated.author = extractedArticle.author
                        updated.chapters = extractedArticle.chapters
                        updated.isDownloading = false
                        
                        self.articles[idx] = updated
                        self.saveArticles()
                    }
                }
            } catch {
                print("Failed to hydrate article: \(error)")
                await MainActor.run {
                    if let idx = self.articles.firstIndex(where: { $0.id == article.id }) {
                        self.articles[idx].isDownloading = false
                    }
                }
            }
        }
    }

    // MARK: - CRUD Operations

    func addArticle(_ article: Article) {
        loadIfNeeded()
        articles.insert(article, at: 0)
        saveArticles()
    }

    func removeArticle(_ article: Article) {
        loadIfNeeded()
        articles.removeAll { $0.id == article.id }
        saveArticles()
    }

    func updateArticle(_ article: Article) {
        loadIfNeeded()
        if let index = articles.firstIndex(where: { $0.id == article.id }) {
            articles[index] = article
            saveArticles()
        }
    }

    func updateProgress(articleId: UUID, chapterIndex: Int, position: Int) {
        loadIfNeeded()
        if let index = articles.firstIndex(where: { $0.id == articleId }) {
            articles[index].lastReadChapter = chapterIndex
            articles[index].lastReadPosition = position
            saveArticles()
        }
    }

    func createArticleFromText(title: String, text: String, source: String = "Pasted Text") -> Article {
        let chapter = ArticleChapter(title: title, content: text)
        return Article(title: title, source: source, chapters: [chapter])
    }
    
    /// Splits content into chapters based on markdown-style headers
    func splitIntoChapters(title: String, content: String) -> [ArticleChapter] {
        let lines = content.components(separatedBy: "\n")
        var chapters: [ArticleChapter] = []
        var currentTitle = title
        var currentContent: [String] = []

        for line in lines {
            // Check for markdown headers (## or ###)
            if line.hasPrefix("## ") || line.hasPrefix("### ") {
                if !currentContent.isEmpty {
                    let chapterText = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chapterText.isEmpty {
                        chapters.append(ArticleChapter(title: currentTitle, content: chapterText))
                    }
                }
                currentTitle = line.replacingOccurrences(of: "### ", with: "")
                    .replacingOccurrences(of: "## ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentContent = []
            } else {
                currentContent.append(line)
            }
        }

        if !currentContent.isEmpty {
            let chapterText = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !chapterText.isEmpty {
                chapters.append(ArticleChapter(title: currentTitle, content: chapterText))
            }
        }

        if chapters.isEmpty {
            chapters.append(ArticleChapter(title: title, content: content))
        }

        return chapters
    }

    // MARK: - Persistence

    func saveArticles() {
        if let encoded = try? JSONEncoder().encode(articles) {
            userDefaults.set(encoded, forKey: articlesKey)
        }
    }

    private func loadArticles() {
        if let data = userDefaults.data(forKey: articlesKey),
           let decoded = try? JSONDecoder().decode([Article].self, from: data) {
            articles = decoded
        }
    }
}
