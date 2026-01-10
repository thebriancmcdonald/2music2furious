//
//  BookLibraryView.swift
//  2 Music 2 Furious - MILESTONE 15
//
//  Audiobook library - Uses SharedComponents for consistency
//  UPDATED: Smart Resume - remembers exact position within chapters
//  UPDATED: Auto-mark played when chapter completes (≥95%)
//  UPDATED: Bulk "Mark All Played/Unplayed" options
//  UPDATED: Shows played progress in chapter list
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Combine

// MARK: - Supported Audiobook File Types

func buildSupportedAudioTypes() -> [UTType] {
    var types: [UTType] = [
        .audio,
        .mp3,
        .mpeg4Audio,
        .wav,
        .aiff,
    ]
    
    let m4bTypes = UTType.types(tag: "m4b", tagClass: .filenameExtension, conformingTo: .audio)
    types.append(contentsOf: m4bTypes)
    
    if let m4bApple = UTType("com.apple.m4b-audio") { types.append(m4bApple) }
    if let m4bAlt = UTType("public.m4b-audio") { types.append(m4bAlt) }
    if let m4bExt = UTType(filenameExtension: "m4b") { types.append(m4bExt) }
    if let mpeg4 = UTType("public.mpeg-4") { types.append(mpeg4) }
    if let mpeg4Audio = UTType("public.mpeg-4-audio") { types.append(mpeg4Audio) }
    
    let otherExtensions = ["aac", "flac", "ogg", "opus"]
    for ext in otherExtensions {
        if let type = UTType(filenameExtension: ext) { types.append(type) }
        types.append(contentsOf: UTType.types(tag: ext, tagClass: .filenameExtension, conformingTo: .audio))
    }
    
    var seen = Set<UTType>()
    return types.filter { seen.insert($0).inserted }
}

let supportedAudiobookTypes: [UTType] = buildSupportedAudioTypes()

// MARK: - M4B Chapter Reader

struct M4BChapterReader {
    
    struct ChapterInfo {
        let title: String
        let startTime: Double
        let endTime: Double
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
    
    static func readChapterMetadata(from url: URL) async throws -> (chapters: [ChapterInfo], title: String?, author: String?, artwork: Data?) {
        let asset = AVURLAsset(url: url)
        let metadata = try await asset.load(.commonMetadata)
        let duration = try await asset.load(.duration)
        let fileDuration = CMTimeGetSeconds(duration)
        
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
                
                chapters.append(ChapterInfo(title: chapterTitle, startTime: startTime, endTime: endTime, index: index))
            }
        }
        
        if chapters.isEmpty {
            if var mp4Chapters = MP4ChapterParser.parseChapters(from: url) {
                MP4ChapterParser.updateLastChapterEndTime(chapters: &mp4Chapters, fileDuration: fileDuration)
                chapters = mp4Chapters.map { ChapterInfo(title: $0.title, startTime: $0.startTime, endTime: $0.endTime, index: $0.index) }
            }
        }
        
        if chapters.isEmpty {
            chapters.append(ChapterInfo(title: title ?? "Full Audiobook", startTime: 0, endTime: fileDuration, index: 0))
        }
        
        return (chapters, title, author, artwork)
    }
    
    static func hasChapters(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let locales = try await asset.load(.availableChapterLocales)
            if !locales.isEmpty { return true }
        } catch {}
        
        if let chapters = MP4ChapterParser.parseChapters(from: url), !chapters.isEmpty {
            return true
        }
        return false
    }
}

