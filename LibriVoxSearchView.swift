//
//  LibriVoxSearchView.swift
//  2 Music 2 Furious - MILESTONE 8.8
//
//  Search, browse, and download LibriVox audiobooks
//  Updates: Header edge-to-edge, Fixed Ghost Download Logic via BookID
//

import SwiftUI
import Combine

// MARK: - LibriVox Models (Partial - Chapter/Author in BookManager)

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
    @State private var searchText = ""; @State private var selectedTab: LibriVoxTab = .popular
    @State private var selectedBook: LibriVoxBook?; @State private var showingToast = false; @State private var toastMessage = ""
    enum LibriVoxTab: String, CaseIterable { case popular = "Popular", recent = "Recent", search = "Search" }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search audiobooks...", text: $searchText, onCommit: { selectedTab = .search; api.search(query: searchText) })
                        if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) } }
                    }.padding(10).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12)).padding()
                    Picker("Tab", selection: $selectedTab) { ForEach(LibriVoxTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(SegmentedPickerStyle()).padding(.horizontal).padding(.bottom, 16)
                        .onChange(of: selectedTab) { if $0 == .popular { api.loadPopular() } else if $0 == .recent { api.loadRecent() } }
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if selectedTab == .search && api.displayBooks.isEmpty && !api.isSearching {
                                if searchText.isEmpty { emptyView(icon: "magnifyingglass", text: "Search") } else { emptyView(icon: "book.closed", text: "No results") }
                            } else { bookListView(books: api.displayBooks, isLoading: api.isSearching) }
                        }.padding(.horizontal).padding(.bottom, 20)
                    }
                }
                if showingToast { VStack { Spacer(); LibriVoxToastView(message: toastMessage).padding(.bottom, 20) }.transition(.move(edge: .bottom).combined(with: .opacity)).animation(.spring(), value: showingToast).zIndex(100) }
            }
            .navigationTitle("LibriVox").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(action: { dismiss() }) { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary) } } }
            .sheet(item: $selectedBook) { book in
                LibriVoxBookDetailView(book: book, api: api, bookManager: bookManager, showToast: showToast, dismiss: { selectedBook = nil })
            }
            .onAppear { if api.displayBooks.isEmpty { api.loadPopular() } }
        }
    }
    
    private func bookListView(books: [LibriVoxBook], isLoading: Bool) -> some View {
        Group {
            if isLoading && books.isEmpty { VStack(spacing: 16) { ProgressView(); Text("Loading...").foregroundColor(.secondary) }.padding(.top, 50) } else {
                ForEach(books) { book in
                    LibriVoxBookRow(book: book).onTapGesture { selectedBook = book; api.loadBookDetails(bookId: book.id) }
                        .onAppear { if book.id == books.last?.id { api.loadNextPage() } }
                }
                if api.isLoadingMore { HStack { Spacer(); ProgressView(); Spacer() }.padding() }
            }
        }
    }
    
    private func emptyView(icon: String, text: String) -> some View { VStack(spacing: 16) { Image(systemName: icon).font(.system(size: 40)).foregroundColor(.secondary); Text(text).foregroundColor(.secondary) }.padding(.top, 50) }
    private func showToast(_ message: String) { toastMessage = message; withAnimation { showingToast = true }; DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { showingToast = false } } }
}

