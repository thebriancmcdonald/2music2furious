//
//  LibriVoxSearchView.swift
//  2 Music 2 Furious - MILESTONE 11
//
//  Search, browse, and download LibriVox audiobooks
//  Uses SharedComponents for consistency
//

import SwiftUI
import Combine

// MARK: - LibriVox Models

struct LibriVoxBook: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let author: String
    let description: String
    let totalTime: String
    let language: String
    let chapters: [LibriVoxChapter]
    let archiveUrl: String?
    
    var coverArtUrl: URL? {
        guard let archiveUrl = archiveUrl,
              let identifier = archiveUrl.components(separatedBy: "/").last,
              !identifier.isEmpty else {
            return nil
        }
        return URL(string: "https://archive.org/services/img/\(identifier)")
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, description, language
        case author = "authors"
        case totalTime = "totaltimesecs"
        case chapters = "sections"
        case archiveUrl = "url_iarchive"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "English"
        archiveUrl = try container.decodeIfPresent(String.self, forKey: .archiveUrl)
        
        if let authorsArray = try? container.decode([LibriVoxAuthor].self, forKey: .author) {
            author = authorsArray.first.map { "\($0.firstName) \($0.lastName)" } ?? "Unknown"
        } else if let singleAuthor = try? container.decode(LibriVoxAuthor.self, forKey: .author) {
            author = "\(singleAuthor.firstName) \(singleAuthor.lastName)"
        } else {
            author = "Unknown"
        }
        
        if let seconds = try? container.decode(Int.self, forKey: .totalTime) {
            totalTime = LibriVoxBook.formatTime(seconds)
        } else if let secondsString = try? container.decode(String.self, forKey: .totalTime), let seconds = Int(secondsString) {
            totalTime = LibriVoxBook.formatTime(seconds)
        } else {
            totalTime = "Unknown"
        }
        
        chapters = try container.decodeIfPresent([LibriVoxChapter].self, forKey: .chapters) ?? []
    }
    
    static func formatTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    init(id: String, title: String, author: String, description: String, totalTime: String, language: String, chapters: [LibriVoxChapter], archiveUrl: String? = nil) {
        self.id = id; self.title = title; self.author = author; self.description = description; self.totalTime = totalTime; self.language = language; self.chapters = chapters; self.archiveUrl = archiveUrl
    }
    
    static func == (lhs: LibriVoxBook, rhs: LibriVoxBook) -> Bool { lhs.id == rhs.id }
}

struct LibriVoxSearchResponse: Codable {
    let books: [LibriVoxBook]
}

// MARK: - API

class LibriVoxAPI: ObservableObject {
    @Published var displayBooks: [LibriVoxBook] = []
    @Published var isSearching = false
    @Published var isLoadingMore = false
    @Published var selectedBook: LibriVoxBook?
    @Published var isLoadingChapters = false
    
    private var currentOffset = 0
    private let limit = 20
    private var hasMoreResults = true
    private var currentMode: FetchMode = .popular
    private var lastQuery: String = ""
    private let baseURL = "https://librivox.org/api/feed/audiobooks"
    
    enum FetchMode { case popular, recent, search }
    
    func search(query: String) {
        guard !query.isEmpty else { return }
        resetPagination(mode: .search); lastQuery = query; isSearching = true; fetchBooks(query: query)
    }
    func loadPopular() { if currentMode != .popular || displayBooks.isEmpty { resetPagination(mode: .popular); isSearching = true; fetchBooks() } }
    func loadRecent() { if currentMode != .recent || displayBooks.isEmpty { resetPagination(mode: .recent); isSearching = true; fetchBooks() } }
    func loadNextPage() {
        guard !isLoadingMore && !isSearching && hasMoreResults else { return }
        isLoadingMore = true; currentOffset += limit; fetchBooks(query: lastQuery, isPagination: true)
    }
    
    private func resetPagination(mode: FetchMode) { currentMode = mode; currentOffset = 0; hasMoreResults = true; displayBooks = [] }
    
