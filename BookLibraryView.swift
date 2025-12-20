//
//  BookLibraryView.swift
//  2 Music 2 Furious - MILESTONE 14.5
//
//  Audiobook library - Uses SharedComponents for consistency
//  UPDATED: Added Played Status Tracking via GlassEpisodeRow
//

import SwiftUI
import UniformTypeIdentifiers

struct BookLibraryView: View {
    @ObservedObject var bookManager: BookManager
    @ObservedObject var speechPlayer: AudioPlayer
    let dismiss: () -> Void
    
    @State private var showingFilePicker = false
    @State private var showingLibriVox = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                
                if bookManager.books.isEmpty {
                    GlassEmptyStateView(
                        icon: "books.vertical",
                        title: "Your Library is Empty",
                        subtitle: "Import files from your device or\nsearch the public domain.",
                        actions: [
                            (icon: "square.and.arrow.up", title: "Upload Files", action: { showingFilePicker = true }),
                            (icon: "magnifyingglass", title: "Search LibriVox", action: { showingLibriVox = true })
                        ]
                    )
                } else {
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
                
                if showingToast {
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
                    
                    Button { showingLibriVox = true } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white)
                    }
                }
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                handleFileUpload(result: result)
            }
            .sheet(isPresented: $showingLibriVox) {
                LibriVoxSearchView(bookManager: bookManager, dismiss: { showingLibriVox = false })
            }
        }
        .accentColor(.royalPurple)
        .tint(.royalPurple)
    }
    
    private func handleFileUpload(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var uploadedTracks: [Track] = []
            for url in urls {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let filename = url.lastPathComponent
                    let destinationURL = documentsPath.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: destinationURL.path) { try FileManager.default.removeItem(at: destinationURL) }
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    let title = filename.replacingOccurrences(of: "_", with: " ").components(separatedBy: ".").dropLast().joined(separator: ".")
                    let track = Track(title: title, artist: "Audiobook", filename: filename)
                    uploadedTracks.append(track)
                }
            }
            if !uploadedTracks.isEmpty {
                let newBooks = bookManager.processUploadedTracks(uploadedTracks)
                for book in newBooks { bookManager.addBook(book) }
                showToast("Added \(newBooks.count) audiobook(s)")
            }
        } catch { print("Upload error: \(error)"); showToast("Upload failed") }
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
    
    var chaptersToDisplay: [DisplayChapter] {
        if filter == .downloaded {
            return book.chapters.enumerated().map { (index, track) in
                let duration = bookManager.getTrackDuration(track: track)
                // Use filename as a stable ID for local files
                return DisplayChapter(index: index, title: track.title, isDownloaded: true, filename: track.filename, remoteChapter: nil, duration: duration, uniqueId: track.filename)
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
        let uniqueId: String // Stable ID for tracking played status
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
                            tertiaryText: "\(book.chapters.count) of \(book.librivoxChapters?.count ?? book.chapters.count) Downloaded",
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
                        
                        GlassSegmentedFilter(
                            selection: $filter,
                            options: FilterOption.allCases.map { ($0, $0.rawValue) },
                            color: .royalPurple
                        )
                    }
                    .padding(.bottom, 10)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                
                Section {
                    ForEach(chaptersToDisplay) { chapter in
                        let isPlayed = bookManager.isPlayed(chapterId: chapter.uniqueId)
                        
                        // UPDATED: Use Shared GlassEpisodeRow
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
                                if let filename = chapter.filename, let realIndex = book.chapters.firstIndex(where: { $0.filename == filename }) {
                                    onPlayChapter(realIndex)
                                    // Optional: Auto-mark as played?
                                    // bookManager.togglePlayed(chapterId: chapter.uniqueId)
                                }
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if chapter.isDownloaded, let filename = chapter.filename {
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
            bookManager.preloadDurations(for: book)
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
                Text("\(book.chapters.count) of \(book.librivoxChapters?.count ?? book.chapters.count) chapters")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            GlassPlayButton(size: 28, color: .royalPurple, action: onPlay)
        }
        .padding(12)
        .glassCard()
    }
}
