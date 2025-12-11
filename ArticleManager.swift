//
//  ArticleManager.swift
//  2 Music 2 Furious
//
//  Article models and management for text-to-speech reader
//  Pattern follows BookManager.swift for consistency
//

import Foundation
import SwiftUI

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

    /// Estimated reading time in minutes (assuming ~200 words per minute)
    var estimatedReadingTime: Int {
        let wordCount = content.split(separator: " ").count
        return max(1, wordCount / 200)
    }

    /// Word count for display
    var wordCount: Int {
        content.split(separator: " ").count
    }
}

// MARK: - Article Model

struct Article: Identifiable, Codable {
    let id: UUID
    var title: String
    var source: String               // Domain name or "Uploaded ePub", "Pasted Text", etc.
    var sourceURL: URL?              // Original URL if from web
    var author: String?
    var chapters: [ArticleChapter]
    var dateAdded: Date
    var lastReadChapter: Int
    var lastReadPosition: Int        // Character offset within chapter for TTS resume

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

    /// Total word count across all chapters
    var totalWordCount: Int {
        chapters.reduce(0) { $0 + $1.wordCount }
    }

    /// Total estimated reading time in minutes
    var totalReadingTime: Int {
        let wordCount = totalWordCount
        return max(1, wordCount / 200)
    }

    /// Formatted reading time string
    var formattedReadingTime: String {
        let minutes = totalReadingTime
        if minutes < 60 {
            return "\(minutes) min read"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m read" : "\(hours)h read"
        }
    }

    /// Display-friendly source (extracts domain from URL or returns source string)
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

    @Published var articles: [Article] = []

    private let userDefaults = UserDefaults.standard
    private let articlesKey = "savedArticles"

    init() {
        loadArticles()
    }

    // MARK: - CRUD Operations

    func addArticle(_ article: Article) {
        articles.insert(article, at: 0) // Newest first
        saveArticles()
    }

    func removeArticle(_ article: Article) {
        articles.removeAll { $0.id == article.id }
        saveArticles()
    }

    func updateArticle(_ article: Article) {
        if let index = articles.firstIndex(where: { $0.id == article.id }) {
            articles[index] = article
            saveArticles()
        }
    }

    // MARK: - Reading Progress

    func updateProgress(articleId: UUID, chapterIndex: Int, position: Int) {
        if let index = articles.firstIndex(where: { $0.id == articleId }) {
            articles[index].lastReadChapter = chapterIndex
            articles[index].lastReadPosition = position
            saveArticles()
        }
    }

    // MARK: - Article Creation Helpers

    /// Creates an article from plain text (single chapter)
    func createArticleFromText(title: String, text: String, source: String = "Pasted Text") -> Article {
        let chapter = ArticleChapter(title: title, content: text)
        return Article(
            title: title,
            source: source,
            chapters: [chapter]
        )
    }

    /// Creates an article from URL with extracted content
    /// For now, this is a placeholder - real extraction will be added in Phase 3/4
    func createArticleFromURL(url: URL, title: String, content: String, chapters: [ArticleChapter]? = nil) -> Article {
        let articleChapters: [ArticleChapter]

        if let chapters = chapters, !chapters.isEmpty {
            articleChapters = chapters
        } else {
            // Single chapter from content
            articleChapters = [ArticleChapter(title: title, content: content)]
        }

        return Article(
            title: title,
            source: url.host ?? "Web",
            sourceURL: url,
            chapters: articleChapters
        )
    }

    /// Splits content into chapters based on HTML headers (h2, h3)
    /// Returns array of chapters, or single chapter if no headers found
    func splitIntoChapters(title: String, content: String, html: String? = nil) -> [ArticleChapter] {
        // For now, simple implementation - look for markdown-style headers
        // Real HTML parsing will come in Phase 3

        let lines = content.components(separatedBy: "\n")
        var chapters: [ArticleChapter] = []
        var currentTitle = title
        var currentContent: [String] = []

        for line in lines {
            // Check for markdown headers (## or ###)
            if line.hasPrefix("## ") || line.hasPrefix("### ") {
                // Save previous chapter if it has content
                if !currentContent.isEmpty {
                    let chapterText = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chapterText.isEmpty {
                        chapters.append(ArticleChapter(title: currentTitle, content: chapterText))
                    }
                }
                // Start new chapter
                currentTitle = line.replacingOccurrences(of: "### ", with: "")
                    .replacingOccurrences(of: "## ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentContent = []
            } else {
                currentContent.append(line)
            }
        }

        // Don't forget the last chapter
        if !currentContent.isEmpty {
            let chapterText = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !chapterText.isEmpty {
                chapters.append(ArticleChapter(title: currentTitle, content: chapterText))
            }
        }

        // If no chapters were created, make one from all content
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
