//
//  LibriVoxSearchView.swift
//  2 Music 2 Furious - MILESTONE 7.3
//
//  Search, browse, and download LibriVox audiobooks
//  Downloads auto-group into Books library
//

import SwiftUI
import Combine

// MARK: - LibriVox Models

struct LibriVoxBook: Identifiable, Codable {
    let id: String
    let title: String
    let author: String
    let description: String
    let totalTime: String
    let language: String
    let chapters: [LibriVoxChapter]
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case author = "authors"
        case description
        case totalTime = "totaltimesecs"
        case language
        case chapters = "sections"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "English"
        
        // Author can be array or single object
        if let authorsArray = try? container.decode([LibriVoxAuthor].self, forKey: .author) {
            author = authorsArray.first.map { "\($0.firstName) \($0.lastName)" } ?? "Unknown"
        } else if let singleAuthor = try? container.decode(LibriVoxAuthor.self, forKey: .author) {
            author = "\(singleAuthor.firstName) \(singleAuthor.lastName)"
        } else {
            author = "Unknown"
        }
        
        // Total time
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
    
    init(id: String, title: String, author: String, description: String, totalTime: String, language: String, chapters: [LibriVoxChapter]) {
        self.id = id
        self.title = title
        self.author = author
        self.description = description
        self.totalTime = totalTime
        self.language = language
        self.chapters = chapters
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
    @Published var searchResults: [LibriVoxBook] = []
    @Published var popularBooks: [LibriVoxBook] = []
    @Published var recentBooks: [LibriVoxBook] = []
    @Published var isSearching = false
    @Published var isLoadingPopular = false
    @Published var isLoadingRecent = false
    @Published var selectedBook: LibriVoxBook?
    @Published var isLoadingChapters = false
    
    private let baseURL = "https://librivox.org/api/feed/audiobooks"
    
    // MARK: - Search
    
    func search(query: String) {
        guard !query.isEmpty else { return }
        isSearching = true
        
        let urlString = "\(baseURL)?title=^\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&format=json&extended=1"
        
        fetch(urlString: urlString) { [weak self] (result: Result<LibriVoxSearchResponse, Error>) in
            DispatchQueue.main.async {
                self?.isSearching = false
                switch result {
                case .success(let response):
                    self?.searchResults = response.books
                case .failure(let error):
                    print("Search error: \(error)")
                    self?.searchResults = []
                }
            }
        }
    }
    
    // MARK: - Popular Books
    
    func loadPopular() {
        guard popularBooks.isEmpty else { return }
        isLoadingPopular = true
        
        // LibriVox doesn't have a "popular" endpoint, so we get well-known titles
        let urlString = "\(baseURL)?format=json&extended=1&limit=20"
        
        fetch(urlString: urlString) { [weak self] (result: Result<LibriVoxSearchResponse, Error>) in
            DispatchQueue.main.async {
                self?.isLoadingPopular = false
                switch result {
                case .success(let response):
                    self?.popularBooks = response.books
                case .failure(let error):
                    print("Popular error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Recent Books
    
    func loadRecent() {
        guard recentBooks.isEmpty else { return }
        isLoadingRecent = true
        
        let urlString = "\(baseURL)?format=json&extended=1&limit=20&since=2024-01-01"
        
        fetch(urlString: urlString) { [weak self] (result: Result<LibriVoxSearchResponse, Error>) in
            DispatchQueue.main.async {
                self?.isLoadingRecent = false
                switch result {
                case .success(let response):
                    self?.recentBooks = response.books
                case .failure(let error):
                    print("Recent error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Load Book Details (with chapters)
    
    func loadBookDetails(bookId: String) {
        isLoadingChapters = true
        
        let urlString = "\(baseURL)?id=\(bookId)&format=json&extended=1"
        
        fetch(urlString: urlString) { [weak self] (result: Result<LibriVoxSearchResponse, Error>) in
            DispatchQueue.main.async {
                self?.isLoadingChapters = false
                switch result {
                case .success(let response):
                    if let book = response.books.first {
                        self?.selectedBook = book
                    }
                case .failure(let error):
                    print("Book details error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Generic Fetch
    
    private func fetch<T: Codable>(urlString: String, completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: 0)))
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                print("Decode error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Download Manager for LibriVox

class LibriVoxDownloadManager: ObservableObject {
    @Published var downloadProgress: [String: Double] = [:] // chapterId -> progress
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
            
            // Sort tracks by index and create book
            let sortedTracks = downloadedTracks.sorted { t1, t2 in
                // Extract chapter number from filename
                let num1 = self?.extractChapterNumber(from: t1.filename) ?? 0
                let num2 = self?.extractChapterNumber(from: t2.filename) ?? 0
                return num1 < num2
            }
            
            if !sortedTracks.isEmpty {
                let newBook = Book(
                    title: book.title,
                    chapters: sortedTracks,
                    dateAdded: Date()
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
                    
                    // Check if book already exists
                    if let existingIndex = bookManager.books.firstIndex(where: { $0.title == book.title }) {
                        // Add chapter to existing book
                        var existingBook = bookManager.books[existingIndex]
                        existingBook.chapters.append(track)
                        existingBook.chapters.sort { t1, t2 in
                            let num1 = self?.extractChapterNumber(from: t1.filename) ?? 0
                            let num2 = self?.extractChapterNumber(from: t2.filename) ?? 0
                            return num1 < num2
                        }
                        bookManager.books[existingIndex] = existingBook
                    } else {
                        // Create new book with single chapter
                        let newBook = Book(
                            title: book.title,
                            chapters: [track],
                            dateAdded: Date()
                        )
                        bookManager.addBook(newBook)
                    }
                }
            }
        }
    }
    
    private func downloadChapter(chapter: LibriVoxChapter, book: LibriVoxBook, index: Int, completion: @escaping (Track?) -> Void) {
        guard let url = URL(string: chapter.listenUrl) else {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let tempURL = tempURL, error == nil else {
                print("Download error: \(error?.localizedDescription ?? "Unknown")")
                completion(nil)
                return
            }
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = self?.sanitizeFilename("\(book.title)_Chapter_\(String(format: "%03d", index + 1))_\(chapter.title).mp3") ?? "chapter.mp3"
            let destinationURL = documentsPath.appendingPathComponent(filename)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                
                let track = Track(
                    title: chapter.title,
                    artist: book.author,
                    filename: filename
                )
                completion(track)
            } catch {
                print("File error: \(error)")
                completion(nil)
            }
        }
        task.resume()
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
    
    private func extractChapterNumber(from filename: String) -> Int {
        // Look for _Chapter_XXX_ pattern
        if let range = filename.range(of: "_Chapter_\\d{3}_", options: .regularExpression) {
            let numberStr = filename[range].replacingOccurrences(of: "_Chapter_", with: "").replacingOccurrences(of: "_", with: "")
            return Int(numberStr) ?? 0
        }
        return 0
    }
    
    func isDownloading(chapterId: String) -> Bool {
        downloadProgress[chapterId] != nil
    }
    
    func isCompleted(chapterId: String) -> Bool {
        completedChapters.contains(chapterId)
    }
}

// MARK: - Main LibriVox Search View

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
        case popular = "Popular"
        case recent = "Recent"
        case search = "Search"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search audiobooks...", text: $searchText, onCommit: {
                            selectedTab = .search
                            api.search(query: searchText)
                        })
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding()
                    
                    // Tab picker
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(LibriVoxTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    // Content
                    switch selectedTab {
                    case .popular:
                        bookListView(books: api.popularBooks, isLoading: api.isLoadingPopular)
                            .onAppear { api.loadPopular() }
                    case .recent:
                        bookListView(books: api.recentBooks, isLoading: api.isLoadingRecent)
                            .onAppear { api.loadRecent() }
                    case .search:
                        if api.isSearching {
                            Spacer()
                            ProgressView("Searching...")
                            Spacer()
                        } else if api.searchResults.isEmpty && !searchText.isEmpty {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No results found")
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        } else if searchText.isEmpty {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("Search for audiobooks")
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        } else {
                            bookListView(books: api.searchResults, isLoading: false)
                        }
                    }
                }
                
                // Toast
                if showingToast {
                    VStack {
                        Spacer()
                        LibriVoxToastView(message: toastMessage)
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: showingToast)
                }
            }
            .navigationTitle("LibriVox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedBook) { book in
                BookDetailView(
                    book: book,
                    api: api,
                    downloadManager: downloadManager,
                    bookManager: bookManager,
                    showToast: showToast,
                    dismiss: { selectedBook = nil }
                )
            }
        }
    }
    
    private func bookListView(books: [LibriVoxBook], isLoading: Bool) -> some View {
        Group {
            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if books.isEmpty {
                Spacer()
                Text("No books available")
                    .foregroundColor(.gray)
                Spacer()
            } else {
                List(books) { book in
                    LibriVoxBookRow(book: book)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedBook = book
                            api.loadBookDetails(bookId: book.id)
                        }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation {
            showingToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showingToast = false
            }
        }
    }
}

// MARK: - Book Row

struct LibriVoxBookRow: View {
    let book: LibriVoxBook
    
    var body: some View {
        HStack(spacing: 12) {
            // Book icon
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "book.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 20))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(2)
                
                Text(book.author)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label("\(book.chapters.count) ch", systemImage: "list.bullet")
                    Label(book.totalTime, systemImage: "clock")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Book Detail View

struct BookDetailView: View {
    let book: LibriVoxBook
    @ObservedObject var api: LibriVoxAPI
    @ObservedObject var downloadManager: LibriVoxDownloadManager
    @ObservedObject var bookManager: BookManager
    let showToast: (String) -> Void
    let dismiss: () -> Void
    
    @State private var showChapters = false
    
    var displayBook: LibriVoxBook {
        api.selectedBook ?? book
    }
    
    var isDownloadingAll: Bool {
        downloadManager.downloadingBookId == book.id
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Book header
                    HStack(alignment: .top, spacing: 16) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "book.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 40))
                            )
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(displayBook.title)
                                .font(.headline)
                            
                            Text(displayBook.author)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                Label("\(displayBook.chapters.count) chapters", systemImage: "list.bullet")
                                Label(displayBook.totalTime, systemImage: "clock")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    
                    // Download All button
                    Button(action: {
                        if !isDownloadingAll && displayBook.chapters.count > 0 {
                            downloadManager.downloadAllChapters(book: displayBook, bookManager: bookManager)
                            showToast("Downloading \(displayBook.chapters.count) chapters...")
                        }
                    }) {
                        HStack {
                            if isDownloadingAll {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Downloading...")
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download All Chapters")
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isDownloadingAll ? Color.gray : Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(isDownloadingAll || displayBook.chapters.isEmpty)
                    .padding(.horizontal)
                    
                    // Description
                    if !displayBook.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            Text(displayBook.description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineLimit(4)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Chapters section
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { withAnimation { showChapters.toggle() } }) {
                            HStack {
                                Text("Chapters")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: showChapters ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                        
                        if api.isLoadingChapters {
                            HStack {
                                Spacer()
                                ProgressView("Loading chapters...")
                                Spacer()
                            }
                            .padding()
                        } else if showChapters {
                            ForEach(Array(displayBook.chapters.enumerated()), id: \.element.id) { index, chapter in
                                ChapterRow(
                                    chapter: chapter,
                                    index: index,
                                    book: displayBook,
                                    downloadManager: downloadManager,
                                    bookManager: bookManager,
                                    showToast: showToast
                                )
                            }
                        }
                    }
                    
                    Spacer(minLength: 50)
                }
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Chapter Row

struct ChapterRow: View {
    let chapter: LibriVoxChapter
    let index: Int
    let book: LibriVoxBook
    @ObservedObject var downloadManager: LibriVoxDownloadManager
    @ObservedObject var bookManager: BookManager
    let showToast: (String) -> Void
    
    var isDownloading: Bool {
        downloadManager.isDownloading(chapterId: chapter.id)
    }
    
    var isCompleted: Bool {
        downloadManager.isCompleted(chapterId: chapter.id)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Text(chapter.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isDownloading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(action: {
                    downloadManager.downloadSingleChapter(chapter: chapter, book: book, index: index, bookManager: bookManager)
                    showToast("Downloading \(chapter.title)...")
                }) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.blue)
                        .font(.system(size: 22))
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Toast View

struct LibriVoxToastView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.blue)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
    }
}

// Make LibriVoxBook work with sheet(item:)
extension LibriVoxBook: Equatable {
    static func == (lhs: LibriVoxBook, rhs: LibriVoxBook) -> Bool {
        lhs.id == rhs.id
    }
}
