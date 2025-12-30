//
//  BookLibraryView.swift
//  2 Music 2 Furious - MILESTONE 14.5
//
//  Audiobook library - Uses SharedComponents for consistency
//  UPDATED: Added Played Status Tracking via GlassEpisodeRow
//  UPDATED: Comprehensive audiobook file format support including .m4b
//  UPDATED: Fast M4B import using virtual chapters (pointer method - instant!)
//  FIXED: Robust UTType handling that actually works
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Combine  // Required for ObservableObject

// MARK: - Supported Audiobook File Types

/// Build the list of supported types using system lookups for reliability
/// This approach queries iOS for the correct UTType instead of hardcoding identifiers
func buildSupportedAudioTypes() -> [UTType] {
    var types: [UTType] = [
        .audio,         // Base audio type
        .mp3,           // MPEG Audio Layer 3
        .mpeg4Audio,    // MPEG-4 Audio (.m4a) - this SHOULD include .m4b but often doesn't
        .wav,           // Waveform Audio
        .aiff,          // Audio Interchange File Format
    ]
    
    // Try to get .m4b type from the system using multiple approaches
    
    // Approach 1: Query system for types matching .m4b extension
    let m4bTypes = UTType.types(tag: "m4b", tagClass: .filenameExtension, conformingTo: .audio)
    types.append(contentsOf: m4bTypes)
    
    // Approach 2: Try known Apple identifier
    if let m4bApple = UTType("com.apple.m4b-audio") {
        types.append(m4bApple)
    }
    
    // Approach 3: Try alternate identifier
    if let m4bAlt = UTType("public.m4b-audio") {
        types.append(m4bAlt)
    }
    
    // Approach 4: Create from extension as last resort
    if let m4bExt = UTType(filenameExtension: "m4b") {
        types.append(m4bExt)
    }
    
    // Approach 5: Try MPEG-4 types (m4b is technically an MPEG-4 container)
    if let mpeg4 = UTType("public.mpeg-4") {
        types.append(mpeg4)
    }
    if let mpeg4Audio = UTType("public.mpeg-4-audio") {
        types.append(mpeg4Audio)
    }
    
    // Add other audio formats
    let otherExtensions = ["aac", "flac", "ogg", "opus"]
    for ext in otherExtensions {
        if let type = UTType(filenameExtension: ext) {
            types.append(type)
        }
        types.append(contentsOf: UTType.types(tag: ext, tagClass: .filenameExtension, conformingTo: .audio))
    }
    
    // Remove duplicates while preserving order
    var seen = Set<UTType>()
    return types.filter { seen.insert($0).inserted }
}

/// All supported audiobook/audio file types for the file importer
let supportedAudiobookTypes: [UTType] = buildSupportedAudioTypes()

// MARK: - M4B Chapter Reader (Fast - Metadata Only)

/// Reads chapter metadata from M4B files WITHOUT extracting audio
/// This is instant (~2 seconds) compared to extraction (~10 minutes for long books)
/// 
/// Strategy:
/// 1. Try Apple's AVFoundation chapter API first (works for properly tagged files)
/// 2. If no chapters found, try direct MP4 chpl atom parsing (works for inAudible, etc.)
/// 3. If still nothing, treat as single chapter
struct M4BChapterReader {
    
    /// Chapter info with time pointers
    struct ChapterInfo {
        let title: String
        let startTime: Double   // Seconds from file start
        let endTime: Double     // Seconds from file start
        let index: Int
        
        var durationSeconds: Double { endTime - startTime }
        
        var formattedDuration: String {
            let seconds = Int(durationSeconds)
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            let s = seconds % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        }
    }
    
