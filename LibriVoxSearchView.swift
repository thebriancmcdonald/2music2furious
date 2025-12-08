//
//  LibriVoxSearchView.swift
//  2 Music 2 Furious - MILESTONE 8.0
//
//  Search, browse, and download LibriVox audiobooks
//  Style: Apple Glass, Expandable Description, Filter Bar
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
        case id
        case title
        case author = "authors"
        case description
        case totalTime = "totaltimesecs"
        case language
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
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            totalTime = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        } else if let secondsString = try? container.decode(String.self, forKey: .totalTime),
                  let seconds = Int(secondsString) {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            totalTime = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        } else {
            totalTime = "Unknown"
        }
        
        chapters = try container.decodeIfPresent([LibriVoxChapter].self, forKey: .chapters) ?? []
    }
    
    init(id: String, title: String, author: String, description: String, totalTime: String, language: String, chapters: [LibriVoxChapter], archiveUrl: String? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.description = description
        self.totalTime = totalTime
        self.language = language
        self.chapters = chapters
        self.archiveUrl = archiveUrl
    }
    
    static func == (lhs: LibriVoxBook, rhs: LibriVoxBook) -> Bool {
        lhs.id == rhs.id
    }
}

struct LibriVoxAuthor: Codable {
    let firstName: String
    let lastName: String
    
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

struct LibriVoxChapter: Identifiable, Codable {
    let id: String
    let title: String
    let listenUrl: String
    let playtime: String
    
    var duration: String {
        playtime
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "section_number"
        case title
        case listenUrl = "listen_url"
        case playtime
    }
}

struct LibriVoxSearchResponse: Codable {
    let books: [LibriVoxBook]
}

// MARK: - LibriVox API Manager

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
    
    enum FetchMode {
        case popular, recent, search
    }
    
    func search(query: String) {
        guard !query.isEmpty else { return }
        resetPagination(mode: .search)
        lastQuery = query
        isSearching = true
        fetchBooks(query: query)
    }
    
    func loadPopular() {
        if currentMode != .popular || displayBooks.isEmpty {
            resetPagination(mode: .popular)
            isSearching = true
            fetchBooks()
        }
    }
    
    func loadRecent() {
        if currentMode != .recent || displayBooks.isEmpty {
            resetPagination(mode: .recent)
            isSearching = true
            fetchBooks()
        }
    }
    
    func loadNextPage() {
        guard !isLoadingMore && !isSearching && hasMoreResults else { return }
        isLoadingMore = true
        currentOffset += limit
        fetchBooks(query: lastQuery, isPagination: true)
    }
    
    private func resetPagination(mode: FetchMode) {
        currentMode = mode
        currentOffset = 0
        hasMoreResults = true
        displayBooks = []
    }
    