// MARK: - M4B Import State

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
                                NavigationLink(destination: LocalBookDetailView(
                                    book: book,
                                    bookManager: bookManager,
                                    onPlayChapter: { index in playBook(book, startingAt: index) },
                                    onResume: { resumeBook(book) }
                                )) { EmptyView() }.opacity(0)
                                GlassBookRow(book: book, bookManager: bookManager, onPlay: { resumeBook(book) })
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
                        Image(systemName: "square.and.arrow.up").foregroundColor(.white)
                    }.disabled(m4bImportState.isProcessing)
                    
                    Button { showingLibriVox = true } label: {
                        Image(systemName: "magnifyingglass").foregroundColor(.white)
                    }.disabled(m4bImportState.isProcessing)
                }
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                handleFileUpload(result: result)
            }
            .sheet(isPresented: $showingLibriVox) {
                LibriVoxSearchView(bookManager: bookManager, dismiss: { showingLibriVox = false })
            }
        }
        .accentColor(.royalPurple)
        .tint(.royalPurple)
    }
    
    private let supportedExtensions = Set(["mp3", "m4a", "m4b", "wav", "aiff", "aac", "flac", "ogg", "opus", "mp4", "aif"])
    
    private func handleFileUpload(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let audioURLs = urls.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            guard !audioURLs.isEmpty else { showToast("No supported audio files"); return }
            
            var m4bURLs: [URL] = []
            var regularURLs: [URL] = []
            
            for url in audioURLs {
                let ext = url.pathExtension.lowercased()
                if ext == "m4b" || ext == "m4a" { m4bURLs.append(url) }
                else { regularURLs.append(url) }
            }
            
            if !regularURLs.isEmpty { processRegularAudioFiles(regularURLs) }
            if !m4bURLs.isEmpty { Task { await processM4BFiles(m4bURLs) } }
        } catch {
            showToast("Upload failed")
        }
    }
    
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
                    let title = filename.replacingOccurrences(of: "_", with: " ").components(separatedBy: ".").dropLast().joined(separator: ".")
                    uploadedTracks.append(Track(title: title, artist: "Audiobook", filename: filename))
                } catch {}
            }
        }
        if !uploadedTracks.isEmpty {
            let newBooks = bookManager.processUploadedTracks(uploadedTracks)
            for book in newBooks { bookManager.addBook(book) }
            showToast("Added \(newBooks.count) audiobook(s)")
        }
    }
    
    @MainActor
    private func processM4BFiles(_ urls: [URL]) async {
        m4bImportState.isProcessing = true
        m4bImportState.statusMessage = "Reading audiobook metadata..."
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var totalBooksAdded = 0
        var totalChapters = 0
        
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            
            let filename = url.lastPathComponent
            let destinationURL = documentsPath.appendingPathComponent(filename)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)
                
                m4bImportState.statusMessage = "Reading chapters..."
                let hasChapters = await M4BChapterReader.hasChapters(url: destinationURL)
                
                if hasChapters {
                    let (chapters, title, author, artwork) = try await M4BChapterReader.readChapterMetadata(from: destinationURL)
                    let bookTitle = title ?? url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
                    let bookAuthor = author ?? "Unknown Author"
                    
                    var chapterTracks: [Track] = []
                    for chapter in chapters {
                        chapterTracks.append(Track(title: chapter.title, artist: bookAuthor, filename: filename, startTime: chapter.startTime, endTime: chapter.endTime))
                    }
                    
                    let newBook = Book(title: bookTitle, author: bookAuthor, description: nil, chapters: chapterTracks, librivoxChapters: nil, coverArtUrl: nil, coverArtData: artwork, currentChapterIndex: 0, lastPlayedPosition: 0, dateAdded: Date())
                    bookManager.addBook(newBook)
                    totalBooksAdded += 1
                    totalChapters += chapters.count
                } else {
                    let title = filename.replacingOccurrences(of: "_", with: " ").components(separatedBy: ".").dropLast().joined(separator: ".")
                    let track = Track(title: title, artist: "Audiobook", filename: filename)
                    let artData = extractArtwork(from: filename)
                    let newBook = Book(title: title, author: nil, description: nil, chapters: [track], coverArtData: artData, dateAdded: Date())
                    bookManager.addBook(newBook)
                    totalBooksAdded += 1
                    totalChapters += 1
                }
            } catch {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }
        
        m4bImportState.isProcessing = false
        if totalBooksAdded > 0 {
            showToast(totalChapters > 1 ? "Added \(totalBooksAdded) book(s) with \(totalChapters) chapters" : "Added \(totalBooksAdded) audiobook(s)")
        }
    }
    
    private func extractArtwork(from filename: String) -> Data? {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        let asset = AVURLAsset(url: fileURL)
        for item in asset.commonMetadata {
            if item.commonKey == .commonKeyArtwork, let data = item.dataValue { return data }
        }
        return nil
    }
    
    /// Play a book starting at a specific chapter
    private func playBook(_ book: Book, startingAt index: Int) {
        bookManager.startPlayingBook(book, at: index)
        speechPlayer.setExternalArtwork(from: book.coverArtUrl)
        speechPlayer.clearQueue()
        for chapter in book.chapters { speechPlayer.addTrackToQueue(chapter) }
        if speechPlayer.queue.count > 0 {
            let safeIndex = min(max(0, index), speechPlayer.queue.count - 1)
            speechPlayer.playFromQueue(at: safeIndex)
        }
        dismiss()
    }
    
    /// Resume a book from saved position
    private func resumeBook(_ book: Book) {
        let (chapterIndex, position) = bookManager.getResumeInfo(for: book)
        bookManager.startPlayingBook(book, at: chapterIndex)
        speechPlayer.setExternalArtwork(from: book.coverArtUrl)
        speechPlayer.clearQueue()
        for chapter in book.chapters { speechPlayer.addTrackToQueue(chapter) }
        if speechPlayer.queue.count > 0 {
            let safeIndex = min(max(0, chapterIndex), speechPlayer.queue.count - 1)
            speechPlayer.playFromQueue(at: safeIndex)
            if position > 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    speechPlayer.seek(to: position)
                }
            }
        }
        dismiss()
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { showingToast = false } }
    }
}

