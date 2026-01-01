//
//  BookManager.swift
//  2 Music 2 Furious - MILESTONE 15
//
//  Shared Models, Download Logic, and Book Management
//  UPDATED: Smart Played Status Tracking for M4B Audiobooks
//    - Auto-marks chapters as played when they naturally end
//    - Tracks resume position per-book (survives app restart)
//    - Bulk mark all played/unplayed
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

// MARK: - Shared Models

struct LibriVoxChapter: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let listenUrl: String
    let playtime: String
    
    var duration: String { playtime }
    
    var formattedDuration: String {
        guard let seconds = Int(playtime), seconds >= 0 else { return playtime }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "section_number"
        case title
        case listenUrl = "listen_url"
        case playtime
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct LibriVoxAuthor: Codable {
    let firstName: String
    let lastName: String
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

struct Book: Identifiable, Codable, Hashable {
    var id = UUID()
    let title: String
    var author: String? = nil
    var description: String? = nil
    var chapters: [Track]
    var librivoxChapters: [LibriVoxChapter]? = nil
    var coverArtUrl: URL? = nil
    var coverArtData: Data? = nil
    var currentChapterIndex: Int = 0
    var lastPlayedPosition: Double = 0
    let dateAdded: Date
    
    var displayTitle: String {
        let cleaned = title
            .replacingOccurrences(of: "_Chapter.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_Ch.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_Part.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
    }
    
    var displayAuthor: String { author ?? "Unknown Author" }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Book, rhs: Book) -> Bool { lhs.id == rhs.id }
}

// MARK: - Download Manager

class LibriVoxDownloadManager: ObservableObject {
    static let shared = LibriVoxDownloadManager()
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadingBookId: String?
    @Published var completedChapters: Set<String> = []
    
    private func compositeId(bookId: String, chapterId: String) -> String { "\(bookId)_\(chapterId)" }
    
    func downloadSingleChapter(chapter: LibriVoxChapter, bookId: String, bookTitle: String, author: String, coverUrl: URL?, description: String?, index: Int, bookManager: BookManager, fullChapterList: [LibriVoxChapter]? = nil) {
        let uniqueId = compositeId(bookId: bookId, chapterId: chapter.id)
        downloadProgress[uniqueId] = 0.0
        
        downloadChapter(chapter: chapter, bookTitle: bookTitle, author: author, index: index) { [weak self] track in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.downloadProgress.removeValue(forKey: uniqueId)
                
                if let track = track {
                    self.completedChapters.insert(uniqueId)
                    if let existingIndex = bookManager.books.firstIndex(where: { $0.title == bookTitle }) {
                        var existingBook = bookManager.books[existingIndex]
                        if !existingBook.chapters.contains(where: { $0.filename == track.filename }) {
                            existingBook.chapters.append(track)
                            existingBook.chapters.sort { $0.filename < $1.filename }
                        }
                        if existingBook.librivoxChapters == nil { existingBook.librivoxChapters = fullChapterList }
                        if existingBook.coverArtUrl == nil { existingBook.coverArtUrl = coverUrl }
                        bookManager.books[existingIndex] = existingBook
                        bookManager.saveBooks()
                    } else {
                        let newBook = Book(title: bookTitle, author: author, description: description, chapters: [track], librivoxChapters: fullChapterList, coverArtUrl: coverUrl, dateAdded: Date())
                        bookManager.addBook(newBook)
                    }
                }
            }
        }
    }
    
    private func downloadChapter(chapter: LibriVoxChapter, bookTitle: String, author: String, index: Int, completion: @escaping (Track?) -> Void) {
        guard let url = URL(string: chapter.listenUrl) else { completion(nil); return }
        URLSession.shared.downloadTask(with: url) { tempURL, _, _ in
            guard let tempURL = tempURL else { completion(nil); return }
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = "\(bookTitle)_Chapter_\(String(format: "%03d", index + 1))_\(chapter.title).mp3"
                .components(separatedBy: CharacterSet(charactersIn: ":/\\?%*|\"<>")).joined(separator: "_")
            let destinationURL = documentsPath.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: destinationURL)
            try? FileManager.default.moveItem(at: tempURL, to: destinationURL)
            completion(Track(title: chapter.title, artist: author, filename: filename))
        }.resume()
    }
    
    func isDownloading(bookId: String, chapterId: String) -> Bool { downloadProgress[compositeId(bookId: bookId, chapterId: chapterId)] != nil }
    func isCompleted(bookId: String, chapterId: String) -> Bool { completedChapters.contains(compositeId(bookId: bookId, chapterId: chapterId)) }
}

// MARK: - Book Manager