    private func fetchBooks(query: String = "", isPagination: Bool = false) {
        var urlString = "\(baseURL)?format=json&extended=1&limit=\(limit)&offset=\(currentOffset)"
        switch currentMode {
        case .recent: urlString += "&since=2024-01-01"
        case .search: urlString += "&title=^\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        default: break
        }
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSearching = false
                self.isLoadingMore = false
                
                if let data = data, let response = try? JSONDecoder().decode(LibriVoxSearchResponse.self, from: data) {
                    let newBooks = response.books
                    if newBooks.count < self.limit { self.hasMoreResults = false }
                    
                    if isPagination {
                        self.displayBooks.append(contentsOf: newBooks)
                    } else {
                        self.displayBooks = newBooks
                    }
                } else {
                    if !isPagination { self.displayBooks = [] }
                    self.hasMoreResults = false
                }
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

// MARK: - Download Manager

class LibriVoxDownloadManager: ObservableObject {
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadingBookId: String?
    @Published var completedChapters: Set<String> = []
    
    func downloadAllChapters(book: LibriVoxBook, bookManager: BookManager) {
        downloadingBookId = book.id
        let dispatchGroup = DispatchGroup()
        var downloadedTracks: [Track] = []
        
        for (index, chapter) in book.chapters.enumerated() {
            dispatchGroup.enter()
            downloadProgress[chapter.id] = 0.0
            
            downloadChapter(chapter: chapter, book: book, index: index) { [weak self] track in
                DispatchQueue.main.async {
                    if let track = track {
                        downloadedTracks.append(track)
                        self?.completedChapters.insert(chapter.id)
                    }
                    self?.downloadProgress.removeValue(forKey: chapter.id)
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            self?.downloadingBookId = nil
            let sortedTracks = downloadedTracks.sorted { t1, t2 in
                let num1 = self?.extractChapterNumber(from: t1.filename) ?? 0
                let num2 = self?.extractChapterNumber(from: t2.filename) ?? 0
                return num1 < num2
            }
            if !sortedTracks.isEmpty {
                let newBook = Book(
                    title: book.title,
                    author: book.author,
                    description: book.description, // Pass description
                    chapters: sortedTracks,
                    dateAdded: Date(),
                    coverArtUrl: book.coverArtUrl
                )
                bookManager.addBook(newBook)
            }
        }
    }
    
    func downloadSingleChapter(chapter: LibriVoxChapter, book: LibriVoxBook, index: Int, bookManager: BookManager) {
        downloadProgress[chapter.id] = 0.0
        
        downloadChapter(chapter: chapter, book: book, index: index) { [weak self] track in
            DispatchQueue.main.async {
                self?.downloadProgress.removeValue(forKey: chapter.id)
                if let track = track {
                    self?.completedChapters.insert(chapter.id)
                    
                    if let existingIndex = bookManager.books.firstIndex(where: { $0.title == book.title }) {
                        var existingBook = bookManager.books[existingIndex]
                        existingBook.chapters.append(track)
                        existingBook.chapters.sort { t1, t2 in
                            let num1 = self?.extractChapterNumber(from: t1.filename) ?? 0
                            let num2 = self?.extractChapterNumber(from: t2.filename) ?? 0
                            return num1 < num2
                        }
                        if existingBook.description == nil { existingBook.description = book.description }
                        if existingBook.author == nil { existingBook.author = book.author }
                        if existingBook.coverArtUrl == nil { existingBook.coverArtUrl = book.coverArtUrl }
                        bookManager.books[existingIndex] = existingBook
                    } else {
                        let newBook = Book(
                            title: book.title,
                            author: book.author,
                            description: book.description,
                            chapters: [track],
                            dateAdded: Date(),
                            coverArtUrl: book.coverArtUrl
                        )
                        bookManager.addBook(newBook)
                    }
                }
            }
        }
    }
    
    private func downloadChapter(chapter: LibriVoxChapter, book: LibriVoxBook, index: Int, completion: @escaping (Track?) -> Void) {
        guard let url = URL(string: chapter.listenUrl) else { completion(nil); return }
        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, _ in
            guard let tempURL = tempURL else { completion(nil); return }
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = self?.sanitizeFilename("\(book.title)_Chapter_\(String(format: "%03d", index + 1))_\(chapter.title).mp3") ?? "chapter.mp3"
            let destinationURL = documentsPath.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: destinationURL)
            try? FileManager.default.moveItem(at: tempURL, to: destinationURL)
            let track = Track(title: chapter.title, artist: book.author, filename: filename)
            completion(track)
        }.resume()
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
    
    private func extractChapterNumber(from filename: String) -> Int {
        if let range = filename.range(of: "_Chapter_\\d{3}_", options: .regularExpression) {
            let numberStr = filename[range].replacingOccurrences(of: "_Chapter_", with: "").replacingOccurrences(of: "_", with: "")
            return Int(numberStr) ?? 0
        }
        return 0
    }
    
    func isDownloading(chapterId: String) -> Bool { downloadProgress[chapterId] != nil }
    func isCompleted(chapterId: String) -> Bool { completedChapters.contains(chapterId) }
}

// MARK: - Main View

struct LibriVoxSearchView: View {
    @StateObject private var api = LibriVoxAPI()
    @StateObject private var downloadManager = LibriVoxDownloadManager()
    @ObservedObject var bookManager: BookManager
    let dismiss: () -> Void
    
    @State private var searchText = ""
    @State private var selectedTab: LibriVoxTab = .popular
    @State private var selectedBook: LibriVoxBook?
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    enum LibriVoxTab: String, CaseIterable {
        case popular = "Popular", recent = "Recent", search = "Search"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search audiobooks...", text: $searchText, onCommit: { selectedTab = .search; api.search(query: searchText) })
                        if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) } }
                    }
                    .padding(10).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12)).padding()
                    
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(LibriVoxTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(SegmentedPickerStyle()).padding(.horizontal).padding(.bottom, 16)
                    .onChange(of: selectedTab) { newTab in
                        if newTab == .popular { api.loadPopular() } else if newTab == .recent { api.loadRecent() }
                    }
                    
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if selectedTab == .search && api.displayBooks.isEmpty && !api.isSearching {
                                if searchText.isEmpty { emptyView(icon: "magnifyingglass", text: "Search for audiobooks") }
                                else { emptyView(icon: "book.closed", text: "No results found") }
                            } else {
                                bookListView(books: api.displayBooks, isLoading: api.isSearching)
                            }
                        }
                        .padding(.horizontal).padding(.bottom, 20)
                    }
                }
                
                if showingToast {
                    VStack { Spacer(); LibriVoxToastView(message: toastMessage).padding(.bottom, 20) }
                        .transition(.move(edge: .bottom).combined(with: .opacity)).animation(.spring(), value: showingToast).zIndex(100)
                }
            }
            .navigationTitle("LibriVox").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(action: { dismiss() }) { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary) } } }
            .sheet(item: $selectedBook) { book in
                LibriVoxBookDetailView(book: book, api: api, downloadManager: downloadManager, bookManager: bookManager, showToast: showToast, dismiss: { selectedBook = nil })
            }
            .onAppear { if api.displayBooks.isEmpty { api.loadPopular() } }
        }
    }
    
    private func bookListView(books: [LibriVoxBook], isLoading: Bool) -> some View {
        Group {
            if isLoading && books.isEmpty {
                VStack(spacing: 16) { ProgressView(); Text("Loading...").foregroundColor(.secondary) }.padding(.top, 50)
            } else {
                ForEach(books) { book in
                    LibriVoxBookRow(book: book).onTapGesture { selectedBook = book; api.loadBookDetails(bookId: book.id) }
                        .onAppear { if book.id == books.last?.id { api.loadNextPage() } }
                }
                if api.isLoadingMore { HStack { Spacer(); ProgressView(); Spacer() }.padding() }
            }
        }
    }
    
    private func emptyView(icon: String, text: String) -> some View {
        VStack(spacing: 16) { Image(systemName: icon).font(.system(size: 40)).foregroundColor(.secondary); Text(text).foregroundColor(.secondary) }.padding(.top, 50)
    }
    
    private func showToast(_ message: String) {
        toastMessage = message; withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { showingToast = false } }
    }
}

