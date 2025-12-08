//
//  BookManager.swift
//  2 Music 2 Furious - MILESTONE 8.8
//
//  Shared Models, Download Logic, and Book Management
//  FIX: Unique IDs for downloads (Ghost glitch), Duration Helper
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

// MARK: - Shared Models

struct LibriVoxChapter: Identifiable, Codable {
    let id: String
    let title: String
    let listenUrl: String
    let playtime: String
    
    var duration: String { playtime }
    
    var formattedDuration: String {
        guard let seconds = Int(playtime) else { return playtime }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "section_number"
        case title
        case listenUrl = "listen_url"
        case playtime
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

struct Book: Identifiable, Codable {
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
}

// MARK: - Download Manager (Shared)

class LibriVoxDownloadManager: ObservableObject {
    static let shared = LibriVoxDownloadManager()
    
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadingBookId: String?
    @Published var completedChapters: Set<String> = [] // Stores "BookID_ChapterID"
    
    // Helper to generate unique ID
    private func compositeId(bookId: String, chapterId: String) -> String {
        return "\(bookId)_\(chapterId)"
    }
    
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
                            existingBook.chapters.sort { t1, t2 in
                                let num1 = self.extractChapterNumber(from: t1.filename)
                                let num2 = self.extractChapterNumber(from: t2.filename)
                                return num1 < num2
                            }
                        }
                        // Update metadata
                        if existingBook.librivoxChapters == nil { existingBook.librivoxChapters = fullChapterList }
                        if existingBook.description == nil { existingBook.description = description }
                        if existingBook.author == nil { existingBook.author = author }
                        if existingBook.coverArtUrl == nil { existingBook.coverArtUrl = coverUrl }
                        bookManager.books[existingIndex] = existingBook
                        bookManager.saveBooks()
                    } else {
                        let newBook = Book(
                            title: bookTitle,
                            author: author,
                            description: description,
                            chapters: [track],
                            librivoxChapters: fullChapterList,
                            coverArtUrl: coverUrl,
                            dateAdded: Date()
                        )
                        bookManager.addBook(newBook)
                    }
                }
            }
        }
    }
    
    private func downloadChapter(chapter: LibriVoxChapter, bookTitle: String, author: String, index: Int, completion: @escaping (Track?) -> Void) {
        guard let url = URL(string: chapter.listenUrl) else { completion(nil); return }
        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, _ in
            guard let tempURL = tempURL else { completion(nil); return }
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = self?.sanitizeFilename("\(bookTitle)_Chapter_\(String(format: "%03d", index + 1))_\(chapter.title).mp3") ?? "chapter.mp3"
            let destinationURL = documentsPath.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: destinationURL)
            try? FileManager.default.moveItem(at: tempURL, to: destinationURL)
            let track = Track(title: chapter.title, artist: author, filename: filename)
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
    
    // Updated checks to require Book ID
    func isDownloading(bookId: String, chapterId: String) -> Bool {
        downloadProgress[compositeId(bookId: bookId, chapterId: chapterId)] != nil
    }
    
    func isCompleted(bookId: String, chapterId: String) -> Bool {
        completedChapters.contains(compositeId(bookId: bookId, chapterId: chapterId))
    }
}

// MARK: - Book Manager

class BookManager: ObservableObject {
    static let shared = BookManager()
    @Published var books: [Book] = []
    private let userDefaults = UserDefaults.standard
    private let booksKey = "savedBooks"
    
    init() { loadBooks() }
    
    func getTrackDuration(track: Track) -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(track.filename)
        let asset = AVURLAsset(url: fileURL)
        let duration = asset.duration.seconds
        
        if duration.isNaN || duration.isZero { return "--:--" }
        
        let seconds = Int(duration)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
    