    private func fetchBooks(query: String = "", isPagination: Bool = false) {
        var urlString = "\(baseURL)?format=json&extended=1&limit=\(limit)&offset=\(currentOffset)"
        switch currentMode {
        case .recent: urlString += "&since=2024-01-01"
        case .search: urlString += "&title=^\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        default: break
        }
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSearching = false; self.isLoadingMore = false
                if let data = data, let response = try? JSONDecoder().decode(LibriVoxSearchResponse.self, from: data) {
                    let newBooks = response.books
                    if newBooks.count < self.limit { self.hasMoreResults = false }
                    if isPagination { self.displayBooks.append(contentsOf: newBooks) } else { self.displayBooks = newBooks }
                } else { if !isPagination { self.displayBooks = [] }; self.hasMoreResults = false }
            }
        }.resume()
    }
    
    func loadBookDetails(bookId: String) {
        isLoadingChapters = true
        let urlString = "\(baseURL)?id=\(bookId)&format=json&extended=1"
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.isLoadingChapters = false
                if let data = data, let response = try? JSONDecoder().decode(LibriVoxSearchResponse.self, from: data), let book = response.books.first {
                    self?.selectedBook = book
                }
            }
        }.resume()
    }
}

// MARK: - Views

struct LibriVoxSearchView: View {
    @StateObject private var api = LibriVoxAPI()
    @ObservedObject var bookManager: BookManager
    @ObservedObject var downloadManager = LibriVoxDownloadManager.shared
    
    let dismiss: () -> Void
    @State private var searchText = ""
    @State private var selectedTab: LibriVoxTab = .popular
    @State private var selectedBook: LibriVoxBook?
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    enum LibriVoxTab: String, CaseIterable { case popular = "Popular", recent = "Recent", search = "Search" }
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                
                VStack(spacing: 0) {
                    // Search Bar
                    GlassSearchBar(
                        text: $searchText,
                        placeholder: "Search audiobooks...",
                        onCommit: {
                            selectedTab = .search
                            api.search(query: searchText)
                        }
                    )
                    .padding()
                    
                    // Tab Picker
                    GlassSegmentedFilter(
                        selection: $selectedTab,
                        options: LibriVoxTab.allCases.map { ($0, $0.rawValue) },
                        color: .royalPurple,
                        onChange: { tab in
                            if tab == .popular { api.loadPopular() }
                            else if tab == .recent { api.loadRecent() }
                        }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    
                    // Content
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if selectedTab == .search && api.displayBooks.isEmpty && !api.isSearching {
                                if searchText.isEmpty {
                                    emptyView(icon: "magnifyingglass", text: "Search for audiobooks")
                                } else {
                                    emptyView(icon: "book.closed", text: "No results found")
                                }
                            } else {
                                bookListView(books: api.displayBooks, isLoading: api.isSearching)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
                
                if showingToast {
                    VStack { Spacer(); GlassToastView(message: toastMessage, icon: "arrow.down.circle.fill", iconColor: .royalPurple).padding(.bottom, 20) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(), value: showingToast)
                        .zIndex(100)
                }
            }
            .navigationTitle("LibriVox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
            }
            .sheet(item: $selectedBook) { book in
                LibriVoxBookDetailView(book: book, api: api, bookManager: bookManager, showToast: showToast, dismiss: { selectedBook = nil })
            }
            .onAppear { if api.displayBooks.isEmpty { api.loadPopular() } }
        }
        .accentColor(.royalPurple)
    }
    