class BookManager: ObservableObject {
    static let shared = BookManager()
    @Published var books: [Book] = []
    @Published var isLoaded = false
    @Published var calculatedDurations: [String: String] = [:]
    
    // MARK: - Played Status Tracking
    @Published var playedChapterIDs: Set<String> = []
    
    // MARK: - Active Book Tracking
    @Published var activeBookId: UUID? = nil
    private var lastKnownChapterIndex: Int = -1
    
    // Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    private weak var speechPlayer: AudioPlayer?
    
    private let userDefaults = UserDefaults.standard
    private let booksKey = "savedBooks"
    private let durationsKey = "cachedDurations"
    private let playedChaptersKey = "playedChapters"
    private let activeBookKey = "activeBookId"
    private let calculationQueue = DispatchQueue(label: "durationCalculation", qos: .utility)
    
    init() {
        if let cached = userDefaults.dictionary(forKey: durationsKey) as? [String: String] { calculatedDurations = cached }
    }
    
    func loadIfNeeded() {
        guard !isLoaded else { return }
        if let data = userDefaults.data(forKey: booksKey), let decoded = try? JSONDecoder().decode([Book].self, from: data) { books = decoded }
        
        // Load Played Status
        if let data = userDefaults.data(forKey: playedChaptersKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            playedChapterIDs = decoded
        }
        
        // Restore Active Book ID
        if let idString = userDefaults.string(forKey: activeBookKey),
           let uuid = UUID(uuidString: idString) {
            activeBookId = uuid
            print("📖 Restored active book: \(uuid)")
        }
        
        isLoaded = true
    }
    
    // MARK: - Speech Player Connection
    
    func connectToSpeechPlayer(_ player: AudioPlayer) {
        self.speechPlayer = player
        
        // Observe currentIndex changes
        player.$currentIndex
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newIndex in
                self?.handleChapterIndexChange(to: newIndex)
            }
            .store(in: &cancellables)
        