    /// Read chapter metadata from an M4B/M4A file
    /// Returns chapters, title, author, artwork - all from metadata
    static func readChapterMetadata(from url: URL) async throws -> (chapters: [ChapterInfo], title: String?, author: String?, artwork: Data?) {
        let asset = AVURLAsset(url: url)
        
        // Load metadata
        let metadata = try await asset.load(.commonMetadata)
        let duration = try await asset.load(.duration)
        let fileDuration = CMTimeGetSeconds(duration)
        
        // Extract title, author, artwork from metadata
        var title: String? = nil
        var author: String? = nil
        var artwork: Data? = nil
        
        for item in metadata {
            if item.commonKey == .commonKeyTitle {
                title = try? await item.load(.stringValue)
            } else if item.commonKey == .commonKeyArtist || item.commonKey == .commonKeyAuthor {
                author = try? await item.load(.stringValue)
            } else if item.commonKey == .commonKeyArtwork {
                artwork = try? await item.load(.dataValue)
            }
        }
        
        var chapters: [ChapterInfo] = []
        
        // APPROACH 1: Try Apple's AVFoundation chapter API
        let locales = try await asset.load(.availableChapterLocales)
        
        if let locale = locales.first {
            let chapterGroups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: [locale.identifier])
            
            for (index, group) in chapterGroups.enumerated() {
                var chapterTitle = "Chapter \(index + 1)"
                for item in group.items {
                    if item.commonKey == .commonKeyTitle {
                        if let titleValue = try? await item.load(.stringValue) {
                            chapterTitle = titleValue
                        }
                    }
                }
                
                let startTime = CMTimeGetSeconds(group.timeRange.start)
                let endTime = startTime + CMTimeGetSeconds(group.timeRange.duration)
                
                chapters.append(ChapterInfo(
                    title: chapterTitle,
                    startTime: startTime,
                    endTime: endTime,
                    index: index
                ))
            }
        }
        
        // APPROACH 2: If Apple API found nothing, try direct MP4 parsing
        if chapters.isEmpty {
            print("📖 Apple API found no chapters, trying direct MP4 parsing...")
            
            if var mp4Chapters = MP4ChapterParser.parseChapters(from: url) {
                // Update last chapter's end time with file duration
                MP4ChapterParser.updateLastChapterEndTime(chapters: &mp4Chapters, fileDuration: fileDuration)
                
                // Convert to our ChapterInfo format
                chapters = mp4Chapters.map { mp4Chapter in
                    ChapterInfo(
                        title: mp4Chapter.title,
                        startTime: mp4Chapter.startTime,
                        endTime: mp4Chapter.endTime,
                        index: mp4Chapter.index
                    )
                }
                
                print("📖 Direct parsing found \(chapters.count) chapters!")
            }
        }
        
        // APPROACH 3: If still no chapters, treat entire file as one chapter
        if chapters.isEmpty {
            print("📖 No chapters found, treating as single-chapter audiobook")
            chapters.append(ChapterInfo(
                title: title ?? "Full Audiobook",
                startTime: 0,
                endTime: fileDuration,
                index: 0
            ))
        }
        
        return (chapters, title, author, artwork)
    }
    
    /// Check if file has embedded chapters (checks both Apple API and direct parsing)
    static func hasChapters(url: URL) async -> Bool {
        print("📖 hasChapters checking: \(url.path)")
        
        // First try Apple API
        let asset = AVURLAsset(url: url)
        do {
            let locales = try await asset.load(.availableChapterLocales)
            print("📖 Apple API locales: \(locales)")
            if !locales.isEmpty {
                print("📖 Apple API found chapters!")
                return true
            }
        } catch {
            print("📖 Apple API error: \(error)")
        }
        
        // Try direct MP4 parsing
        print("📖 Trying direct MP4 parsing...")
        if let chapters = MP4ChapterParser.parseChapters(from: url), !chapters.isEmpty {
            print("📖 Direct parsing found \(chapters.count) chapters!")
            return true
        }
        
        print("📖 No chapters found by either method")
        return false
    }
}

// MARK: - M4B Import State

/// Tracks the state of M4B import (now very fast!)
class M4BImportState: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage = "Reading audiobook..."
}

// MARK: - Book Library View

struct BookLibraryView: View {
    @ObservedObject var bookManager: BookManager
    @ObservedObject var speechPlayer: AudioPlayer
    let dismiss: () -> Void
    
