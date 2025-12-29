//
//  Track.swift
//  2 Music 2 Furious - MILESTONE 4
//
//  Track model with Codable support for persistence
//  UPDATED: Added Hashable conformance for SwiftUI Lists
//  UPDATED: Added chapter boundary support for M4B audiobooks (startTime/endTime)
//

import Foundation

struct Track: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let artist: String
    let filename: String
    
    // MARK: - Chapter Boundaries (for M4B audiobooks)
    // When set, the track represents a portion of a larger audio file.
    // Times are in seconds from the start of the file.
    // nil = use full file (default behavior for regular audio files)
    
    let startTime: Double?  // Chapter start position in seconds
    let endTime: Double?    // Chapter end position in seconds
    
    /// Returns true if this track has chapter boundaries (is part of a chaptered audiobook)
    var hasChapterBoundaries: Bool {
        startTime != nil && endTime != nil
    }
    
    /// The duration of this chapter in seconds (nil if no boundaries set)
    var chapterDuration: Double? {
        guard let start = startTime, let end = endTime else { return nil }
        return end - start
    }
    
    // MARK: - Initializers
    
    /// Standard initializer for regular audio files (no chapter boundaries)
    init(id: UUID = UUID(), title: String, artist: String, filename: String) {
        self.id = id
        self.title = title
        self.artist = artist
        self.filename = filename
        self.startTime = nil
        self.endTime = nil
    }
    
    /// Full initializer with chapter boundary support for M4B audiobooks
    init(id: UUID = UUID(), title: String, artist: String, filename: String, startTime: Double?, endTime: Double?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.filename = filename
        self.startTime = startTime
        self.endTime = endTime
    }
    
    // MARK: - Computed Properties
    
    /// Helper to get readable display name
    var displayName: String {
        "\(artist) - \(title)"
    }
    
    // MARK: - Protocol Conformance
    
    /// Hashable conformance (Must match Equatable logic)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// Equatable conformance
    static func == (lhs: Track, rhs: Track) -> Bool {
        return lhs.id == rhs.id
    }
}