struct LibriVoxBookRow: View {
    let book: LibriVoxBook
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                if let url = book.coverArtUrl { AsyncImage(url: url) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.orange.opacity(0.1) } } }
                else { RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1)); Image(systemName: "book.fill").font(.system(size: 24)).foregroundColor(.orange) }
            }.frame(width: 56, height: 56).cornerRadius(12).clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.system(size: 16, weight: .semibold)).foregroundColor(.primary).lineLimit(2)
                Text(book.author).font(.system(size: 14)).foregroundColor(.secondary).lineLimit(1)
                HStack(spacing: 12) { Label("\(book.chapters.count) ch", systemImage: "list.bullet"); Label(book.totalTime, systemImage: "clock") }.font(.caption).foregroundColor(.secondary)
            }
            Spacer(); Image(systemName: "chevron.right").foregroundColor(.secondary.opacity(0.5)).font(.system(size: 14, weight: .semibold))
        }
        .padding(16).background(.ultraThinMaterial).cornerRadius(20).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.2), lineWidth: 1)).shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

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
                LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Edge-to-Edge Header
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                if let url = displayBook.coverArtUrl { AsyncImage(url: url) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.orange.opacity(0.1); ProgressView() } } }
                                else { Color.orange.opacity(0.1); Image(systemName: "book.fill").font(.system(size: 40)).foregroundColor(.orange) }
                            }.frame(width: 100, height: 100).cornerRadius(20).shadow(radius: 5)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(displayBook.title).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                                Text(displayBook.author).font(.subheadline).foregroundColor(.secondary)
                                HStack(spacing: 12) { Label("\(displayBook.chapters.count) chapters", systemImage: "list.bullet"); Label(displayBook.totalTime, systemImage: "clock") }.font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity) // FORCE FULL WIDTH
                        .background(.ultraThinMaterial)
                        // .cornerRadius(24) // REMOVE ROUNDED CORNERS FOR FULL EDGE-TO-EDGE LOOK OR KEEP IF DESIRED. Keeping generic structure but removing side padding constraints
                        
                        Button(action: downloadAll) {
                            HStack {
                                if isDownloadingAll { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)); Text("Downloading...") }
                                else { Image(systemName: "arrow.down.circle.fill"); Text("Download All Chapters") }
                            }.font(.system(size: 16, weight: .semibold)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16).background(isDownloadingAll ? Color.gray : Color.blue).cornerRadius(16).shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }.disabled(isDownloadingAll || displayBook.chapters.isEmpty).padding(.horizontal)
                        
                        if !displayBook.description.isEmpty {
                            DescriptionView(text: displayBook.description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                                .padding(.horizontal)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            if api.isLoadingChapters { HStack { Spacer(); ProgressView("Loading chapters..."); Spacer() }.padding() }
                            else {
                                LazyVStack(spacing: 8) {
                                    ForEach(Array(displayBook.chapters.enumerated()), id: \.element.id) { index, chapter in
                                        ChapterRow(chapter: chapter, index: index, bookId: displayBook.id, bookTitle: displayBook.title, author: displayBook.author, coverUrl: displayBook.coverArtUrl, description: displayBook.description, bookManager: bookManager, showToast: showToast, fullChapterList: displayBook.chapters)
                                    }
                                }.padding(.horizontal)
                            }
                        }
                        Spacer(minLength: 50)
                    }.padding(.top)
                }
            }
            .navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(action: { dismiss() }) { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary) } } }
        }
    }
}

struct DescriptionView: View {
    let text: String; @State private var isExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description").font(.headline)
            Text(text).font(.system(size: 15)).foregroundColor(.secondary).lineLimit(isExpanded ? nil : 4).animation(.spring(), value: isExpanded)
            Button(action: { withAnimation { isExpanded.toggle() } }) { Text(isExpanded ? "Show Less" : "Show More").font(.caption.weight(.bold)).foregroundColor(.blue) }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial).cornerRadius(16).onTapGesture { withAnimation { isExpanded.toggle() } }
    }
}

struct ChapterRow: View {
    let chapter: LibriVoxChapter; let index: Int
    let bookId: String; let bookTitle: String; let author: String; let coverUrl: URL?; let description: String?
    @ObservedObject var downloadManager = LibriVoxDownloadManager.shared
    @ObservedObject var bookManager: BookManager
    let showToast: (String) -> Void
    let fullChapterList: [LibriVoxChapter]
    
    // FIX: Unique ID Check
    var isDownloading: Bool { downloadManager.isDownloading(bookId: bookId, chapterId: chapter.id) }
    var isCompleted: Bool { downloadManager.isCompleted(bookId: bookId, chapterId: chapter.id) }
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)").font(.system(size: 14, weight: .bold)).foregroundColor(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title).font(.system(size: 15)).foregroundColor(.primary).lineLimit(1)
                Text(chapter.formattedDuration).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isCompleted { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 20)) }
            else if isDownloading { ProgressView().scaleEffect(0.8) }
            else {
                Button(action: {
                    downloadManager.downloadSingleChapter(chapter: chapter, bookId: bookId, bookTitle: bookTitle, author: author, coverUrl: coverUrl, description: description, index: index, bookManager: bookManager, fullChapterList: fullChapterList)
                    showToast("Downloading \(chapter.title)...")
                }) { Image(systemName: "arrow.down.circle").foregroundColor(.blue).font(.system(size: 22)) }.buttonStyle(BorderlessButtonStyle())
            }
        }.padding(12).background(.ultraThinMaterial).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
    }
}

struct LibriVoxToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) { Image(systemName: "arrow.down.circle.fill").foregroundColor(.blue); Text(message).font(.subheadline.weight(.medium)) }
            .padding(.horizontal, 20).padding(.vertical, 12).background(.thinMaterial).clipShape(Capsule()).shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}