    @State private var showingFilePicker = false
    @State private var showingLibriVox = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    // M4B Processing State
    @StateObject private var m4bImportState = M4BImportState()
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                
                if bookManager.books.isEmpty && !m4bImportState.isProcessing {
                    GlassEmptyStateView(
                        icon: "books.vertical",
                        title: "Your Library is Empty",
                        subtitle: "Import files from your device or\nsearch the public domain.",
                        actions: [
                            (icon: "square.and.arrow.up", title: "Upload Files", action: { showingFilePicker = true }),
                            (icon: "magnifyingglass", title: "Search LibriVox", action: { showingLibriVox = true })
                        ]
                    )
                } else if !m4bImportState.isProcessing {
                    List {
                        ForEach(bookManager.books) { book in
                            ZStack {
                                NavigationLink(destination: LocalBookDetailView(book: book, bookManager: bookManager, onPlayChapter: { index in playBook(book, startingAt: index) })) { EmptyView() }.opacity(0)
                                GlassBookRow(book: book, onPlay: { playBook(book) })
                            }
                            .glassListRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { bookManager.removeBook(book) } label: { Label("Delete", systemImage: "trash") }
                                    .tint(.royalPurple)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .tint(.royalPurple)
                }
                
                // Quick Processing Overlay (shows briefly during M4B import)
                if m4bImportState.isProcessing {
                    M4BQuickProcessingOverlay(state: m4bImportState)
                }
                
                if showingToast && !m4bImportState.isProcessing {
                    VStack { Spacer(); GlassToastView(message: toastMessage).padding(.bottom, 20) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(), value: showingToast)
                        .zIndex(100)
                }
            }
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingFilePicker = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                    }
                    .disabled(m4bImportState.isProcessing)
                    
