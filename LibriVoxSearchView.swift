//
//  LibriVoxSearchView.swift
//  2 Music 2 Furious - MILESTONE 14
//
//  Search, browse, and download LibriVox audiobooks
//  FIXED: Proper API query syntax with partial matching (^) and multi-word (+)
//

import SwiftUI
import Combine

// MARK: - API Specific Models (Private to avoid conflicts)

private struct APISection: Codable, Sendable {
    let title: String?
    let playtime: String?
    let listen_url: String?
}

private struct APIAuthor: Codable, Sendable {
    let id: String
    let first_name: String
    let last_name: String
}

private struct APIBook: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String?
    let totaltimesecs: Int?
    let url_iarchive: String?
    let authors: [APIAuthor]?
    let sections: [APISection]?
    
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
        
        var domainChapters: [LibriVoxChapter] = []
        if let apiSections = sections {
            for (index, section) in apiSections.enumerated() {
                if let url = section.listen_url {
                    let chapter = LibriVoxChapter(
                        id: UUID().uuidString,
                        title: section.title ?? "Chapter \(index + 1)",
                        listenUrl: url,
                        playtime: section.playtime ?? "0"
                    )
                    domainChapters.append(chapter)
                }
            }
        }
        
        return LibriVoxBook(
            id: id,
            title: title,
            author: authorName,
            description: description ?? "",
            totalTime: timeString,
            language: "English",
            chapters: domainChapters,
            archiveUrl: url_iarchive
        )
    }
    
    /// Calculate relevance score for a search query (higher = better match)
    func relevanceScore(for tokens: [String]) -> Int {
        var score = 0
        let titleLower = title.lowercased()
        let descLower = (description ?? "").lowercased()
        
        // Build author string
        var authorString = ""
        if let authors = authors {
            authorString = authors.map { "\($0.first_name) \($0.last_name)" }.joined(separator: " ").lowercased()
        }
        
        for token in tokens {
            // Title exact word match = highest score
            if titleLower.contains(" \(token) ") || titleLower.hasPrefix("\(token) ") || titleLower.hasSuffix(" \(token)") || titleLower == token {
                score += 100
            }
            // Title contains token
            else if titleLower.contains(token) {
                score += 50
            }
            
            // Author exact match
            if authorString.contains(token) {
                score += 75
            }
            
            // Description contains token (lower score)
            if descLower.contains(token) {
                score += 10
            }
        }
        
        return score
    }
}

private struct APISearchResponse: Codable, Sendable {
    let books: [APIBook]?  // Optional because API returns {} when no results
    
    var booksList: [APIBook] {
        books ?? []
    }
}

// MARK: - Public Models

struct LibriVoxBook: Identifiable, Equatable, Hashable {
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
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - API Manager

class LibriVoxAPI: ObservableObject {
    @Published var displayBooks: [LibriVoxBook] = []
    @Published var isSearching = false
    @Published var isLoadingMore = false
    
    private let baseURL = "https://librivox.org/api/feed/audiobooks"
    private var currentOffset = 0
    private let browseLimit = 50       // For browsing (Popular/Recent) - API default
    private let searchLimit = 200      // Higher limit for search to find more results
    private var lastQuery = ""
    private var lastSearchTokens: [String] = []
    private var currentMode: FetchMode = .popular
    
    enum FetchMode { case popular, recent, search, genre }
    
    func loadPopular() { resetAndFetch(mode: .popular) }
    func loadRecent() { resetAndFetch(mode: .recent) }
    
    // MARK: - FIXED SEARCH IMPLEMENTATION
    
    /// Main search function using correct LibriVox API syntax
    /// API Notes:
    ///   - `^` anchors the BEGINNING of search: title=^Benjamin finds "Benjamin Franklin's..."
    ///   - `author` searches by LAST NAME only
    ///   - Without `^`, does partial/contains match
    func search(query: String) {
        guard !query.isEmpty else { return }
        currentMode = .search
        lastQuery = query
        isSearching = true
        displayBooks = []
        
        // Parse query into lowercase tokens
        let tokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 1 }
        
        lastSearchTokens = tokens
        
