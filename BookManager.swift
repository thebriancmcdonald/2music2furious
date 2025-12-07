//
//  BookManager.swift
//  2 Music 2 Furious - MILESTONE 4
//
//  Detects and manages audiobook chapters
//

import Foundation
import Combine

struct Book: Identifiable, Codable {
    var id = UUID()  // var to satisfy Codable requirements
    let title: String
    var chapters: [Track]
    var currentChapterIndex: Int = 0
    var lastPlayedPosition: Double = 0
    let dateAdded: Date
    
    var displayTitle: String {
        // Clean up the title (remove common patterns)
        let cleaned = title
            .replacingOccurrences(of: "_Chapter.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_Ch.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_Part.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
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
    
    /// Analyze uploaded files and group them into books
    func processUploadedTracks(_ tracks: [Track]) -> [Book] {
        var detectedBooks: [Book] = []
        var ungroupedTracks: [Track] = []
        
        // Group tracks by base name
        var groupedByBase: [String: [Track]] = [:]
        
        for track in tracks {
            if let baseName = detectBaseName(from: track.filename) {
                groupedByBase[baseName, default: []].append(track)
            } else {
                ungroupedTracks.append(track)
            }
        }
        
        // Create books from groups with 2+ chapters
        for (baseName, chapters) in groupedByBase {
            if chapters.count >= 2 {
                // Sort chapters
                let sortedChapters = chapters.sorted { track1, track2 in
                    extractChapterNumber(from: track1.filename) < extractChapterNumber(from: track2.filename)
                }
                
                let book = Book(
                    title: baseName,
                    chapters: sortedChapters,
                    dateAdded: Date()
                )
                detectedBooks.append(book)
            } else {
                // Single file, don't group
                ungroupedTracks.append(contentsOf: chapters)
            }
        }
        
        // Create individual "books" for ungrouped tracks
        for track in ungroupedTracks {
            let book = Book(
                title: track.title,
                chapters: [track],
                dateAdded: Date()
            )
            detectedBooks.append(book)
        }
        
        return detectedBooks
    }
    
    /// Detect base name from filename
    private func detectBaseName(from filename: String) -> String? {
        let name = filename.replacingOccurrences(of: "\\.(mp3|m4a|m4b)$", with: "", options: .regularExpression)
        
        // Common patterns for chapters
        let patterns = [
            "(.+?)[-_\\s]*(Chapter|Ch|Part|Pt)[-_\\s]*\\d+",
            "(.+?)[-_\\s]*\\d{2,3}",  // Ends with 2-3 digits
            "(.+?)[-_\\s]*\\(\\d+\\)",  // Ends with (1), (2), etc.
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
    
    /// Extract chapter number from filename
    private func extractChapterNumber(from filename: String) -> Int {
        // Look for numbers in the filename
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
    
    /// Add a book to the library
    func addBook(_ book: Book) {
        books.append(book)
        saveBooks()
    }
    
    /// Remove a book
    func removeBook(_ book: Book) {
        books.removeAll { $0.id == book.id }
        saveBooks()
    }
    
    /// Update book progress
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
