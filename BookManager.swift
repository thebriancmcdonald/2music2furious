//
//  BookManager.swift
//  2 Music 2 Furious - MILESTONE 4
//
//  Detects and manages audiobook chapters
//  Updates: Added description and author support
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

struct Book: Identifiable, Codable {
    var id = UUID()
    let title: String
    var author: String?         // <--- NEW
    var description: String?    // <--- NEW
    var chapters: [Track]
    var currentChapterIndex: Int = 0
    var lastPlayedPosition: Double = 0
    let dateAdded: Date
    
    // Artwork support
    var coverArtUrl: URL?       // For LibriVox
    var coverArtData: Data?     // For Local Uploads
    
    var displayTitle: String {
        let cleaned = title
            .replacingOccurrences(of: "_Chapter.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_Ch.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_Part.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
    }
    
    var displayAuthor: String {
        author ?? "Unknown Author"
    }
}

class BookManager: ObservableObject {
    
    static let shared = BookManager()
    
    @Published var books: [Book] = []
    
    private let userDefaults = UserDefaults.standard
    private let booksKey = "savedBooks"
    
    init() {
        loadBooks()
    }
    
    // MARK: - Chapter Detection
    
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
                
                // Try to extract artwork & artist from the first chapter
                let artData = extractArtwork(from: sortedChapters.first?.filename)
                let artist = sortedChapters.first?.artist
                
                let book = Book(
                    title: baseName,
                    author: artist,
                    description: nil, // Local files usually don't have full descriptions
                    chapters: sortedChapters,
                    dateAdded: Date(),
                    coverArtData: artData
                )
                detectedBooks.append(book)
            } else {
                ungroupedTracks.append(contentsOf: chapters)
            }
        }
        
        for track in ungroupedTracks {
            let artData = extractArtwork(from: track.filename)
            let book = Book(
                title: track.title,
                author: track.artist,
                description: nil,
                chapters: [track],
                dateAdded: Date(),
                coverArtData: artData
            )
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
            // Check for artwork keys
            if item.commonKey == .commonKeyArtwork {
                if let data = item.dataValue {
                    return data
                }
            }
        }
        return nil
    }
    
    private func detectBaseName(from filename: String) -> String? {
        let name = filename.replacingOccurrences(of: "\\.(mp3|m4a|m4b)$", with: "", options: .regularExpression)
        let patterns = [
            "(.+?)[-_\\s]*(Chapter|Ch|Part|Pt)[-_\\s]*\\d+",
            "(.+?)[-_\\s]*\\d{2,3}",
            "(.+?)[-_\\s]*\\(\\d+\\)",
        ]
        
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
        let patterns = [
            "Chapter[-_\\s]*(\\d+)",
            "Ch[-_\\s]*(\\d+)",
            "Part[-_\\s]*(\\d+)",
            "Pt[-_\\s]*(\\d+)",
            "\\((\\d+)\\)",
            "[-_\\s](\\d{2,3})\\.(mp3|m4a|m4b)$"
        ]
        
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
    
    // MARK: - Book Management
    
    func addBook(_ book: Book) {
        books.append(book)
        saveBooks()
    }
    
    func removeBook(_ book: Book) {
        // Delete actual files
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
        
        // Delete files for removed chapters
        for index in offsets {
            if index < updatedBook.chapters.count {
                let chapter = updatedBook.chapters[index]
                let fileURL = documentsPath.appendingPathComponent(chapter.filename)
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        updatedBook.chapters.remove(atOffsets: offsets)
        
        // If book is empty, remove it entirely
        if updatedBook.chapters.isEmpty {
            removeBook(updatedBook)
        } else {
            // Adjust current index if needed
            if updatedBook.currentChapterIndex >= updatedBook.chapters.count {
                updatedBook.currentChapterIndex = max(0, updatedBook.chapters.count - 1)
            }
            books[bookIndex] = updatedBook
            saveBooks()
        }
    }
    
    func updateProgress(bookId: UUID, chapterIndex: Int, position: Double) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].currentChapterIndex = chapterIndex
            books[index].lastPlayedPosition = position
            saveBooks()
        }
    }
    
    // MARK: - Persistence
    
    private func saveBooks() {
        if let encoded = try? JSONEncoder().encode(books) {
            userDefaults.set(encoded, forKey: booksKey)
        }
    }
    
    private func loadBooks() {
        if let data = userDefaults.data(forKey: booksKey),
           let decoded = try? JSONDecoder().decode([Book].self, from: data) {
            books = decoded
        }
    }
}