        guard !tokens.isEmpty else {
            isSearching = false
            return
        }
        
        // Build search endpoints using correct API syntax
        var searchEndpoints: Set<String> = []
        
        // === TITLE SEARCHES ===
        
        // 1. Full phrase contains search (no ^)
        let fullPhrase = query.trimmingCharacters(in: .whitespaces)
        searchEndpoints.insert("title=\(encodeForURL(fullPhrase))")
        
        // 2. Each individual word - contains search
        for token in tokens {
            searchEndpoints.insert("title=\(encodeForURL(token))")
        }
        
        // 3. Anchored search - titles STARTING with first word
        searchEndpoints.insert("title=^\(encodeForURL(tokens.first!))")
        
        // === AUTHOR SEARCHES ===
        // API docs say: "author - all records by that author last name"
        
        // 4. Try each token as author last name
        for token in tokens {
            searchEndpoints.insert("author=\(encodeForURL(token))")
        }
        
        // 5. Try anchored author search
        if let lastName = tokens.last {
            searchEndpoints.insert("author=^\(encodeForURL(lastName))")
        }
        
        print("🔍 LibriVox Search: '\(query)' → \(searchEndpoints.count) API calls")
        print("🔍 Tokens: \(tokens)")
        
        let group = DispatchGroup()
        var combinedResults: [APIBook] = []
        let resultsLock = NSLock()
        
        for params in searchEndpoints {
            group.enter()
            // Use higher limit for better coverage
            let urlString = "\(baseURL)?format=json&extended=1&limit=\(searchLimit)&\(params)"
            
            guard let url = URL(string: urlString) else {
                print("❌ Invalid URL: \(urlString)")
                group.leave()
                continue
            }
            
            print("📡 Fetching: \(urlString)")
            
            URLSession.shared.dataTask(with: url) { data, response, error in
                defer { group.leave() }
                
                if let error = error {
                    print("❌ Network error for \(params): \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("❌ No data for \(params)")
                    return
                }
                
                // Debug: Print raw response preview
                if let rawString = String(data: data, encoding: .utf8) {
                    let preview = String(rawString.prefix(300))
                    print("📦 Response for \(params): \(preview)...")
                }
                
                do {
                    let response = try JSONDecoder().decode(APISearchResponse.self, from: data)
                    let books = response.booksList
                    resultsLock.lock()
                    combinedResults.append(contentsOf: books)
                    resultsLock.unlock()
                    print("✅ Got \(books.count) results from \(params)")
                } catch {
                    print("❌ Decode error for \(params): \(error)")
                }
            }.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.processSearchResults(combinedResults, tokens: tokens)
        }
    }
    
    /// Process and filter search results
    private func processSearchResults(_ results: [APIBook], tokens: [String]) {
        // Deduplicate by ID
        var seen = Set<String>()
        var uniqueBooks = results.filter { seen.insert($0.id).inserted }
        
        // Filter: Keep only books where at least one token appears in title, author, or description
        let filteredBooks = uniqueBooks.filter { book in
            let searchable = "\(book.title) \(book.authors?.map { "\($0.first_name) \($0.last_name)" }.joined(separator: " ") ?? "") \(book.description ?? "")".lowercased()
            
            // Require at least one token to match
            return tokens.contains { searchable.contains($0) }
        }
        
        // Sort by relevance score (higher = better match)
        let sortedBooks = filteredBooks.sorted { book1, book2 in
            book1.relevanceScore(for: tokens) > book2.relevanceScore(for: tokens)
        }
        
        print("🎯 Search complete: \(results.count) raw → \(uniqueBooks.count) unique → \(sortedBooks.count) relevant")
        
        self.isSearching = false
        self.displayBooks = sortedBooks.map { $0.toDomain() }
    }
    
    func searchGenre(genre: String) { resetAndFetch(mode: .genre, query: genre) }
    