    func processUploadedTracks(_ tracks: [Track]) -> [Book] {
        var detectedBooks: [Book] = []
        var ungroupedTracks: [Track] = []
        var groupedByBase: [String: [Track]] = [:]
        
        for track in tracks {
            if let baseName = detectBaseName(from: track.filename) {
                groupedByBase[baseName, default: []].append(track)
            } else {
                ungroupedTracks.append(track)
            }
        }
        
        for (baseName, chapters) in groupedByBase {
            if chapters.count >= 2 {
                let sortedChapters = chapters.sorted { track1, track2 in
                    extractChapterNumber(from: track1.filename) < extractChapterNumber(from: track2.filename)
                }
                let artData = extractArtwork(from: sortedChapters.first?.filename)
                let artist = sortedChapters.first?.artist
                let book = Book(title: baseName, author: artist, description: nil, chapters: sortedChapters, coverArtData: artData, dateAdded: Date())
                detectedBooks.append(book)
            } else {
                ungroupedTracks.append(contentsOf: chapters)
            }
        }
        
        for track in ungroupedTracks {
            let artData = extractArtwork(from: track.filename)
            let book = Book(title: track.title, author: track.artist, description: nil, chapters: [track], coverArtData: artData, dateAdded: Date())
            detectedBooks.append(book)
        }
        return detectedBooks
    }
    
    private func extractArtwork(from filename: String?) -> Data? {
        guard let filename = filename else { return nil }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        let asset = AVURLAsset(url: fileURL)
        for item in asset.commonMetadata {
            if item.commonKey == .commonKeyArtwork, let data = item.dataValue { return data }
        }
        return nil
    }
    
    private func detectBaseName(from filename: String) -> String? {
        let name = filename.replacingOccurrences(of: "\\.(mp3|m4a|m4b)$", with: "", options: .regularExpression)
        let patterns = ["(.+?)[-_\\s]*(Chapter|Ch|Part|Pt)[-_\\s]*\\d+", "(.+?)[-_\\s]*\\d{2,3}", "(.+?)[-_\\s]*\\(\\d+\\)"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
               let range = Range(match.range(at: 1), in: name) {
                return String(name[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func extractChapterNumber(from filename: String) -> Int {
        let patterns = ["Chapter[-_\\s]*(\\d+)", "Ch[-_\\s]*(\\d+)", "Part[-_\\s]*(\\d+)", "Pt[-_\\s]*(\\d+)", "\\((\\d+)\\)", "[-_\\s](\\d{2,3})\\.(mp3|m4a|m4b)$"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
               let range = Range(match.range(at: 1), in: filename),
               let number = Int(filename[range]) {
                return number
            }
        }
        return 0
    }
    
    func addBook(_ book: Book) { books.append(book); saveBooks() }
    
    func removeBook(_ book: Book) {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for chapter in book.chapters {
            let fileURL = documentsPath.appendingPathComponent(chapter.filename)
            try? fileManager.removeItem(at: fileURL)
        }
        books.removeAll { $0.id == book.id }
        saveBooks()
    }
    
    func deleteChapter(at offsets: IndexSet, from book: Book) {
        guard let bookIndex = books.firstIndex(where: { $0.id == book.id }) else { return }
        var updatedBook = books[bookIndex]
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        for index in offsets {
            if index < updatedBook.chapters.count {
                let chapter = updatedBook.chapters[index]
                let fileURL = documentsPath.appendingPathComponent(chapter.filename)
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        updatedBook.chapters.remove(atOffsets: offsets)
        
        if updatedBook.chapters.isEmpty && (updatedBook.librivoxChapters == nil || updatedBook.librivoxChapters!.isEmpty) {
            removeBook(updatedBook)
        } else {
            if updatedBook.currentChapterIndex >= updatedBook.chapters.count {
                updatedBook.currentChapterIndex = max(0, updatedBook.chapters.count - 1)
            }
            books[bookIndex] = updatedBook
            saveBooks()
        }
    }
    
    func deleteChapterFile(filename: String, from book: Book) {
        guard let index = book.chapters.firstIndex(where: { $0.filename == filename }) else { return }
        deleteChapter(at: IndexSet(integer: index), from: book)
    }
    
    func updateProgress(bookId: UUID, chapterIndex: Int, position: Double) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].currentChapterIndex = chapterIndex
            books[index].lastPlayedPosition = position
            saveBooks()
        }
    }
    
    func saveBooks() {
        if let encoded = try? JSONEncoder().encode(books) { userDefaults.set(encoded, forKey: booksKey) }
    }
    
    private func loadBooks() {
        if let data = userDefaults.data(forKey: booksKey), let decoded = try? JSONDecoder().decode([Book].self, from: data) { books = decoded }
    }
}
