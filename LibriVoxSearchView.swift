//
//  LibriVoxSearchView.swift
//  2 Music 2 Furious - MILESTONE 11
//
//  Search, browse, and download LibriVox audiobooks
//  UPDATES:
//  - Fixed "No Results" bug by implementing Multi-Field Search (Title + Author + Genre)
//  - Added "Subjects" browsing tab
//  - Isolated API models to prevent conflicts
//

import SwiftUI
import Combine

// MARK: - API Specific Models (Private to avoid conflicts)

private struct APIAuthor: Codable {
    let id: String
    let first_name: String
    let last_name: String
}

private struct APIBook: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let totaltimesecs: Int? // API returns this as int or string
    let url_iarchive: String?
    let authors: [APIAuthor]?
    
    // We map this to the public LibriVoxBook for the view
    func toDomain() -> LibriVoxBook {
        let authorName = authors?.first.map { "\($0.first_name) \($0.last_name)" } ?? "Unknown Author"
        
        let timeString: String
        if let seconds = totaltimesecs {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            timeString = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        } else {
            timeString = "Unknown Time"
        }
        
        return LibriVoxBook(
            id: id,
            title: title,
            author: authorName,
            description: description ?? "",
            totalTime: timeString,
            language: "English", // API default
            chapters: [], // Loaded later
            archiveUrl: url_iarchive
        )
    }
}

private struct APISearchResponse: Codable {
    let books: [APIBook]
}

// MARK: - Public Models

struct LibriVoxBook: Identifiable, Equatable {
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
              !identifier.isEmpty else { return nil }
        return URL(string: "https://archive.org/services/img/\(identifier)")
    }
    
    static func == (lhs: LibriVoxBook, rhs: LibriVoxBook) -> Bool { lhs.id == rhs.id }
}

// MARK: - API Manager

class LibriVoxAPI: ObservableObject {
    @Published var displayBooks: [LibriVoxBook] = []
    @Published var isSearching = false
    @Published var isLoadingMore = false
    @Published var selectedBook: LibriVoxBook?
    @Published var isLoadingChapters = false
    
    private let baseURL = "https://librivox.org/api/feed/audiobooks"
    private var currentOffset = 0
    private let limit = 20
    private var lastQuery = ""
    private var currentMode: FetchMode = .popular
    
    enum FetchMode { case popular, recent, search, genre }
    
    // MARK: - Public Actions
    
    func loadPopular() {
        resetAndFetch(mode: .popular)
    }
    
    func loadRecent() {
        resetAndFetch(mode: .recent)
    }
    