    func loadNextPage() {
        guard !isSearching, !isLoadingMore, currentMode != .search else { return }
        isLoadingMore = true
        currentOffset += browseLimit
        var params = "limit=\(browseLimit)&offset=\(currentOffset)"
        switch currentMode {
        case .recent: params += "&since=2024-01-01"
        case .genre: params += "&genre=\(encodeForURL(lastQuery))"
        default: break
        }
        fetchRaw(url: "\(baseURL)?format=json&extended=1&\(params)") { [weak self] books in
            DispatchQueue.main.async {
                self?.isLoadingMore = false
                self?.displayBooks.append(contentsOf: books.map { $0.toDomain() })
            }
        }
    }
    
    private func resetAndFetch(mode: FetchMode, query: String = "") {
        currentMode = mode
        lastQuery = query
        currentOffset = 0
        isSearching = true
        displayBooks = []
        var params = "limit=\(browseLimit)&offset=0"
        switch mode {
        case .recent: params += "&since=2024-01-01"
        case .genre: params += "&genre=\(encodeForURL(query))"
        default: break
        }
        fetchRaw(url: "\(baseURL)?format=json&extended=1&\(params)") { [weak self] books in
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
                completion(response.booksList)
            } catch {
                print("❌ fetchRaw decode error: \(error)")
                completion([])
            }
        }.resume()
    }
    
    /// URL encode a string for query parameters
    /// Preserves ^ which is part of LibriVox API syntax for anchored searches
    private func encodeForURL(_ string: String) -> String {
        // Create a custom character set that includes ^ as allowed
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert("^")  // Don't encode ^ - it's API syntax
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

// MARK: - Views

struct LibriVoxSearchView: View {
    @StateObject private var api = LibriVoxAPI()
    @ObservedObject var bookManager: BookManager
    @ObservedObject var downloadManager = LibriVoxDownloadManager.shared
    var speechPlayer: AudioPlayer?
    let dismiss: () -> Void
    @State private var searchText = ""
    @State private var selectedTab: Tab = .browse
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    enum Tab: String, CaseIterable { case browse = "Browse"; case subjects = "Subjects"; case search = "Search" }
    let subjects = ["Mystery", "Sci-Fi", "Romance", "History", "Children", "Fantasy", "Humor", "Poetry", "Philosophy", "Adventure"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackgroundView()
                VStack(spacing: 0) {
                    GlassSegmentedFilter(selection: $selectedTab, options: Tab.allCases.map { ($0, $0.rawValue) }, color: .royalPurple).padding()
                    if selectedTab == .search { searchView }
                    else if selectedTab == .subjects { subjectsView }
                    else { browseView }
                }
                if showingToast {
                    VStack { Spacer(); GlassToastView(message: toastMessage, icon: "arrow.down.circle.fill", iconColor: .royalPurple).padding(.bottom, 20) }
                        .transition(.move(edge: .bottom).combined(with: .opacity)).animation(.spring(), value: showingToast).zIndex(100)
                }
            }
            .navigationTitle("LibriVox").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { GlassCloseButton(action: dismiss) } }
        }
        .accentColor(.royalPurple)
    }
    
    private var searchView: some View {
        VStack(spacing: 0) {
            GlassSearchBar(text: $searchText, placeholder: "Title, Author, or Keyword...", onCommit: { api.search(query: searchText) }).padding(.horizontal).padding(.bottom)
            bookList
        }
    }
    
    private var browseView: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Popular") { api.loadPopular() }.font(.subheadline.weight(.bold)).foregroundColor(.primary)
                Spacer()
                Button("Recent") { api.loadRecent() }.font(.subheadline).foregroundColor(.secondary)
            }.padding(.horizontal).padding(.bottom, 8)
            bookList
        }
    }
    
    private var subjectsView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                ForEach(subjects, id: \.self) { subject in
                    Button(action: { selectedTab = .search; searchText = subject; api.searchGenre(genre: subject) }) {
                        Text(subject).font(.system(size: 16, weight: .semibold)).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 80)
                            .background(LinearGradient(colors: [.royalPurple.opacity(0.6), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1)).shadow(radius: 4)
                    }
                }
            }.padding()
        }
    }
    
    private var bookList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if api.isSearching { ProgressView("Searching LibriVox...").padding(.top, 50) }
                else if api.displayBooks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical").font(.largeTitle).foregroundColor(.secondary)
                        Text("No audiobooks found").foregroundColor(.secondary)
                        if !searchText.isEmpty {
                            Text("Try different keywords or check spelling")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }.padding(.top, 50)
                } else {
                    // Show result count for searches
                    if !searchText.isEmpty {
                        Text("\(api.displayBooks.count) results for \"\(searchText)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    
                    ForEach(api.displayBooks) { book in
                        NavigationLink(value: book) {
                            GlassMediaListRow(title: book.title, subtitle: book.author, artworkURL: book.coverArtUrl, artworkIcon: "book.fill", artworkColor: .orange, details: book.totalTime)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onAppear { if book.id == api.displayBooks.last?.id { api.loadNextPage() } }
                    }
                    if api.isLoadingMore { ProgressView().padding() }
                }
            }.padding(.horizontal).padding(.bottom, 20)
            .navigationDestination(for: LibriVoxBook.self) { book in
                LibriVoxBookDetailView(book: book, api: api, bookManager: bookManager, showToast: showToast)
            }
        }
        .onAppear { if api.displayBooks.isEmpty { api.loadPopular() } }
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { showingToast = false } }
    }
}

