//
//  ArticleLibraryView.swift
//  2 Music 2 Furious
//
//  Article library for text-to-speech reader
//  Pattern follows BookLibraryView.swift for consistency
//

import SwiftUI
import UniformTypeIdentifiers

struct ArticleLibraryView: View {
    @ObservedObject var articleManager: ArticleManager
    @ObservedObject var speechPlayer: AudioPlayer
    let dismiss: () -> Void

    @State private var showingAddURL = false
    @State private var showingAddText = false
    @State private var showingFilePicker = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var toastIcon = "checkmark.circle.fill"
    @State private var isImporting = false

    // For URL input sheet
    @State private var urlInput = ""
    @State private var isLoadingURL = false

    // For text input sheet
    @State private var textTitle = ""
    @State private var textContent = ""

    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()

                if articleManager.articles.isEmpty {
                    GlassEmptyStateView(
                        icon: "doc.text",
                        title: "No Articles Yet",
                        subtitle: "Import files, add URLs, or paste text\nto listen while you work.",
                        actions: [
                            (icon: "doc.badge.plus", title: "Import File", action: { showingFilePicker = true }),
                            (icon: "doc.on.clipboard", title: "Paste Text", action: { showingAddText = true })
                        ]
                    )
                } else {
                    List {
                        ForEach(articleManager.articles) { article in
                            ZStack {
                                NavigationLink(destination: ArticleReaderView(
                                    article: article,
                                    articleManager: articleManager,
                                    speechPlayer: speechPlayer
                                )) { EmptyView() }.opacity(0)

                                GlassArticleRow(article: article)
                            }
                            .glassListRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    articleManager.removeArticle(article)
                                    showToast("Article removed")
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.royalPurple)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .tint(.royalPurple)
                }

                // Toast
                if showingToast {
                    VStack {
                        Spacer()
                        GlassToastView(message: toastMessage, icon: toastIcon, iconColor: toastIcon.contains("exclamation") ? .orange : .royalPurple)
                            .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: showingToast)
                    .zIndex(100)
                }

                // Loading overlay
                if isImporting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Importing...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                }
            }
            .navigationTitle("Articles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingFilePicker = true } label: {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.white)
                    }

                    Button { showingAddURL = true } label: {
                        Image(systemName: "link")
                            .foregroundColor(.white)
                    }

                    Button { showingAddText = true } label: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showingAddURL) {
                AddURLSheet(
                    urlInput: $urlInput,
                    isLoading: $isLoadingURL,
                    onAdd: { addArticleFromURL() },
                    onCancel: { showingAddURL = false }
                )
            }
            .sheet(isPresented: $showingAddText) {
                AddTextSheet(
                    title: $textTitle,
                    content: $textContent,
                    onAdd: { addArticleFromText() },
                    onCancel: { showingAddText = false }
                )
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf, .html, .plainText, UTType(filenameExtension: "epub") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
        }
        .accentColor(.royalPurple)
        .tint(.royalPurple)
    }

    // MARK: - File Import

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFile(from: url)
        case .failure(let error):
            showToast("Import failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill")
        }
    }

    private func importFile(from url: URL) {
        isImporting = true

        Task {
            do {
                let article = try await DocumentImporter.importDocument(from: url)

                await MainActor.run {
                    articleManager.addArticle(article)
                    isImporting = false
                    showToast("\"\(article.title)\" imported!")
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    showToast("Import failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    // MARK: - Actions

    private func addArticleFromURL() {
        guard let url = URL(string: urlInput), !urlInput.isEmpty else {
            showToast("Please enter a valid URL")
            return
        }

        isLoadingURL = true

        // For Phase 1, we'll create a placeholder article
        // Real URL extraction comes in Phase 3/4
        let title = url.lastPathComponent.isEmpty ? "Web Article" : url.lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        // Placeholder content - real extraction will replace this
        let placeholderContent = """
        This article was saved from \(url.host ?? "the web").

        Full article extraction will be available in a future update. For now, you can paste article text directly using the "Paste Text" option.

        URL: \(url.absoluteString)
        """

        let article = articleManager.createArticleFromURL(
            url: url,
            title: title,
            content: placeholderContent
        )

        articleManager.addArticle(article)

        urlInput = ""
        isLoadingURL = false
        showingAddURL = false
        showToast("Article saved!")
    }

    private func addArticleFromText() {
        guard !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("Please enter some text")
            return
        }

        let title = textTitle.isEmpty ? "Pasted Text" : textTitle
        let cleanContent = textContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to split into chapters if there are headers
        let chapters = articleManager.splitIntoChapters(title: title, content: cleanContent)

        let article = Article(
            title: title,
            source: "Pasted Text",
            chapters: chapters
        )

        articleManager.addArticle(article)

        textTitle = ""
        textContent = ""
        showingAddText = false
        showToast("Article added!")
    }

    private func showToast(_ message: String, icon: String = "checkmark.circle.fill") {
        toastMessage = message
        toastIcon = icon
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showingToast = false }
        }
    }
}

// MARK: - Glass Article Row

struct GlassArticleRow: View {
    let article: Article

    var body: some View {
        HStack(spacing: 12) {
            // Icon based on source
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.royalPurple.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: iconForSource(article.source))
                    .font(.system(size: 22))
                    .foregroundColor(.royalPurple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(article.displaySource)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text(article.formattedReadingTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if article.chapters.count > 1 {
                    Text("\(article.chapters.count) sections")
                        .font(.caption2)
                        .foregroundColor(.royalPurple)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary.opacity(0.5))
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(12)
        .glassCard()
    }

    private func iconForSource(_ source: String) -> String {
        switch source.lowercased() {
        case "pasted text":
            return "doc.on.clipboard"
        case "epub", "uploaded epub":
            return "book.closed"
        case "pdf", "uploaded pdf":
            return "doc.richtext"
        case "uploaded html", "uploaded text":
            return "doc.plaintext"
        default:
            return "globe"
        }
    }
}

// MARK: - Add URL Sheet

struct AddURLSheet: View {
    @Binding var urlInput: String
    @Binding var isLoading: Bool
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Article URL")
                            .font(.headline)

                        TextField("https://example.com/article", text: $urlInput)
                            .textFieldStyle(.plain)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }

                    Text("Paste a URL to save an article for reading and listening.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer()

                    GlassActionButton(
                        title: "Add Article",
                        icon: "plus.circle.fill",
                        isLoading: isLoading,
                        loadingText: "Loading...",
                        color: .royalPurple,
                        isDisabled: urlInput.isEmpty,
                        action: onAdd
                    )
                }
                .padding(24)
            }
            .navigationTitle("Add from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundColor(.royalPurple)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Add Text Sheet

struct AddTextSheet: View {
    @Binding var title: String
    @Binding var content: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title (optional)")
                            .font(.headline)

                        TextField("Article title", text: $title)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Content")
                            .font(.headline)

                        TextEditor(text: $content)
                            .scrollContentBackground(.hidden)
                            .padding()
                            .frame(minHeight: 200)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }

                    Text("Paste or type text to create an article. Use ## headers to create sections.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer()

                    GlassActionButton(
                        title: "Add Article",
                        icon: "plus.circle.fill",
                        color: .royalPurple,
                        isDisabled: content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: onAdd
                    )
                }
                .padding(24)
            }
            .navigationTitle("Paste Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundColor(.royalPurple)
                }
            }
        }
    }
}