// MARK: - Reusable Components

struct LibriVoxBookRow: View {
    let book: LibriVoxBook
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                if let url = book.coverArtUrl { AsyncImage(url: url) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.orange.opacity(0.1) } } }
                else { RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1)); Image(systemName: "book.fill").font(.system(size: 24)).foregroundColor(.orange) }
            }
            .frame(width: 56, height: 56).cornerRadius(12).clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.system(size: 16, weight: .semibold)).foregroundColor(.primary).lineLimit(2)
                Text(book.author).font(.system(size: 14)).foregroundColor(.secondary).lineLimit(1)
                HStack(spacing: 12) { Label("\(book.chapters.count) ch", systemImage: "list.bullet"); Label(book.totalTime, systemImage: "clock") }.font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary.opacity(0.5)).font(.system(size: 14, weight: .semibold))
        }
        .padding(16).background(.ultraThinMaterial).cornerRadius(20).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.2), lineWidth: 1)).shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Detail View

struct LibriVoxBookDetailView: View {
    let book: LibriVoxBook
    @ObservedObject var api: LibriVoxAPI
    @ObservedObject var downloadManager: LibriVoxDownloadManager
    @ObservedObject var bookManager: BookManager
    let showToast: (String) -> Void
    let dismiss: () -> Void
    
