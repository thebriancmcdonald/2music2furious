//
//  ShareViewController.swift
//  SaveToReader (Share Extension)
//
//  Share Extension for saving web articles and text to 2 Music 2 Furious
//

import UIKit
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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
        activityIndicator.color = UIColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1.0)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        containerView.addSubview(activityIndicator)

        // Status Label
        statusLabel = UILabel()
        statusLabel.text = "Saving to Reader..."
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        statusLabel.textColor = .label
        statusLabel.numberOfLines = 2
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
            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        ])
    }

    // MARK: - Process Shared Content

    private func processSharedContent() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeWithError("No content found")
            return
        }

        for extensionItem in extensionItems {
            guard let attachments = extensionItem.attachments else { continue }

            for attachment in attachments {
                // Try URL first
                if attachment.hasItemConformingToTypeIdentifier("public.url") {
                    attachment.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] (item, error) in
                        DispatchQueue.main.async {
                            if let url = item as? URL {
                                self?.handleURL(url)
                            } else if let urlString = item as? String, let url = URL(string: urlString) {
                                self?.handleURL(url)
                            } else {
                                self?.completeWithError("Could not load URL")
                            }
                        }
                    }
                    return
                }

                // Try plain text
                if attachment.hasItemConformingToTypeIdentifier("public.plain-text") {
                    attachment.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] (item, error) in
                        DispatchQueue.main.async {
                            if let text = item as? String {
                                // Check if it looks like a URL
                                if text.hasPrefix("http://") || text.hasPrefix("https://"),
                                   let url = URL(string: text) {
                                    self?.handleURL(url)
                                } else {
                                    self?.handleText(text)
                                }
                            } else {
                                self?.completeWithError("Could not load text")
                            }
                        }
                    }
                    return
                }
            }
        }

        completeWithError("No supported content")
    }

    // MARK: - Handle URL

    private func handleURL(_ url: URL) {
        statusLabel.text = "Fetching article..."

        // Fetch article in background
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.completeWithError("Network error")
                    return
                }

                guard let data = data,
                      let html = String(data: data, encoding: .utf8) else {
                    self?.completeWithError("Could not read page")
                    return
                }

                // Extract title
                var title = url.host ?? "Web Article"
                if let range = html.range(of: "<title[^>]*>(.*?)</title>", options: .regularExpression) {
                    title = String(html[range])
                        .replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "</title>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Clean title
                if let pipeRange = title.range(of: " | ") {
                    title = String(title[..<pipeRange.lowerBound])
                }
                if let dashRange = title.range(of: " - ", options: .backwards) {
                    let beforeDash = String(title[..<dashRange.lowerBound])
                    if beforeDash.count > 10 {
                        title = beforeDash
                    }
                }

                if title.isEmpty { title = "Web Article" }

                // Decode HTML entities in title
                title = self?.decodeHTMLEntities(title) ?? title

                // Extract and clean content
                var content = html

                // Remove scripts and styles
                content = content.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
                content = content.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
                content = content.replacingOccurrences(of: "<nav[^>]*>[\\s\\S]*?</nav>", with: "", options: .regularExpression)
                content = content.replacingOccurrences(of: "<footer[^>]*>[\\s\\S]*?</footer>", with: "", options: .regularExpression)

                // Convert to plain text
                content = content.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
                content = content.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
                content = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

                // Decode HTML entities
                content = self?.decodeHTMLEntities(content) ?? content

                // Aggressive whitespace cleaning
                // Remove leading/trailing whitespace from each line
                content = content.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: "\n")

                // Replace multiple spaces with single space
                content = content.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

                // Replace 3+ newlines with just 2
                content = content.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

                // Remove lines that are just whitespace
                content = content.components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty || $0.isEmpty }
                    .joined(separator: "\n")

                // Final trim
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)

                if content.isEmpty {
                    self?.completeWithError("No content found")
                    return
                }

                // Create and save article
                let article = ArticleData(
                    id: UUID(),
                    title: title,
                    source: url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web",
                    sourceURL: url,
                    author: nil,
                    chapters: [ChapterData(id: UUID(), title: title, content: content)],
                    dateAdded: Date(),
                    lastReadChapter: 0,
                    lastReadPosition: 0
                )

                self?.saveArticle(article)
                self?.completeWithSuccess(title)
            }
        }.resume()
    }

    // MARK: - Handle Text

    private func handleText(_ text: String) {
        let title = String(text.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.count > 40 ? title.prefix(40) + "..." : title

        let article = ArticleData(
            id: UUID(),
            title: String(displayTitle),
            source: "Shared Text",
            sourceURL: nil,
            author: nil,
            chapters: [ChapterData(id: UUID(), title: String(displayTitle), content: text)],
            dateAdded: Date(),
            lastReadChapter: 0,
            lastReadPosition: 0
        )

        saveArticle(article)
        completeWithSuccess("Text saved!")
    }

    // MARK: - HTML Entity Decoding

    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string

        // Named entities
        let namedEntities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"),
            ("&rsquo;", "\u{2019}"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™"),
            ("&bull;", "•"),
            ("&middot;", "·")
        ]

        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Decimal entities (&#39; &#8217; etc.)
        while let range = result.range(of: "&#[0-9]+;", options: .regularExpression) {
            let entity = String(result[range])
            let numberStr = entity.dropFirst(2).dropLast()
            if let codePoint = Int(numberStr),
               let scalar = Unicode.Scalar(codePoint) {
                result.replaceSubrange(range, with: String(Character(scalar)))
            } else {
                break
            }
        }

        // Hex entities (&#x27; &#x2019; etc.)
        while let range = result.range(of: "&#[xX][0-9a-fA-F]+;", options: .regularExpression) {
            let entity = String(result[range])
            let hexStr = entity.dropFirst(3).dropLast() // Remove &#x and ;
            if let codePoint = Int(hexStr, radix: 16),
               let scalar = Unicode.Scalar(codePoint) {
                result.replaceSubrange(range, with: String(Character(scalar)))
            } else {
                break
            }
        }

        return result
    }

    // MARK: - Save Article

    private func saveArticle(_ article: ArticleData) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("ShareExtension: Could not access App Group")
            return
        }

        // Load existing pending articles
        var pendingArticles: [ArticleData] = []
        if let data = userDefaults.data(forKey: pendingArticlesKey),
           let existing = try? JSONDecoder().decode([ArticleData].self, from: data) {
            pendingArticles = existing
        }

        // Add new article at beginning
        pendingArticles.insert(article, at: 0)

        // Save
        if let encoded = try? JSONEncoder().encode(pendingArticles) {
            userDefaults.set(encoded, forKey: pendingArticlesKey)
            userDefaults.synchronize()
            print("ShareExtension: Saved article '\(article.title)'")
        }
    }

    // MARK: - Completion

    private func completeWithSuccess(_ title: String) {
        activityIndicator.stopAnimating()

        // Show checkmark
        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.tintColor = UIColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1.0)
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(checkmark)

        NSLayoutConstraint.activate([
            checkmark.centerXAnchor.constraint(equalTo: activityIndicator.centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: activityIndicator.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 40),
            checkmark.heightAnchor.constraint(equalToConstant: 40)
        ])

        statusLabel.text = "Saved!"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func completeWithError(_ message: String) {
        activityIndicator.stopAnimating()
        statusLabel.text = message
        statusLabel.textColor = .systemRed

        // Show X mark
        let xmark = UIImageView(image: UIImage(systemName: "xmark.circle.fill"))
        xmark.tintColor = .systemRed
        xmark.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(xmark)

        NSLayoutConstraint.activate([
            xmark.centerXAnchor.constraint(equalTo: activityIndicator.centerXAnchor),
            xmark.centerYAnchor.constraint(equalTo: activityIndicator.centerYAnchor),
            xmark.widthAnchor.constraint(equalToConstant: 40),
            xmark.heightAnchor.constraint(equalToConstant: 40)
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 1))
        }
    }
}

// MARK: - Data Models (must match main app's Article/ArticleChapter structure)

struct ChapterData: Codable {
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

struct ArticleData: Codable {
    let id: UUID
    var title: String
    var source: String
    var sourceURL: URL?
    var author: String?
    var chapters: [ChapterData]
    var dateAdded: Date
    var lastReadChapter: Int
    var lastReadPosition: Int
}