        // Observe isPlaying to save position on pause
        player.$isPlaying
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self = self, self.activeBookId != nil else { return }
                if !isPlaying {
                    self.saveCurrentPlaybackState()
                }
            }
            .store(in: &cancellables)
        
        // Auto-detect book from restored queue
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.detectActiveBookFromQueue(player)
        }
        
        print("📖 BookManager connected to speech player")
    }
    
    /// Try to detect if the current queue belongs to a book
    private func detectActiveBookFromQueue(_ player: AudioPlayer) {
        loadIfNeeded()
        
        // If we already have an active book set, verify it's still valid
        if let bookId = activeBookId {
            if books.contains(where: { $0.id == bookId }) {
                // Update tracking state
                lastKnownChapterIndex = player.currentIndex
                print("📖 Active book verified: \(bookId), chapter \(player.currentIndex)")
                return
            } else {
                // Book was deleted, clear active
                activeBookId = nil
            }
        }
        
        // Try to find a book that matches the current queue
        guard let currentTrack = player.currentTrack else { return }
        
        for book in books {
            // Check if current track matches any chapter in this book
            if book.chapters.contains(where: { $0.filename == currentTrack.filename }) {
                activeBookId = book.id
                lastKnownChapterIndex = player.currentIndex
                saveActiveBookId()
                print("📖 Auto-detected book: \(book.displayTitle), chapter \(player.currentIndex)")
                return
            }
        }
    }
    
    // MARK: - Book Playback Control
    
    func startPlayingBook(_ book: Book, at chapterIndex: Int) {
        loadIfNeeded()
        
        print("📖 Starting book: \(book.displayTitle), chapter \(chapterIndex)")
        
        activeBookId = book.id
        lastKnownChapterIndex = chapterIndex
        
        // Update book's current chapter
        if let bookIndex = books.firstIndex(where: { $0.id == book.id }) {
            books[bookIndex].currentChapterIndex = chapterIndex
            saveBooks()
        }
        
        saveActiveBookId()
    }
    
    func stopPlayingBook() {
        guard activeBookId != nil else { return }
        
        print("📖 Stopping book tracking")
        saveCurrentPlaybackState()
        
        activeBookId = nil
        lastKnownChapterIndex = -1
        
        saveActiveBookId()
    }
    
    func getResumeInfo(for book: Book) -> (chapterIndex: Int, position: Double) {
        loadIfNeeded()
        
        let chapterIndex = min(book.currentChapterIndex, max(0, book.chapters.count - 1))
        let position = book.lastPlayedPosition
        
        return (chapterIndex, position)
    }
    
    func getFirstUnplayedChapter(for book: Book) -> Int {
        loadIfNeeded()
        
        for (index, track) in book.chapters.enumerated() {
            let chapterId = track.hasChapterBoundaries ? track.id.uuidString : track.filename
            if !playedChapterIDs.contains(chapterId) {
                return index
            }
        }
        return max(0, book.chapters.count - 1)
    }
    
    // MARK: - Chapter Change Handling
    
    private func handleChapterIndexChange(to newIndex: Int) {
        guard let bookId = activeBookId,
              let bookIndex = books.firstIndex(where: { $0.id == bookId }) else {
            // Try to detect book if not set
            if let player = speechPlayer {
                detectActiveBookFromQueue(player)
            }
            return
        }
        
        let book = books[bookIndex]
        let oldIndex = lastKnownChapterIndex
        
        // Skip if not tracking yet or same index
        guard oldIndex >= 0 && newIndex != oldIndex else {
            lastKnownChapterIndex = newIndex
            return
        }
        
        print("📖 Chapter: \(oldIndex) → \(newIndex)")
        
        // If we advanced forward by 1, the previous chapter naturally ended
        // Mark it as played
        if newIndex == oldIndex + 1 && oldIndex >= 0 && oldIndex < book.chapters.count {
            let oldTrack = book.chapters[oldIndex]
            let chapterId = oldTrack.hasChapterBoundaries ? oldTrack.id.uuidString : oldTrack.filename
            
            if !playedChapterIDs.contains(chapterId) {
                playedChapterIDs.insert(chapterId)
                savePlayedStatus()
                print("📖 ✓ Marked chapter \(oldIndex) as played (natural end)")
            }
        }
        
        // Update tracking
        lastKnownChapterIndex = newIndex
        
        // Update book state
        books[bookIndex].currentChapterIndex = newIndex
        books[bookIndex].lastPlayedPosition = 0
        saveBooks()
    }
    
    private func saveCurrentPlaybackState() {
        guard let player = speechPlayer,
              let bookId = activeBookId,
              let bookIndex = books.firstIndex(where: { $0.id == bookId }) else { return }
        
        let position = player.currentTime
        let index = player.currentIndex
        
        books[bookIndex].currentChapterIndex = index
        books[bookIndex].lastPlayedPosition = position
        lastKnownChapterIndex = index
        saveBooks()
        
        print("📖 Saved: chapter \(index), position \(String(format: "%.1f", position))")
    }
    
    private func saveActiveBookId() {
        if let id = activeBookId {
            userDefaults.set(id.uuidString, forKey: activeBookKey)
        } else {
            userDefaults.removeObject(forKey: activeBookKey)
        }
    }
    
    // MARK: - Played Status Logic
    
    func togglePlayed(chapterId: String) {
        if playedChapterIDs.contains(chapterId) {
            playedChapterIDs.remove(chapterId)
        } else {
            playedChapterIDs.insert(chapterId)
        }
        savePlayedStatus()
    }
    
    func isPlayed(chapterId: String) -> Bool {
        return playedChapterIDs.contains(chapterId)
    }
    
    func markChapterPlayed(_ track: Track) {
        let chapterId = track.hasChapterBoundaries ? track.id.uuidString : track.filename
        if !playedChapterIDs.contains(chapterId) {
            playedChapterIDs.insert(chapterId)
            savePlayedStatus()
        }
    }
    
    // MARK: - Bulk Mark Operations
    
    func markAllPlayed(for book: Book) {
        loadIfNeeded()
        for track in book.chapters {
            let chapterId = track.hasChapterBoundaries ? track.id.uuidString : track.filename
            playedChapterIDs.insert(chapterId)
        }
        savePlayedStatus()
    }
    
    func markAllUnplayed(for book: Book) {
        loadIfNeeded()
        for track in book.chapters {
            let chapterId = track.hasChapterBoundaries ? track.id.uuidString : track.filename
            playedChapterIDs.remove(chapterId)
        }
        if let bookIndex = books.firstIndex(where: { $0.id == book.id }) {
            books[bookIndex].currentChapterIndex = 0
            books[bookIndex].lastPlayedPosition = 0
            saveBooks()
        }
        savePlayedStatus()
    }
    
    func playedChapterCount(for book: Book) -> Int {
        var count = 0
        for track in book.chapters {
            let chapterId = track.hasChapterBoundaries ? track.id.uuidString : track.filename
            if playedChapterIDs.contains(chapterId) { count += 1 }
        }
        return count
    }
    
    private func savePlayedStatus() {
        if let encoded = try? JSONEncoder().encode(playedChapterIDs) {
            userDefaults.set(encoded, forKey: playedChaptersKey)
        }
    }
    
    // MARK: - Duration Logic
    
    func getTrackDuration(track: Track) -> String {
        if let cached = calculatedDurations[track.filename] { return cached }
        calculateDurationAsync(for: track)
        return "--:--"
    }
    
    func preloadDurations(for book: Book) {
        for track in book.chapters { if calculatedDurations[track.filename] == nil { calculateDurationAsync(for: track) } }
    }
    
    private func calculateDurationAsync(for track: Track) {
        let filename = track.filename
        calculationQueue.async { [weak self] in
            guard let self = self else { return }
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
            var result = "--:--"
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let asset = AVURLAsset(url: fileURL)
                let duration = asset.duration.seconds
                if duration.isFinite && duration > 0 {
                    let s = max(0, Int(duration))
                    result = s >= 3600 ? String(format: "%d:%02d:%02d", s/3600, (s%3600)/60, s%60) : String(format: "%d:%02d", (s%3600)/60, s%60)
                }
            }
            DispatchQueue.main.async {
                self.calculatedDurations[filename] = result
                self.userDefaults.set(self.calculatedDurations, forKey: self.durationsKey)
            }
        }
    }
    
    // MARK: - Book Processing
    
    func processUploadedTracks(_ tracks: [Track]) -> [Book] {
        var detectedBooks: [Book] = []
        var ungroupedTracks: [Track] = []
        var groupedByBase: [String: [Track]] = [:]
        
        for track in tracks {
            if let baseName = detectBaseName(from: track.filename) {
                groupedByBase[baseName, default: []].append(track)
            } else { ungroupedTracks.append(track) }
        }
        
        for (baseName, chapters) in groupedByBase {
            if chapters.count >= 2 {
                let sorted = chapters.sorted { $0.filename < $1.filename }
                let artData = extractArtwork(from: sorted.first?.filename)
                detectedBooks.append(Book(title: baseName, author: sorted.first?.artist, description: nil, chapters: sorted, coverArtData: artData, dateAdded: Date()))
            } else { ungroupedTracks.append(contentsOf: chapters) }
        }
        
        for track in ungroupedTracks {
            let artData = extractArtwork(from: track.filename)
            detectedBooks.append(Book(title: track.title, author: track.artist, description: nil, chapters: [track], coverArtData: artData, dateAdded: Date()))
        }
        return detectedBooks
    }
    
    private func extractArtwork(from filename: String?) -> Data? {
        guard let filename = filename else { return nil }
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        let asset = AVURLAsset(url: fileURL)
        for item in asset.commonMetadata {
            if item.commonKey == .commonKeyArtwork, let data = item.dataValue { return data }
        }
        return nil
    }
    
    private func detectBaseName(from filename: String) -> String? {
        let name = filename.replacingOccurrences(of: "\\.(mp3|m4a|m4b)$", with: "", options: .regularExpression)
        if let regex = try? NSRegularExpression(pattern: "(.+?)[-_\\s]*(Chapter|Ch|Part|Pt)[-_\\s]*\\d+", options: .caseInsensitive),
           let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
           let range = Range(match.range(at: 1), in: name) {
            return String(name[range]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    
    func addBook(_ book: Book) { loadIfNeeded(); books.append(book); saveBooks() }
    
    func removeBook(_ book: Book) {
        loadIfNeeded()
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for chapter in book.chapters {
            try? fm.removeItem(at: docs.appendingPathComponent(chapter.filename))
            calculatedDurations.removeValue(forKey: chapter.filename)
        }
        for track in book.chapters {
            let chapterId = track.hasChapterBoundaries ? track.id.uuidString : track.filename
            playedChapterIDs.remove(chapterId)
        }
        savePlayedStatus()
        if activeBookId == book.id {
            activeBookId = nil
            saveActiveBookId()
        }
        books.removeAll { $0.id == book.id }
        saveBooks()
    }
    
    func deleteChapterFile(filename: String, from book: Book) {
        loadIfNeeded()
        guard let index = book.chapters.firstIndex(where: { $0.filename == filename }) else { return }
        if let bookIndex = books.firstIndex(where: { $0.id == book.id }) {
            var updatedBook = books[bookIndex]
            try? FileManager.default.removeItem(at: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename))
            updatedBook.chapters.remove(at: index)
            if updatedBook.chapters.isEmpty && (updatedBook.librivoxChapters == nil || updatedBook.librivoxChapters!.isEmpty) {
                removeBook(updatedBook)
            } else {
                books[bookIndex] = updatedBook
                saveBooks()
            }
        }
    }
    
    func saveBooks() {
        if let encoded = try? JSONEncoder().encode(books) { userDefaults.set(encoded, forKey: booksKey) }
    }
}