// MARK: - M4B Processing Overlay

struct M4BQuickProcessingOverlay: View {
    @ObservedObject var state: M4BImportState
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.5).tint(.white)
                Text(state.statusMessage).font(.subheadline).foregroundColor(.white)
            }
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        }
    }
}

// MARK: - Local Book Detail View

struct LocalBookDetailView: View {
    let book: Book
    @ObservedObject var bookManager: BookManager
    @ObservedObject var downloadManager = LibriVoxDownloadManager.shared
    
    let onPlayChapter: (Int) -> Void
    let onResume: () -> Void
    
    @State private var filter: FilterOption = .downloaded
    @State private var toastMessage = ""
    @State private var showingToast = false
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case downloaded = "Downloaded"
    }
    
    var showFilter: Bool {
        book.librivoxChapters != nil && !(book.librivoxChapters?.isEmpty ?? true)
    }
    
    var currentBook: Book {
        bookManager.books.first(where: { $0.id == book.id }) ?? book
    }
    
    var chaptersToDisplay: [DisplayChapter] {
        if filter == .downloaded || !showFilter {
            return currentBook.chapters.enumerated().map { (index, track) in
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
                let uniqueId = track.hasChapterBoundaries ? track.id.uuidString : track.filename
                return DisplayChapter(index: index, title: track.title, isDownloaded: true, filename: track.filename, remoteChapter: nil, duration: duration, uniqueId: uniqueId)
            }
        } else {
            if let remote = currentBook.librivoxChapters, !remote.isEmpty {
                return remote.enumerated().map { (index, remoteChap) in
                    let targetIndex = index + 1
                    let match = currentBook.chapters.first { $0.filename.contains("Chapter_\(String(format: "%03d", targetIndex))_") }
                    return DisplayChapter(index: index, title: remoteChap.title, isDownloaded: match != nil, filename: match?.filename, remoteChapter: remoteChap, duration: remoteChap.formattedDuration, uniqueId: remoteChap.id)
                }
            } else {
                return currentBook.chapters.enumerated().map { (index, track) in
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
                            title: currentBook.displayTitle,
                            subtitle: currentBook.displayAuthor,
                            tertiaryText: chapterCountText,
                            artworkURL: currentBook.coverArtUrl,
                            artworkData: currentBook.coverArtData,
                            artworkIcon: "book.fill",
                            artworkColor: .royalPurple
                        )
                        
                        GlassActionButton(
                            title: resumeButtonTitle,
                            icon: "play.fill",
                            color: .deepResumePurple,
                            action: onResume
                        )
                        
                        if let desc = currentBook.description, !desc.isEmpty {
                            ExpandableDescriptionView(
                                text: desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
                                color: .royalPurple
                            ).tint(.royalPurple).accentColor(.royalPurple)
                        }
                        
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
                            isDownloading: chapter.remoteChapter != nil && downloadManager.isDownloading(bookId: currentBook.librivoxChapters?.first?.id ?? "", chapterId: chapter.remoteChapter!.id),
                            downloadColor: .royalPurple,
                            onDownload: {
                                if !chapter.isDownloaded, let remote = chapter.remoteChapter {
                                    downloadManager.downloadSingleChapter(
                                        chapter: remote,
                                        bookId: currentBook.title,
                                        bookTitle: currentBook.title,
                                        author: currentBook.displayAuthor,
                                        coverUrl: currentBook.coverArtUrl,
                                        description: currentBook.description,
                                        index: chapter.index,
                                        bookManager: bookManager,
                                        fullChapterList: currentBook.librivoxChapters
                                    )
                                    showToast("Downloading...")
                                }
                            },
                            onPlay: { onPlayChapter(chapter.index) }
                        )
                        .glassListRow()
                        .swipeActions(edge: .leading) {
                            Button {
                                bookManager.togglePlayed(chapterId: chapter.uniqueId)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label(isPlayed ? "Unmark" : "Played", systemImage: isPlayed ? "eye.slash" : "eye")
                            }.tint(.orange)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if chapter.isDownloaded && chapter.remoteChapter != nil, let filename = chapter.filename {
                                Button(role: .destructive) {
                                    bookManager.deleteChapterFile(filename: filename, from: currentBook)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        bookManager.markAllPlayed(for: currentBook)
                        showToast("Marked all as played")
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Label("Mark All Played", systemImage: "checkmark.circle.fill")
                    }
                    
                    Button {
                        bookManager.markAllUnplayed(for: currentBook)
                        showToast("Marked all as unplayed")
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Label("Mark All Unplayed", systemImage: "circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundColor(.white)
                }
            }
        }
        .onAppear {
            if let firstChapter = currentBook.chapters.first, !firstChapter.hasChapterBoundaries {
                bookManager.preloadDurations(for: currentBook)
            }
        }
    }
    
    var chapterCountText: String {
        let playedCount = bookManager.playedChapterCount(for: currentBook)
        let totalCount = currentBook.chapters.count
        if let librivoxChapters = currentBook.librivoxChapters, !librivoxChapters.isEmpty {
            return "\(currentBook.chapters.count) of \(librivoxChapters.count) Downloaded • \(playedCount) played"
        } else {
            return "\(playedCount) of \(totalCount) played"
        }
    }
    
    var resumeButtonTitle: String {
        let (chapterIndex, _) = bookManager.getResumeInfo(for: currentBook)
        if chapterIndex == 0 && currentBook.lastPlayedPosition < 5 {
            return "Play"
        } else {
            return "Resume Ch. \(chapterIndex + 1)"
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
    @ObservedObject var bookManager: BookManager
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
        let playedCount = bookManager.playedChapterCount(for: book)
        if let librivoxChapters = book.librivoxChapters, !librivoxChapters.isEmpty {
            return "\(book.chapters.count) of \(librivoxChapters.count) chapters • \(playedCount) played"
        } else {
            return "\(playedCount) of \(book.chapters.count) played"
        }
    }
}
