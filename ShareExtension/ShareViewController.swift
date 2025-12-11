//
//  ShareViewController.swift
//  SaveToReader (Share Extension)
//
//  Share Extension for saving web articles and text to 2 Music 2 Furious
//  Handles URLs (extracts article content) and plain text
//

import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    // App Group identifier - MUST match ArticleManager.appGroupIdentifier
    private let appGroupIdentifier = "group.com.2music2furious.shared"
    private let pendingArticlesKey = "pendingArticles"

    // UI Elements
    private var statusLabel: UILabel!
    private var activityIndicator: UIActivityIndicatorView!
    private var containerView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedContent()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        // Container
        containerView = UIView()
        containerView.backgroundColor = UIColor.systemBackground
        containerView.layer.cornerRadius = 16
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Activity Indicator
        activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = UIColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1.0) // Royal purple
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        containerView.addSubview(activityIndicator)

        // Status Label
        statusLabel = UILabel()
        statusLabel.text = "Saving to Reader..."
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        statusLabel.textColor = .label
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 250),
            containerView.heightAnchor.constraint(equalToConstant: 120),

            activityIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),

            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        ])
    }

    // MARK: - Process Shared Content

    private func processSharedContent() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeWithError("No content to share")
            return
        }

        for extensionItem in extensionItems {
            guard let attachments = extensionItem.attachments else { continue }

            for attachment in attachments {
                // Handle URLs
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                        if let url = item as? URL {
                            self?.handleURL(url)
                        } else if let error = error {
                            self?.completeWithError("Failed to load URL: \(error.localizedDescription)")
                        }
                    }
                    return
                }

                // Handle plain text
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (item, error) in
                        if let text = item as? String {
                            // Check if it's a URL string
                            if let url = URL(string: text), url.scheme != nil {
                                self?.handleURL(url)
                            } else {
                                self?.handleText(text)
                            }
                        } else if let error = error {
                            self?.completeWithError("Failed to load text: \(error.localizedDescription)")
                        }
                    }
                    return
                }
            }
        }

        completeWithError("No supported content found")
    }

    // MARK: - Handle URL

    private func handleURL(_ url: URL) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Fetching article..."
        }

        // Fetch and extract article content
        Task {
            do {
                let article = try await extractArticle(from: url)
                saveArticle(article)
                completeWithSuccess("Saved: \(article.title)")
            } catch {
                completeWithError("Failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Handle Text

    private func handleText(_ text: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Saving text..."
        }

        // Create article from plain text
        let title = extractTitle(from: text) ?? "Shared Text"
        let chapter = ArticleChapterSimple(id: UUID(), title: title, content: text)
        let article = ArticleSimple(
            id: UUID(),
            title: title,
            source: "Shared Text",
            sourceURL: nil,
            author: nil,
            chapters: [chapter],
            dateAdded: Date(),
            lastReadChapter: 0,
            lastReadPosition: 0
        )

        saveArticle(article)
        completeWithSuccess("Text saved!")
    }

    // MARK: - Article Extraction

    private func extractArticle(from url: URL) async throws -> ArticleSimple {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ShareError.networkError
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ShareError.parsingError
        }

        // Extract title
        var title = url.lastPathComponent
        if let titleMatch = html.range(of: "<title[^>]*>(.*?)</title>", options: .regularExpression) {
            title = String(html[titleMatch])
                .replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "</title>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Clean title - remove site name suffix
        if let pipeRange = title.range(of: " | ") {
            title = String(title[..<pipeRange.lowerBound])
        }
        if let dashRange = title.range(of: " - ", options: .backwards) {
            let beforeDash = String(title[..<dashRange.lowerBound])
            if beforeDash.count > 10 {
                title = beforeDash
            }
        }

        if title.isEmpty {
            title = "Web Article"
        }

        // Extract content
        var content = html

        // Try to find article/main content
        let contentPatterns = [
            "<article[^>]*>([\\s\\S]*?)</article>",
            "<main[^>]*>([\\s\\S]*?)</main>"
        ]

        for pattern in contentPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                content = String(html[range])
                break
            }
        }

        // Remove scripts, styles, nav, etc.
        let removePatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<header[^>]*>[\\s\\S]*?</header>"
        ]

        for pattern in removePatterns {
            content = content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Convert to plain text
        content = content.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        content = content.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        content = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        content = content
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        // Clean whitespace
        content = content.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw ShareError.noContent
        }

        let chapter = ArticleChapterSimple(id: UUID(), title: title, content: content)

        return ArticleSimple(
            id: UUID(),
            title: title,
            source: url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web",
            sourceURL: url,
            author: nil,
            chapters: [chapter],
            dateAdded: Date(),
            lastReadChapter: 0,
            lastReadPosition: 0
        )
    }

    private func extractTitle(from text: String) -> String? {
        // Try to extract a title from the first line
        let lines = text.components(separatedBy: .newlines)
        if let firstLine = lines.first?.trimmingCharacters(in: .whitespaces),
           !firstLine.isEmpty && firstLine.count < 100 {
            return firstLine
        }
        return nil
    }

    // MARK: - Save Article

    private func saveArticle(_ article: ArticleSimple) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            completeWithError("App Group not configured")
            return
        }

        // Load existing pending articles
        var pendingArticles: [ArticleSimple] = []
        if let data = userDefaults.data(forKey: pendingArticlesKey),
           let existing = try? JSONDecoder().decode([ArticleSimple].self, from: data) {
            pendingArticles = existing
        }

        // Add new article
        pendingArticles.insert(article, at: 0)

        // Save
        if let encoded = try? JSONEncoder().encode(pendingArticles) {
            userDefaults.set(encoded, forKey: pendingArticlesKey)
        }
    }

    // MARK: - Completion

    private func completeWithSuccess(_ message: String) {
        DispatchQueue.main.async {
            self.activityIndicator.stopAnimating()
            self.statusLabel.text = message

            // Show checkmark
            let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            checkmark.tintColor = UIColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1.0)
            checkmark.translatesAutoresizingMaskIntoConstraints = false
            self.containerView.addSubview(checkmark)
            NSLayoutConstraint.activate([
                checkmark.centerXAnchor.constraint(equalTo: self.containerView.centerXAnchor),
                checkmark.topAnchor.constraint(equalTo: self.containerView.topAnchor, constant: 24),
                checkmark.widthAnchor.constraint(equalToConstant: 40),
                checkmark.heightAnchor.constraint(equalToConstant: 40)
            ])

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    private func completeWithError(_ message: String) {
        DispatchQueue.main.async {
            self.activityIndicator.stopAnimating()
            self.statusLabel.text = message
            self.statusLabel.textColor = .systemRed

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.extensionContext?.cancelRequest(withError: ShareError.failed)
            }
        }
    }
}

// MARK: - Simple Article Models (for Share Extension)
// These mirror the main app's models but are self-contained

struct ArticleChapterSimple: Codable {
    let id: UUID
    var title: String
    var content: String
    var htmlContent: String?

    init(id: UUID = UUID(), title: String, content: String, htmlContent: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.htmlContent = htmlContent
    }
}

struct ArticleSimple: Codable {
    let id: UUID
    var title: String
    var source: String
    var sourceURL: URL?
    var author: String?
    var chapters: [ArticleChapterSimple]
    var dateAdded: Date
    var lastReadChapter: Int
    var lastReadPosition: Int
}

enum ShareError: Error {
    case networkError
    case parsingError
    case noContent
    case failed
}