    private func bookListView(books: [LibriVoxBook], isLoading: Bool) -> some View {
        Group {
            if isLoading && books.isEmpty {
                VStack(spacing: 16) { ProgressView(); Text("Loading...").foregroundColor(.secondary) }.padding(.top, 50)
            } else {
                ForEach(books) { book in
                    // Using Shared Component
                    GlassMediaListRow(
                        title: book.title,
                        subtitle: book.author,
                        artworkURL: book.coverArtUrl,
                        artworkIcon: "book.fill",
                        artworkColor: .orange,
                        details: "\(book.chapters.count) ch • \(book.totalTime)"
                    )
                    .onTapGesture { selectedBook = book; api.loadBookDetails(bookId: book.id) }
                    .onAppear { if book.id == books.last?.id { api.loadNextPage() } }
                }
                if api.isLoadingMore { HStack { Spacer(); ProgressView(); Spacer() }.padding() }
            }
        }
    }
    
    private func emptyView(icon: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 40)).foregroundColor(.secondary)
            Text(text).foregroundColor(.secondary)
        }
        .padding(.top, 50)
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { showingToast = false } }
    }
}

// MARK: - LibriVox Book Detail View

struct LibriVoxBookDetailView: View {
    let book: LibriVoxBook
    @ObservedObject var api: LibriVoxAPI
    @ObservedObject var bookManager: BookManager
    @ObservedObject var downloadManager = LibriVoxDownloadManager.shared
    
    let showToast: (String) -> Void
    let dismiss: () -> Void
    
    var displayBook: LibriVoxBook { api.selectedBook ?? book }
    var isDownloadingAll: Bool { downloadManager.downloadingBookId == book.id }
    
    func downloadAll() {
        showToast("Downloading \(displayBook.chapters.count) chapters...")
        for (index, chapter) in displayBook.chapters.enumerated() {
            downloadManager.downloadSingleChapter(chapter: chapter, bookId: displayBook.id, bookTitle: displayBook.title, author: displayBook.author, coverUrl: displayBook.coverArtUrl, description: displayBook.description, index: index, bookManager: bookManager, fullChapterList: displayBook.chapters)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        MediaDetailHeader(
                            title: displayBook.title,
                            subtitle: displayBook.author,
                            tertiaryText: "\(displayBook.chapters.count) chapters • \(displayBook.totalTime)",
                            artworkURL: displayBook.coverArtUrl,
                            artworkIcon: "book.fill",
                            artworkColor: .orange // LibriVox Orange accent for artwork
                        )
                        .padding(.horizontal)
                        
                        // Download All Button
                        GlassActionButton(
                            title: "Download All Chapters",
                            icon: "arrow.down.circle.fill",
                            isLoading: isDownloadingAll,
                            loadingText: "Downloading...",
                            color: .deepResumePurple, // UPDATED: Matches Resume Button in Books (Darker)
                            isDisabled: displayBook.chapters.isEmpty,
                            action: downloadAll
                        )
                        .padding(.horizontal)
                        
                        // Description
                        if !displayBook.description.isEmpty {
                            ExpandableDescriptionView(
                                text: displayBook.description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
                                color: .royalPurple
                            )
                            .padding(.horizontal)
                        }
                        
                        // Chapters
                        VStack(alignment: .leading, spacing: 12) {
                            if api.isLoadingChapters {
                                HStack { Spacer(); ProgressView("Loading chapters..."); Spacer() }.padding()
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(Array(displayBook.chapters.enumerated()), id: \.element.id) { index, chapter in
                                        // Using Shared Component
                                        GlassDownloadRow(
                                            index: index + 1,
                                            title: chapter.title,
                                            subtitle: chapter.formattedDuration,
                                            isDownloaded: downloadManager.isCompleted(bookId: displayBook.id, chapterId: chapter.id),
                                            isDownloading: downloadManager.isDownloading(bookId: displayBook.id, chapterId: chapter.id),
                                            color: .royalPurple,
                                            onDownload: {
                                                downloadManager.downloadSingleChapter(chapter: chapter, bookId: displayBook.id, bookTitle: displayBook.title, author: displayBook.author, coverUrl: displayBook.coverArtUrl, description: displayBook.description, index: index, bookManager: bookManager, fullChapterList: displayBook.chapters)
                                                showToast("Downloading \(chapter.title)...")
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
            }
        }
        .accentColor(.royalPurple)
    }
}
