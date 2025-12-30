//
//  MP4ChapterParser.swift
//  2 Music 2 Furious
//
//  Direct MP4/M4B chapter parser that reads the 'chpl' atom
//  This handles files where Apple's AVFoundation chapter API fails
//  (e.g., files from inAudible, some Audible converters, etc.)
//
//  The MP4 box structure we navigate:
//  ftyp (file type)
//  moov (movie container)
//    └── udta (user data)
//          └── chpl (chapter list) <-- what we want
//

import Foundation

/// Parses chapters directly from MP4/M4B files by reading the chpl atom
struct MP4ChapterParser {
    
    /// Chapter info extracted from the file
    struct Chapter {
        let title: String
        let startTime: Double   // seconds
        let endTime: Double     // seconds
        let index: Int
        
        var duration: Double { endTime - startTime }
        
        var formattedDuration: String {
            let seconds = Int(duration)
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            let s = seconds % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        }
    }
    
    /// Parse chapters from an M4B/M4A/MP4 file
    /// Returns nil if no chapters found or file can't be parsed
    static func parseChapters(from url: URL) -> [Chapter]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            print("📖 MP4ChapterParser: Could not read file")
            return nil
        }
        
        print("📖 MP4ChapterParser: File size = \(data.count) bytes")
        
        // List all top-level boxes for debugging
        print("📖 MP4ChapterParser: Scanning top-level boxes...")
        listBoxes(in: data, range: data.startIndex..<data.endIndex, indent: 0)
        
        // Find the moov box
        guard let moovRange = findBox(named: "moov", in: data, searchRange: data.startIndex..<data.endIndex) else {
            print("📖 MP4ChapterParser: No moov box found")
            return nil
        }
        print("📖 MP4ChapterParser: Found moov at \(moovRange.lowerBound), size \(moovRange.count)")
        
        // List boxes inside moov
        let moovContentStart = moovRange.lowerBound + 8
        print("📖 MP4ChapterParser: Boxes inside moov:")
        listBoxes(in: data, range: moovContentStart..<moovRange.upperBound, indent: 2)
        
        // Find udta box inside moov
        guard let udtaRange = findBox(named: "udta", in: data, searchRange: moovContentStart..<moovRange.upperBound) else {
            print("📖 MP4ChapterParser: No udta box found in moov")
            return nil
        }
        print("📖 MP4ChapterParser: Found udta at \(udtaRange.lowerBound), size \(udtaRange.count)")
        
        // List boxes inside udta
        let udtaContentStart = udtaRange.lowerBound + 8
        print("📖 MP4ChapterParser: Boxes inside udta:")
        listBoxes(in: data, range: udtaContentStart..<udtaRange.upperBound, indent: 4)
        
        // Find chpl box inside udta
        guard let chplRange = findBox(named: "chpl", in: data, searchRange: udtaContentStart..<udtaRange.upperBound) else {
            print("📖 MP4ChapterParser: No chpl box found in udta")
            return nil
        }
        print("📖 MP4ChapterParser: Found chpl at \(chplRange.lowerBound), size \(chplRange.count)")
        
        // Parse the chpl box
        return parseChplBox(data: data, range: chplRange)
    }
    
    /// Debug helper: list boxes at a given level
    private static func listBoxes(in data: Data, range: Range<Data.Index>, indent: Int) {
        var offset = range.lowerBound
        let prefix = String(repeating: " ", count: indent)
        var count = 0
        
        while offset + 8 <= range.upperBound && count < 50 {
            let sizeBytes = data[offset..<offset+4]
            let size = UInt32(bigEndian: sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self) })
            
            let typeBytes = data[offset+4..<offset+8]
            let type = String(bytes: typeBytes, encoding: .ascii) ?? "????"
            
            var actualSize: UInt64 = UInt64(size)
            if size == 1 && offset + 16 <= range.upperBound {
                let extSizeBytes = data[offset+8..<offset+16]
                actualSize = UInt64(bigEndian: extSizeBytes.withUnsafeBytes { $0.load(as: UInt64.self) })
            } else if size == 0 {
                actualSize = UInt64(range.upperBound - offset)
            }
            
            guard actualSize >= 8 else { break }
            
            print("\(prefix)📦 '\(type)' size=\(actualSize) at offset \(offset)")
            
            let boxEnd = offset + Int(min(actualSize, UInt64(range.upperBound - offset)))
            offset = boxEnd
            count += 1
        }
    }
    
    /// Find a box by its 4-character name within a range
    private static func findBox(named name: String, in data: Data, searchRange: Range<Data.Index>) -> Range<Data.Index>? {
        var offset = searchRange.lowerBound
        
        while offset + 8 <= searchRange.upperBound {
            // Read box size (4 bytes, big-endian)
            let sizeBytes = data[offset..<offset+4]
            let size = UInt32(bigEndian: sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self) })
            
            // Read box type (4 bytes ASCII)
            let typeBytes = data[offset+4..<offset+8]
            let type = String(bytes: typeBytes, encoding: .ascii) ?? ""
            
            // Handle extended size (size == 1 means 64-bit size follows)
            var actualSize: UInt64 = UInt64(size)
            var headerSize = 8
            
            if size == 1 && offset + 16 <= searchRange.upperBound {
                let extSizeBytes = data[offset+8..<offset+16]
                actualSize = UInt64(bigEndian: extSizeBytes.withUnsafeBytes { $0.load(as: UInt64.self) })
                headerSize = 16
            } else if size == 0 {
                // Size 0 means box extends to end of file
                actualSize = UInt64(searchRange.upperBound - offset)
            }
            
            // Safety check
            guard actualSize >= UInt64(headerSize) else {
                print("📖 MP4ChapterParser: Invalid box size at offset \(offset)")
                break
            }
            
            let boxEnd = offset + Int(actualSize)
            guard boxEnd <= searchRange.upperBound else {
                break
            }
            
            if type == name {
                return offset..<boxEnd
            }
            
            offset = boxEnd
        }
        
        return nil
    }
    
    /// Parse the chpl (chapter list) box
    private static func parseChplBox(data: Data, range: Range<Data.Index>) -> [Chapter]? {
        var offset = range.lowerBound + 8 // skip size + type
        
        guard offset + 5 <= range.upperBound else { return nil }
        
        // Version (1 byte) + Flags (3 bytes)
        let version = data[offset]
        offset += 4 // skip version + flags
        
        // Reserved (4 bytes) - appears in some chpl boxes
        // Actually, let's check: some encoders put a reserved field, some don't
        // The inAudible format seems to have: version(1) + flags(3) + reserved(4) + count(1)
        // But standard is: version(1) + flags(3) + count(4 for v1, 1 for v0)
        
        // Let's try to detect the format by looking at what makes sense
        // If next byte looks like a small count and following data looks like timestamps, use that
        
        var chapterCount: Int
        
        if version == 1 {
            // Version 1: 4-byte count
            guard offset + 4 <= range.upperBound else { return nil }
            let countBytes = data[offset..<offset+4]
            chapterCount = Int(UInt32(bigEndian: countBytes.withUnsafeBytes { $0.load(as: UInt32.self) }))
            offset += 4
        } else {
            // Version 0: Try to figure out the format
            // Some encoders use 1-byte count, some use 4-byte with reserved padding
            
            // Peek ahead to see what makes sense
            // inAudible seems to use: 4 bytes reserved/unknown + 1 byte count
            // Standard v0 is just 1 byte count
            
            // Let's try: if byte at offset is 0 and byte at offset+4 is reasonable, use inAudible format
            if offset + 5 <= range.upperBound && data[offset] == 0 {
                // Likely has 4-byte reserved field
                offset += 4
                guard offset + 1 <= range.upperBound else { return nil }
                chapterCount = Int(data[offset])
                offset += 1
            } else {
                // Standard 1-byte count
                guard offset + 1 <= range.upperBound else { return nil }
                chapterCount = Int(data[offset])
                offset += 1
            }
        }
        
        // Sanity check
        guard chapterCount > 0 && chapterCount < 10000 else {
            print("📖 MP4ChapterParser: Invalid chapter count: \(chapterCount)")
            return nil
        }
        
        print("📖 MP4ChapterParser: Found \(chapterCount) chapters")
        
        var chapters: [Chapter] = []
        var previousEndTime: Double = 0
        
        for i in 0..<chapterCount {
            guard offset + 9 <= range.upperBound else {
                print("📖 MP4ChapterParser: Unexpected end of data at chapter \(i)")
                break
            }
            
            // Timestamp: 8 bytes, in 100-nanosecond units (like Windows FILETIME)
            let timestampBytes = data[offset..<offset+8]
            let timestamp = UInt64(bigEndian: timestampBytes.withUnsafeBytes { $0.load(as: UInt64.self) })
            let startTimeSeconds = Double(timestamp) / 10_000_000.0 // Convert 100ns to seconds
            offset += 8
            
            // Title length: 1 byte
            let titleLength = Int(data[offset])
            offset += 1
            
            // Title: variable length string
            guard offset + titleLength <= range.upperBound else {
                print("📖 MP4ChapterParser: Title extends beyond box at chapter \(i)")
                break
            }
            
            let titleData = data[offset..<offset+titleLength]
            let title = String(data: titleData, encoding: .utf8) ?? "Chapter \(i + 1)"
            offset += titleLength
            
            // Update previous chapter's end time
            if !chapters.isEmpty {
                let lastIndex = chapters.count - 1
                chapters[lastIndex] = Chapter(
                    title: chapters[lastIndex].title,
                    startTime: chapters[lastIndex].startTime,
                    endTime: startTimeSeconds,
                    index: lastIndex
                )
            }
            
            chapters.append(Chapter(
                title: title,
                startTime: startTimeSeconds,
                endTime: startTimeSeconds, // Will be updated by next chapter or file duration
                index: i
            ))
            
            previousEndTime = startTimeSeconds
        }
        
        return chapters.isEmpty ? nil : chapters
    }
    
    /// Update the last chapter's end time with the file duration
    static func updateLastChapterEndTime(chapters: inout [Chapter], fileDuration: Double) {
        guard !chapters.isEmpty else { return }
        let lastIndex = chapters.count - 1
        chapters[lastIndex] = Chapter(
            title: chapters[lastIndex].title,
            startTime: chapters[lastIndex].startTime,
            endTime: fileDuration,
            index: lastIndex
        )
    }
}