struct LibriVoxBookDetailView: View {
    let book: LibriVoxBook
    @ObservedObject var api: LibriVoxAPI
    @ObservedObject var bookManager: BookManager
    @ObservedObject var downloadManager = LibriVoxDownloadManager.shared
    let showToast: (String) -> Void
    var isDownloadingAll: Bool { downloadManager.downloadingBookId == book.id }
    
    func downloadAll() {
        showToast("Downloading \(book.chapters.count) chapters...")
        for (index, chapter) in book.chapters.enumerated() {
            downloadManager.downloadSingleChapter(chapter: chapter, bookId: book.id, bookTitle: book.title, author: book.author, coverUrl: book.coverArtUrl, description: book.description, index: index, bookManager: bookManager, fullChapterList: book.chapters)
        }
    }
    
    private func playDownloadedChapter(_ chapter: LibriVoxChapter) {
        if let localBook = bookManager.books.first(where: { $0.title == book.title }) {
            if let index = localBook.chapters.firstIndex(where: { $0.title == chapter.title }) {
                NotificationCenter.default.post(name: NSNotification.Name("PlayBookRequest"), object: nil, userInfo: ["book": localBook, "index": index])
            } else { showToast("Chapter not found locally") }
        } else { showToast("Book not found locally") }
    }
    
    var body: some View {
        ZStack {
            GlassBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MediaDetailHeader(title: book.title, subtitle: book.author, tertiaryText: "\(book.chapters.count) chapters • \(book.totalTime)", artworkURL: book.coverArtUrl, artworkIcon: "book.fill", artworkColor: .orange)
                        .padding(.horizontal)
                    GlassActionButton(title: "Download All Chapters", icon: "arrow.down.circle.fill", isLoading: isDownloadingAll, loadingText: "Downloading...", color: .deepResumePurple, isDisabled: book.chapters.isEmpty, action: downloadAll)
                        .padding(.horizontal)
                    if !book.description.isEmpty {
                        ExpandableDescriptionView(text: book.description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression), color: .royalPurple).padding(.horizontal)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        if book.chapters.isEmpty { Text("No chapters available or loading...").foregroundColor(.secondary).padding() }
                        else {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                                    GlassDownloadRow(index: index + 1, title: chapter.title, subtitle: chapter.playtime, isDownloaded: downloadManager.isCompleted(bookId: book.id, chapterId: chapter.id), isDownloading: downloadManager.isDownloading(bookId: book.id, chapterId: chapter.id), color: .royalPurple, onDownload: {
                                        downloadManager.downloadSingleChapter(chapter: chapter, bookId: book.id, bookTitle: book.title, author: book.author, coverUrl: book.coverArtUrl, description: book.description, index: index, bookManager: bookManager, fullChapterList: book.chapters)
                                        showToast("Downloading...")
                                    }, onPlay: { playDownloadedChapter(chapter) })
                                }
                            }.padding(.horizontal)
                        }
                    }
                    Spacer(minLength: 50)
                }.padding(.top)
            }
        }.navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
    }
}