    @State private var filter: FilterOption = .all
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case downloaded = "Downloaded"
    }
    
    var displayBook: LibriVoxBook { api.selectedBook ?? book }
    var isDownloadingAll: Bool { downloadManager.downloadingBookId == book.id }
    
    var filteredChapters: [(Int, LibriVoxChapter)] {
        let all = Array(displayBook.chapters.enumerated())
        if filter == .downloaded {
            return all.filter { downloadManager.isCompleted(chapterId: $0.element.id) }
        }
        return all
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                if let url = displayBook.coverArtUrl { AsyncImage(url: url) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.orange.opacity(0.1); ProgressView() } } }
                                else { Color.orange.opacity(0.1); Image(systemName: "book.fill").font(.system(size: 40)).foregroundColor(.orange) }
                            }
                            .frame(width: 100, height: 100).cornerRadius(20).shadow(radius: 5)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(displayBook.title).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                                Text(displayBook.author).font(.subheadline).foregroundColor(.secondary)
                                HStack(spacing: 12) { Label("\(displayBook.chapters.count) chapters", systemImage: "list.bullet"); Label(displayBook.totalTime, systemImage: "clock") }.font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding().background(.ultraThinMaterial).cornerRadius(24).padding(.horizontal)
                        
                        // Download All Button
                        Button(action: { if !isDownloadingAll && displayBook.chapters.count > 0 { downloadManager.downloadAllChapters(book: displayBook, bookManager: bookManager); showToast("Downloading \(displayBook.chapters.count) chapters...") } }) {
                            HStack {
                                if isDownloadingAll { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)); Text("Downloading...") }
                                else { Image(systemName: "arrow.down.circle.fill"); Text("Download All Chapters") }
                            }
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16).background(isDownloadingAll ? Color.gray : Color.blue).cornerRadius(16).shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .disabled(isDownloadingAll || displayBook.chapters.isEmpty).padding(.horizontal)
                        
                        // Description (Expandable)
                        if !displayBook.description.isEmpty {
                            DescriptionView(text: displayBook.description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                                .padding(.horizontal)
                        }
                        
                        // Filter Bar (All / Downloaded)
                        Picker("Filter", selection: $filter) {
                            ForEach(FilterOption.allCases, id: \.self) { option in Text(option.rawValue).tag(option) }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        
                        // Chapters List
                        VStack(alignment: .leading, spacing: 12) {
                            if api.isLoadingChapters { HStack { Spacer(); ProgressView("Loading chapters..."); Spacer() }.padding() }
                            else {
                                LazyVStack(spacing: 8) {
                                    ForEach(filteredChapters, id: \.1.id) { index, chapter in
                                        ChapterRow(chapter: chapter, index: index, book: displayBook, downloadManager: downloadManager, bookManager: bookManager, showToast: showToast)
                                    }
                                    if filteredChapters.isEmpty && filter == .downloaded {
                                        Text("No chapters downloaded yet").font(.subheadline).foregroundColor(.secondary).padding()
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
            .navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(action: { dismiss() }) { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary) } } }
        }
    }
}

// MARK: - Reusable Expandable Description

struct DescriptionView: View {
    let text: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 4)
                .animation(.spring(), value: isExpanded)
            
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                Text(isExpanded ? "Show Less" : "Show More")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .onTapGesture { withAnimation { isExpanded.toggle() } }
    }
}

struct ChapterRow: View {
    let chapter: LibriVoxChapter; let index: Int; let book: LibriVoxBook
    @ObservedObject var downloadManager: LibriVoxDownloadManager
    @ObservedObject var bookManager: BookManager
    let showToast: (String) -> Void
    var isDownloading: Bool { downloadManager.isDownloading(chapterId: chapter.id) }
    var isCompleted: Bool { downloadManager.isCompleted(chapterId: chapter.id) }
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)").font(.system(size: 14, weight: .bold)).foregroundColor(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title).font(.system(size: 15)).foregroundColor(.primary).lineLimit(1)
                Text(chapter.duration).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isCompleted { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 20)) }
            else if isDownloading { ProgressView().scaleEffect(0.8) }
            else {
                Button(action: { downloadManager.downloadSingleChapter(chapter: chapter, book: book, index: index, bookManager: bookManager); showToast("Downloading \(chapter.title)...") }) {
                    Image(systemName: "arrow.down.circle").foregroundColor(.blue).font(.system(size: 22))
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(12).background(.ultraThinMaterial).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
    }
}

struct LibriVoxToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) { Image(systemName: "arrow.down.circle.fill").foregroundColor(.blue); Text(message).font(.subheadline.weight(.medium)) }
            .padding(.horizontal, 20).padding(.vertical, 12).background(.thinMaterial).clipShape(Capsule()).shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}