                    Button { showingLibriVox = true } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white)
                    }
                    .disabled(m4bImportState.isProcessing)
                }
            }
            // NUCLEAR OPTION: Use .item to allow ALL files, then filter by extension
            // This bypasses all UTType issues completely
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.item],  // Allow everything
                allowsMultipleSelection: true
            ) { result in
                handleFileUpload(result: result)
            }
            .sheet(isPresented: $showingLibriVox) {
                LibriVoxSearchView(bookManager: bookManager, dismiss: { showingLibriVox = false })
            }
        }
        .accentColor(.royalPurple)
        .tint(.royalPurple)
    }
    
    // MARK: - File Upload Handler
    
    /// Supported audio file extensions (checked manually since UTType is unreliable)
    private let supportedExtensions = Set(["mp3", "m4a", "m4b", "wav", "aiff", "aac", "flac", "ogg", "opus", "mp4", "aif"])
    
    private func handleFileUpload(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            
            // Filter to only audio files by extension
            let audioURLs = urls.filter { url in
                supportedExtensions.contains(url.pathExtension.lowercased())
            }
            
            guard !audioURLs.isEmpty else {
                showToast("No supported audio files selected")
                return
            }
            
            // Separate M4B files from regular audio files
            var m4bURLs: [URL] = []
            var regularURLs: [URL] = []
            
            for url in audioURLs {
                let ext = url.pathExtension.lowercased()
                if ext == "m4b" || ext == "m4a" {
                    m4bURLs.append(url)
                } else {
                    regularURLs.append(url)
                }
            }
            
            // Process regular audio files immediately
            if !regularURLs.isEmpty {
                processRegularAudioFiles(regularURLs)
            }
            
            // Process M4B/M4A files (fast - just reads metadata)
            if !m4bURLs.isEmpty {
                Task {
                    await processM4BFiles(m4bURLs)
                }
            }
            
        } catch {
            print("Upload error: \(error)")
            showToast("Upload failed")
        }
    }
    
    // MARK: - Regular Audio File Processing
    
    private func processRegularAudioFiles(_ urls: [URL]) {
        var uploadedTracks: [Track] = []
        
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let filename = url.lastPathComponent
                let destinationURL = documentsPath.appendingPathComponent(filename)
                
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    
                    let title = filename
                        .replacingOccurrences(of: "_", with: " ")
                        .components(separatedBy: ".")
                        .dropLast()
                        .joined(separator: ".")
                    
                    let track = Track(title: title, artist: "Audiobook", filename: filename)
                    uploadedTracks.append(track)
                } catch {
                    print("Error copying file: \(error)")
                }
            }
        }
        
        if !uploadedTracks.isEmpty {
            let newBooks = bookManager.processUploadedTracks(uploadedTracks)
            for book in newBooks {
                bookManager.addBook(book)
            }
            showToast("Added \(newBooks.count) audiobook(s)")
        }
    }
    
    // MARK: - M4B File Processing (Fast - Metadata Only!)
    
    @MainActor
    private func processM4BFiles(_ urls: [URL]) async {
        print("🎧 processM4BFiles called with \(urls.count) files")
        
        m4bImportState.isProcessing = true
        m4bImportState.statusMessage = "Reading audiobook metadata..."
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var totalBooksAdded = 0
        var totalChapters = 0
        
        for url in urls {
            print("🎧 Processing: \(url.lastPathComponent)")
            
            // Start security-scoped resource access
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // Copy file to documents directory (needed for playback)
            let filename = url.lastPathComponent
            let destinationURL = documentsPath.appendingPathComponent(filename)
            
            print("🎧 Destination: \(destinationURL.path)")
            
            do {
                // Copy to local documents
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                    print("🎧 Removed existing file")
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)
                print("🎧 File copied successfully")
                
                // Verify file exists and is readable
                let fileSize = try FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int ?? 0
                print("🎧 File size: \(fileSize) bytes")
                
                m4bImportState.statusMessage = "Reading chapters..."
                
                // Check if file has chapters
                print("🎧 Checking for chapters...")
                let hasChapters = await M4BChapterReader.hasChapters(url: destinationURL)
                print("🎧 hasChapters = \(hasChapters)")
                
                if hasChapters {
                    print("🎧 Reading chapter metadata...")
                    // Read chapter metadata (FAST - no extraction!)
                    let (chapters, title, author, artwork) = try await M4BChapterReader.readChapterMetadata(from: destinationURL)
                    
                    print("🎧 Found \(chapters.count) chapters, title: \(title ?? "nil"), author: \(author ?? "nil")")
                    
                    let bookTitle = title ?? url.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "_", with: " ")
                    let bookAuthor = author ?? "Unknown Author"
                    
                    // Create tracks with time pointers (virtual chapters)
                    var chapterTracks: [Track] = []
                    
                    for chapter in chapters {
                        let track = Track(
                            title: chapter.title,
                            artist: bookAuthor,
                            filename: filename,  // All chapters point to same file!
                            startTime: chapter.startTime,
                            endTime: chapter.endTime
                        )
                        chapterTracks.append(track)
                    }
                    
                    // Create book with virtual chapters
                    let newBook = Book(
                        title: bookTitle,
                        author: bookAuthor,
                        description: nil,
                        chapters: chapterTracks,
                        librivoxChapters: nil,
                        coverArtUrl: nil,
                        coverArtData: artwork,
                        currentChapterIndex: 0,
                        lastPlayedPosition: 0,
                        dateAdded: Date()
                    )
                    
                    bookManager.addBook(newBook)
                    totalBooksAdded += 1
                    totalChapters += chapters.count
                    
                } else {
                    print("🎧 No chapters found, creating single-chapter book")
                    // No chapters - treat as single-chapter audiobook
                    let title = filename
                        .replacingOccurrences(of: "_", with: " ")
                        .components(separatedBy: ".")
                        .dropLast()
                        .joined(separator: ".")
                    
                    let track = Track(title: title, artist: "Audiobook", filename: filename)
                    let artData = extractArtwork(from: filename)
                    
                    let newBook = Book(
                        title: title,
                        author: nil,
                        description: nil,
                        chapters: [track],
                        coverArtData: artData,
                        dateAdded: Date()
                    )
                    
                    bookManager.addBook(newBook)
                    totalBooksAdded += 1
                    totalChapters += 1
                }
                
            } catch {
                print("🎧 M4B processing error: \(error)")
                // Clean up on error
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }
        
        m4bImportState.isProcessing = false
        
        if totalBooksAdded > 0 {
            if totalChapters > 1 {
                showToast("Added \(totalBooksAdded) book(s) with \(totalChapters) chapters")
            } else {
                showToast("Added \(totalBooksAdded) audiobook(s)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractArtwork(from filename: String) -> Data? {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        let asset = AVURLAsset(url: fileURL)
        for item in asset.commonMetadata {
            if item.commonKey == .commonKeyArtwork, let data = item.dataValue {
                return data
            }
        }
        return nil
    }
    
    private func playBook(_ book: Book, startingAt index: Int? = nil) {
        speechPlayer.setExternalArtwork(from: book.coverArtUrl)
        speechPlayer.clearQueue()
        for chapter in book.chapters { speechPlayer.addTrackToQueue(chapter) }
        let startIndex = index ?? book.currentChapterIndex
        if speechPlayer.queue.count > 0 {
            let safeIndex = min(max(0, startIndex), speechPlayer.queue.count - 1)
            speechPlayer.currentIndex = safeIndex
            speechPlayer.playNow(speechPlayer.queue[safeIndex], artworkURL: book.coverArtUrl)
        }
        dismiss()
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { showingToast = false } }
    }
}