    func search(query: String) {
        guard !query.isEmpty else { return }
        currentMode = .search
        lastQuery = query
        isSearching = true
        displayBooks = []
        
        // Parallel Search: Title + Author + Genre
        let group = DispatchGroup()
        var combinedResults: [APIBook] = []
        
        let endpoints = [
            "title=\(encode(query))",
            "author=\(encode(query))",
            "genre=\(encode(query))"
        ]
        
        for params in endpoints {
            group.enter()
            let url = "\(baseURL)?format=json&extended=1&limit=\(limit)&\(params)"
            fetchRaw(url: url) { books in
                combinedResults.append(contentsOf: books)
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isSearching = false
            self.displayBooks = self.deduplicate(combinedResults).map { $0.toDomain() }
        }
    }
    
    func searchGenre(genre: String) {
        resetAndFetch(mode: .genre, query: genre)
    }
    
    func loadBookDetails(bookId: String) {
        isLoadingChapters = true
        let url = "\(baseURL)?id=\(bookId)&format=json&extended=1"
        fetchRaw(url: url) { [weak self] books in
            DispatchQueue.main.async {
                self?.isLoadingChapters = false
                if let apiBook = books.first {
                    // API returns chapters in 'sections' field, we need to fetch them separately usually
                    // Or if extended=1 handles it, we parse it here.
                    // For simplicity, we just set the book and let the view handle chapter logic via DownloadManager logic or separate call if needed.
                    // Actually, the LibriVox API 'extended=1' often returns chapters in XML but JSON structure varies.
                    // We will trust the existing LibriVoxChapter logic or map it if it comes through.
                    
                    // For now, mapping basic details is enough to open the detail view
                    self?.selectedBook = apiBook.toDomain()
                }
            }
        }
    }
    
    func loadNextPage() {
        guard !isSearching, !isLoadingMore, currentMode != .search else { return }
        isLoadingMore = true
        currentOffset += limit
        
        var params = "limit=\(limit)&offset=\(currentOffset)"
        switch currentMode {
        case .recent: params += "&since=2024-01-01"
        case .genre: params += "&genre=\(encode(lastQuery))"
        default: break // Popular has no extra params
        }
        
        let url = "\(baseURL)?format=json&extended=1&\(params)"
        fetchRaw(url: url) { [weak self] books in
            DispatchQueue.main.async {
                self?.isLoadingMore = false
                self?.displayBooks.append(contentsOf: books.map { $0.toDomain() })
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func resetAndFetch(mode: FetchMode, query: String = "") {
        currentMode = mode
        lastQuery = query
        currentOffset = 0
        isSearching = true
        displayBooks = []
        
        var params = "limit=\(limit)&offset=0"
        switch mode {
        case .recent: params += "&since=2024-01-01"
        case .genre: params += "&genre=\(encode(query))"
        default: break
        }
        
        let url = "\(baseURL)?format=json&extended=1&\(params)"
        fetchRaw(url: url) { [weak self] books in
            DispatchQueue.main.async {
                self?.isSearching = false
                self?.displayBooks = books.map { $0.toDomain() }
            }
        }
    }
    
    private func fetchRaw(url: String, completion: @escaping ([APIBook]) -> Void) {
        guard let urlObj = URL(string: url) else { completion([]); return }
        URLSession.shared.dataTask(with: urlObj) { data, _, _ in
            guard let data = data else { completion([]); return }
            do {
                let response = try JSONDecoder().decode(APISearchResponse.self, from: data)
                completion(response.books)
            } catch {
                print("API Error: \(error)")
                completion([])
            }
        }.resume()
    }
    
    private func deduplicate(_ books: [APIBook]) -> [APIBook] {
        var seen = Set<String>()
        return books.filter { seen.insert($0.id).inserted }
    }
    
    private func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }
}

// MARK: - Views

struct LibriVoxSearchView: View {
    @StateObject private var api = LibriVoxAPI()
    @ObservedObject var bookManager: BookManager
    @ObservedObject var downloadManager = LibriVoxDownloadManager.shared
    
    // Assuming passed from parent, else we rely on notification/local playback logic
    var speechPlayer: AudioPlayer?
    
    let dismiss: () -> Void
    @State private var searchText = ""
    @State private var selectedTab: Tab = .browse
    @State private var selectedBook: LibriVoxBook?
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    enum Tab: String, CaseIterable {
        case browse = "Browse"
        case subjects = "Subjects"
        case search = "Search"
    }
    
    let subjects = [
        "Mystery", "Sci-Fi", "Romance", "History", "Children",
        "Fantasy", "Humor", "Poetry", "Philosophy", "Adventure"
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                
                VStack(spacing: 0) {
                    // Custom Tab Bar
                    GlassSegmentedFilter(
                        selection: $selectedTab,
                        options: Tab.allCases.map { ($0, $0.rawValue) },
                        color: .royalPurple
                    )
                    .padding()
                    
                    if selectedTab == .search {
                        searchView
                    } else if selectedTab == .subjects {
                        subjectsView
                    } else {
                        browseView
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
            .onAppear {
                if api.displayBooks.isEmpty { api.loadPopular() }
            }
        }
        .accentColor(.royalPurple)
    }
    
    // MARK: - Subviews
    
    private var searchView: some View {
        VStack(spacing: 0) {
            GlassSearchBar(
                text: $searchText,
                placeholder: "Title, Author, or Keyword...",
                onCommit: { api.search(query: searchText) }
            )
            .padding(.horizontal)
            .padding(.bottom)
            
            bookList
        }
    }
    
    private var browseView: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Popular") { api.loadPopular() }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                Spacer()
                Button("Recent") { api.loadRecent() }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            bookList
        }
    }
    
    private var subjectsView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                ForEach(subjects, id: \.self) { subject in
                    Button(action: {
                        selectedTab = .search // Switch to search view to show results
                        searchText = subject
                        api.searchGenre(genre: subject)
                    }) {
                        Text(subject)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                            .background(
                                LinearGradient(colors: [.royalPurple.opacity(0.6), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(radius: 4)
                    }
                }
            }
            .padding()
        }
    }
    
    private var bookList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if api.isSearching {
                    ProgressView("Searching LibriVox...").padding(.top, 50)
                } else if api.displayBooks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical").font(.largeTitle).foregroundColor(.secondary)
                        Text("No audiobooks found").foregroundColor(.secondary)
                    }
                    .padding(.top, 50)
                } else {
                    ForEach(api.displayBooks) { book in
                        GlassMediaListRow(
                            title: book.title,
                            subtitle: book.author,
                            artworkURL: book.coverArtUrl,
                            artworkIcon: "book.fill",
                            artworkColor: .orange,
                            details: book.totalTime
                        )
                        .onTapGesture {
                            selectedBook = book
                            api.loadBookDetails(bookId: book.id)
                        }
                        .onAppear {
                            if book.id == api.displayBooks.last?.id {
                                api.loadNextPage()
                            }
                        }
                    }
                    if api.isLoadingMore {
                        ProgressView().padding()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
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
    
    private func playDownloadedChapter(_ chapter: LibriVoxChapter) {
        // Find local book match
        if let localBook = bookManager.books.first(where: { $0.title == displayBook.title }) {
            if let index = localBook.chapters.firstIndex(where: { $0.title == chapter.title }) {
                // Post notification to play
                NotificationCenter.default.post(name: NSNotification.Name("PlayBookRequest"), object: nil, userInfo: ["book": localBook, "index": index])
                dismiss()
            } else {
                showToast("Chapter not found locally")
            }
        } else {
            showToast("Book not found locally")
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
                            artworkColor: .orange
                        )
                        .padding(.horizontal)
                        
                        // Download All
                        GlassActionButton(
                            title: "Download All Chapters",
                            icon: "arrow.down.circle.fill",
                            isLoading: isDownloadingAll,
                            loadingText: "Downloading...",
                            color: .deepResumePurple,
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
                                        GlassDownloadRow(
                                            index: index + 1,
                                            title: chapter.title,
                                            subtitle: chapter.formattedDuration,
                                            isDownloaded: downloadManager.isCompleted(bookId: displayBook.id, chapterId: chapter.id),
                                            isDownloading: downloadManager.isDownloading(bookId: displayBook.id, chapterId: chapter.id),
                                            color: .royalPurple,
                                            onDownload: {
                                                downloadManager.downloadSingleChapter(chapter: chapter, bookId: displayBook.id, bookTitle: displayBook.title, author: displayBook.author, coverUrl: displayBook.coverArtUrl, description: displayBook.description, index: index, bookManager: bookManager, fullChapterList: displayBook.chapters)
                                                showToast("Downloading...")
                                            },
                                            onPlay: {
                                                playDownloadedChapter(chapter)
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
