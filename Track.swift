//
//  Track.swift
//  2 Music 2 Furious - MILESTONE 4
//
//  Track model with Codable support for persistence
//

import Foundation

struct Track: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let artist: String
    let filename: String
    
    init(id: UUID = UUID(), title: String, artist: String, filename: String) {
        self.id = id
        self.title = title
        self.artist = artist
        self.filename = filename
    }
    
    // Helper to get readable display name
    var displayName: String {
        "\(artist) - \(title)"
    }
    
    // Equatable conformance
    static func == (lhs: Track, rhs: Track) -> Bool {
        return lhs.id == rhs.id
    }
}