// MARK: - Quick Processing Overlay (Brief - just metadata reading)

struct M4BQuickProcessingOverlay: View {
    @ObservedObject var state: M4BImportState
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text(state.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - Local Book Detail View

struct LocalBookDetailView: View {
    let book: Book
    @ObservedObject var bookManager: BookManager
    @ObservedObject var downloadManager = LibriVoxDownloadManager.shared
    
    let onPlayChapter: (Int) -> Void
    
    @State private var filter: FilterOption = .downloaded
    @State private var toastMessage = ""
    @State private var showingToast = false
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case downloaded = "Downloaded"
    }
    
    // For uploaded/local books, show single filter if no librivox chapters
    var showFilter: Bool {
        book.librivoxChapters != nil && !(book.librivoxChapters?.isEmpty ?? true)
    }
    
    var chaptersToDisplay: [DisplayChapter] {
        if filter == .downloaded || !showFilter {
            return book.chapters.enumerated().map { (index, track) in
                // For virtual chapters, use chapterDuration if available
                let duration: String
                if let chapterDuration = track.chapterDuration {
                    let seconds = Int(chapterDuration)
                    let h = seconds / 3600
                    let m = (seconds % 3600) / 60
                    let s = seconds % 60
                    duration = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
                } else {
                    duration = bookManager.getTrackDuration(track: track)
                }
                
                // Use track ID as unique ID for virtual chapters
                let uniqueId = track.hasChapterBoundaries ? track.id.uuidString : track.filename
                
                return DisplayChapter(index: index, title: track.title, isDownloaded: true, filename: track.filename, remoteChapter: nil, duration: duration, uniqueId: uniqueId)
            }
        } else {
            if let remote = book.librivoxChapters, !remote.isEmpty {
                return remote.enumerated().map { (index, remoteChap) in
                    let targetIndex = index + 1
                    let match = book.chapters.first { track in
                        track.filename.contains("Chapter_\(String(format: "%03d", targetIndex))_")
                    }
                    return DisplayChapter(index: index, title: remoteChap.title, isDownloaded: match != nil, filename: match?.filename, remoteChapter: remoteChap, duration: remoteChap.formattedDuration, uniqueId: remoteChap.id)
                }
            } else {
                return book.chapters.enumerated().map { (index, track) in
                    let duration = bookManager.getTrackDuration(track: track)
                    return DisplayChapter(index: index, title: track.title, isDownloaded: true, filename: track.filename, remoteChapter: nil, duration: duration, uniqueId: track.filename)
                }
            }
        }
    }
    
    struct DisplayChapter: Identifiable {
        var id: String { uniqueId }
        let index: Int
        let title: String
        let isDownloaded: Bool
        let filename: String?
        let remoteChapter: LibriVoxChapter?
        let duration: String
        let uniqueId: String
    }
    
    var body: some View {
        ZStack {
            GlassBackgroundView()
            
            List {
                Section {
                    VStack(spacing: 20) {
                        MediaDetailHeader(
                            title: book.displayTitle,
                            subtitle: book.displayAuthor,
                            tertiaryText: chapterCountText,
                            artworkURL: book.coverArtUrl,
                            artworkData: book.coverArtData,
                            artworkIcon: "book.fill",
                            artworkColor: .royalPurple
                        )
                        
                        GlassActionButton(
                            title: "Resume",
                            icon: "play.fill",
                            color: .deepResumePurple,
                            action: { onPlayChapter(book.currentChapterIndex) }
                        )
                        
                        if let desc = book.description, !desc.isEmpty {
                            ExpandableDescriptionView(
                                text: desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
                                color: .royalPurple
                            )
                            .tint(.royalPurple)
                            .accentColor(.royalPurple)
                        }
                        
                        // Only show filter for LibriVox books with remote chapters
                        if showFilter {
                            GlassSegmentedFilter(
                                selection: $filter,
                                options: FilterOption.allCases.map { ($0, $0.rawValue) },
                                color: .royalPurple
                            )
                        }
                    }
                    .padding(.bottom, 10)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                
                Section {
                    ForEach(chaptersToDisplay) { chapter in
                        let isPlayed = bookManager.isPlayed(chapterId: chapter.uniqueId)
                        
                        GlassEpisodeRow(
                            title: chapter.title,
                            duration: chapter.duration,
                            isPlayed: isPlayed,
                            isDownloaded: chapter.isDownloaded,
                            isDownloading: chapter.remoteChapter != nil && downloadManager.isDownloading(bookId: book.librivoxChapters?.first?.id ?? "", chapterId: chapter.remoteChapter!.id),
                            downloadColor: .royalPurple,
                            onDownload: {
                                if !chapter.isDownloaded, let remote = chapter.remoteChapter {
                                    downloadManager.downloadSingleChapter(
                                        chapter: remote,
                                        bookId: book.title,
                                        bookTitle: book.title,
                                        author: book.displayAuthor,
                                        coverUrl: book.coverArtUrl,
                                        description: book.description,
                                        index: chapter.index,
                                        bookManager: bookManager,
                                        fullChapterList: book.librivoxChapters
                                    )
                                    showToast("Downloading...")
                                }
                            },
                            onPlay: {
                                onPlayChapter(chapter.index)
                            }
                        )
                        .glassListRow()
                        // SWIPE ACTION: Toggle Played
                        .swipeActions(edge: .leading) {
                            Button {
                                bookManager.togglePlayed(chapterId: chapter.uniqueId)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label(isPlayed ? "Unmark" : "Played", systemImage: isPlayed ? "eye.slash" : "eye")
                            }.tint(.orange)
                        }
                        // For virtual chapters, we don't delete individual chapters (they share one file)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if chapter.isDownloaded && chapter.remoteChapter != nil, let filename = chapter.filename {
                                Button(role: .destructive) {
                                    bookManager.deleteChapterFile(filename: filename, from: book)
                                } label: { Label("Delete", systemImage: "trash") }
                                    .tint(.royalPurple)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            if showingToast {
                VStack { Spacer(); GlassToastView(message: toastMessage, icon: "arrow.down.circle.fill", iconColor: .royalPurple).padding(.bottom, 20) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: showingToast)
                    .zIndex(100)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Only preload durations for non-virtual chapters
            if let firstChapter = book.chapters.first, !firstChapter.hasChapterBoundaries {
                bookManager.preloadDurations(for: book)
            }
        }
    }
    
    var chapterCountText: String {
        if let librivoxChapters = book.librivoxChapters, !librivoxChapters.isEmpty {
            return "\(book.chapters.count) of \(librivoxChapters.count) Downloaded"
        } else {
            return "\(book.chapters.count) chapter\(book.chapters.count == 1 ? "" : "s")"
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { showingToast = false } }
    }
}

// MARK: - Glass Book Row

struct GlassBookRow: View {
    let book: Book
    let onPlay: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkView(
                url: book.coverArtUrl,
                data: book.coverArtData,
                size: 50,
                cornerRadius: 8,
                fallbackIcon: "book.fill",
                fallbackColor: .royalPurple
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(chapterCountText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            GlassPlayButton(size: 28, color: .royalPurple, action: onPlay)
        }
        .padding(12)
        .glassCard()
    }
    
    var chapterCountText: String {
        if let librivoxChapters = book.librivoxChapters, !librivoxChapters.isEmpty {
            return "\(book.chapters.count) of \(librivoxChapters.count) chapters"
        } else {
            return "\(book.chapters.count) chapter\(book.chapters.count == 1 ? "" : "s")"
        }
    }
}
