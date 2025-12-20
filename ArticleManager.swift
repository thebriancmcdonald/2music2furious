//
//  ArticleManager.swift
//  2 Music 2 Furious
//
//  Article models and management for text-to-speech reader
//  PERFORMANCE UPDATE: Lazy loading for articles
//

import Foundation
import SwiftUI
import Combine

// MARK: - Article Chapter Model

struct ArticleChapter: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String              // Plain text for TTS
    var htmlContent: String?         // Original HTML for rich display (optional)

    init(id: UUID = UUID(), title: String, content: String, htmlContent: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.htmlContent = htmlContent
    }

    var estimatedReadingTime: Int {
        let wordCount = content.split(separator: " ").count
        return max(1, wordCount / 200)
    }

    var wordCount: Int {
        content.split(separator: " ").count
    }
}

// MARK: - Article Model

struct Article: Identifiable, Codable {
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
    
    /// Background task to fetch content for "Shell" articles
    private func hydrateArticleContent(_ article: Article) {
        guard let url = article.sourceURL else { return }
        
        // Mark as downloading (optional UI indicator)
        if let idx = articles.firstIndex(where: { $0.id == article.id }) {
            var updated = articles[idx]
            updated.isDownloading = true
            articles[idx] = updated
        }
        
        Task {
            do {
                let (title, content) = try await fetchAndParseURL(url)
                
                DispatchQueue.main.async {
                    if let idx = self.articles.firstIndex(where: { $0.id == article.id }) {
                        var updated = self.articles[idx]
                        
                        // Update title if the specific fetch found a better one
                        if updated.title == "New Article" || updated.title == "Web Article" {
                            updated.title = title
                        }
                        
                        // Update content
                        let newChapter = ArticleChapter(id: UUID(), title: title, content: content)
                        updated.chapters = [newChapter]
                        updated.isDownloading = false
                        
                        self.articles[idx] = updated
                        self.saveArticles()
                    }
                }
            } catch {
                print("Failed to hydrate article: \(error)")
                DispatchQueue.main.async {
                    if let idx = self.articles.firstIndex(where: { $0.id == article.id }) {
                        self.articles[idx].isDownloading = false
                    }
                }
            }
        }
    }

    // MARK: - Network / Parsing Logic
    
    private func fetchAndParseURL(_ url: URL) async throws -> (String, String) {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }

        // 1. Extract Title
        var title = "Web Article"
        if let titleMatch = html.range(of: "<title[^>]*>(.*?)</title>", options: .regularExpression) {
            title = String(html[titleMatch])
                .replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "</title>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Cleanup title
        if let pipeRange = title.range(of: " | ") { title = String(title[..<pipeRange.lowerBound]) }
        if let dashRange = title.range(of: " - ", options: .backwards) {
            let beforeDash = String(title[..<dashRange.lowerBound])
            if beforeDash.count > 10 { title = beforeDash }
        }

        // 2. Extract Content (Simple Heuristic)
        var content = html
        let contentPatterns = ["<article[^>]*>([\\s\\S]*?)</article>", "<main[^>]*>([\\s\\S]*?)</main>"]
        
        for pattern in contentPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                content = String(html[range])
                break
            }
        }

        // 3. Clean Content
        let removePatterns = [
            "<script[^>]*>[\\s\\S]*?</script>", "<style[^>]*>[\\s\\S]*?</style>",
            "<nav[^>]*>[\\s\\S]*?</nav>", "<footer[^>]*>[\\s\\S]*?</footer>",
            "<header[^>]*>[\\s\\S]*?</header>"
        ]
        for pattern in removePatterns {
            content = content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        content = content.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        content = content.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        content = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Decode Entities
        content = content
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        content = content.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if content.isEmpty { content = "Could not extract content from this page." }

        return (title, content)
    }
    
    // MARK: - UI Helper Logic
    
    func splitIntoChapters(title: String, content: String, html: String? = nil) -> [ArticleChapter] {
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
