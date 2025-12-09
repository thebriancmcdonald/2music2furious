//
//  PodcastSearchView.swift
//  2 Music 2 Furious - MILESTONE 11
//
//  Podcast search and download - Uses SharedComponents for consistency
//

import SwiftUI
import UniformTypeIdentifiers

// Sort Enum
enum DownloadSortOption: String, CaseIterable {
    case date = "Date"
    case name = "Name"
}

// MARK: - Main Podcast View

struct PodcastSearchView: View {
    @ObservedObject var searchManager: PodcastSearchManager
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    let dismiss: () -> Void
    
    @State private var showingFilePicker = false
    @State private var showingSearch = false
    @State private var showingFavorites = false
    @State private var showingPodcastEpisodes: Podcast?
    
    // Sort State
    @State private var sortOption: DownloadSortOption = .date
    @State private var sortAscending = false
    
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    var sortedDownloads: [String] {
        let downloads = downloadManager.downloadedEpisodes
        switch sortOption {
        case .date:
            return sortAscending ? downloads : downloads.reversed()
        case .name:
            let sorted = downloads.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return sortAscending ? sorted : sorted.reversed()
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                
                List {
                    // SECTION 1: FAVORITES
                    if !searchManager.favoritePodcasts.isEmpty {
                        FavoritesCarousel(
                            title: "Favorites",
                            items: searchManager.favoritePodcasts,
                            onSeeAll: { showingFavorites = true }
                        ) { podcast in
                            CarouselItemView(
                                title: podcast.title,
                                artworkURL: URL(string: podcast.artworkUrl),
                                size: 70,
                                fallbackIcon: "mic.fill",
                                fallbackColor: .royalPurple
                            ) {
                                searchManager.loadEpisodes(for: podcast)
                                showingPodcastEpisodes = podcast
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    
                    // SECTION 2: DOWNLOADS HEADER
                    HStack(alignment: .firstTextBaseline) {
                        GlassSectionHeader(
                            title: "Downloaded",
                            count: downloadManager.downloadedEpisodes.isEmpty ? nil : downloadManager.downloadedEpisodes.count
                        )
                        
                        Spacer()
                        
                        Menu {
                            Picker("Sort By", selection: $sortOption) {
                                Label("Date Added", systemImage: "calendar").tag(DownloadSortOption.date)
                                Label("Name", systemImage: "textformat").tag(DownloadSortOption.name)
                            }
                            
                            Button(action: { sortAscending.toggle() }) {
                                Label(sortAscending ? "Ascending" : "Descending",
                                      systemImage: sortAscending ? "arrow.up" : "arrow.down")
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)
                                .foregroundColor(.primary)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    
                    // SECTION 3: DOWNLOADS LIST OR EMPTY STATE
                    if downloadManager.downloadedEpisodes.isEmpty {
                        GlassEmptyStateView(
                            icon: "mic.fill",
                            title: "No downloads yet",
                            subtitle: "Import files from your device or\nsearch for new podcasts.",
                            actions: [
                                (icon: "square.and.arrow.up", title: "Upload Files", action: { showingFilePicker = true }),
                                (icon: "magnifyingglass", title: "Search Podcasts", action: { showingSearch = true })
                            ]
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .frame(height: 400)
                    } else {
                        ForEach(sortedDownloads, id: \.self) { filename in
                            // UPDATED: Using refactored row
                            GlassDownloadedRow(
                                filename: filename,
                                searchManager: searchManager,
                                onPlay: { playEpisode(filename: filename) }
                            )
                            .glassListRowWide()
                            .swipeActions(edge: .trailing) {
                                Button {
                                    downloadManager.deleteEpisode(filename: filename)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.royalPurple)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .tint(.royalPurple)
                
                if showingToast {
                    VStack {
                        Spacer()
                        GlassToastView(message: toastMessage)
                            .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: showingToast)
                    .zIndex(100)
                }
            }
            .navigationTitle("Podcasts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(.white)
                    
                    Button(action: { showingSearch = true }) {
                        Image(systemName: "magnifyingglass")
                    }
                    .tint(.white)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleFileUpload(result: result)
            }
            .sheet(isPresented: $showingSearch) {
                PodcastSearchModal(
                    searchManager: searchManager,
                    downloadManager: downloadManager,
                    speechPlayer: speechPlayer,
                    dismiss: { showingSearch = false },
                    dismissAll: dismiss
                )
            }
            .sheet(isPresented: $showingFavorites) {
                FavoritesFullView(
                    searchManager: searchManager,
                    downloadManager: downloadManager,
                    speechPlayer: speechPlayer,
                    dismiss: { showingFavorites = false },
                    dismissAll: dismiss
                )
            }
            .sheet(item: $showingPodcastEpisodes) { podcast in
                PodcastEpisodesSheet(
                    podcast: podcast,
                    searchManager: searchManager,
                    downloadManager: downloadManager,
                    speechPlayer: speechPlayer,
                    dismiss: { showingPodcastEpisodes = nil },
                    dismissAll: dismiss
                )
            }
        }
        .accentColor(.royalPurple)
    }
    
    private func handleFileUpload(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var addedCount = 0
            for url in urls {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let filename = url.lastPathComponent
                    let destinationURL = documentsPath.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    if !downloadManager.downloadedEpisodes.contains(filename) {
                        downloadManager.downloadedEpisodes.append(filename)
                    }
                    addedCount += 1
                }
            }
            UserDefaults.standard.set(downloadManager.downloadedEpisodes, forKey: "downloadedEpisodes")
            if addedCount > 0 {
                showToast("Added \(addedCount) file\(addedCount == 1 ? "" : "s")")
            }
        } catch {
            showToast("Upload failed")
        }
    }
    
    private func playEpisode(filename: String) {
        let cleanTitle = filename
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: "_", with: " ")
        let track = Track(title: cleanTitle, artist: "Podcast", filename: filename)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        speechPlayer.playNow(track)
        dismiss()
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showingToast = false }
        }
    }
}

// MARK: - Glass Downloaded Episode Row

struct GlassDownloadedRow: View {
    let filename: String
    @ObservedObject var searchManager: PodcastSearchManager
    let onPlay: () -> Void
    
    var podcastName: String {
        let cleanName = filename.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".m4a", with: "")
        let components = cleanName.components(separatedBy: "_")
        return components.first ?? "Unknown Podcast"
    }
    
    var episodeName: String {
        let cleanName = filename.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".m4a", with: "")
        let components = cleanName.components(separatedBy: "_")
        if components.count > 1 {
            return components.dropFirst().joined(separator: " ")
        }
        return cleanName
    }
    
    var artworkUrl: URL? {
        if let match = searchManager.favoritePodcasts.first(where: { $0.title == podcastName }) {
            return URL(string: match.artworkUrl)
        }
        return nil
    }
    
    var body: some View {
        // UPDATED: Whole row is now a button
        Button(action: onPlay) {
            HStack(spacing: 16) {
                MediaArtworkView(
                    url: artworkUrl,
                    size: 50,
                    cornerRadius: 10,
                    fallbackIcon: "mic.fill",
                    fallbackColor: .royalPurple
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(episodeName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(podcastName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Visual Play Indicator (Non-Interactive)
                ZStack {
                    Circle()
                        .fill(Color(white: 0.3))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .offset(x: 1)
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(PlainButtonStyle()) // Prevents flashing box style
    }
}

// MARK: - Podcast Search Modal

struct PodcastSearchModal: View {
    @ObservedObject var searchManager: PodcastSearchManager
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    let dismiss: () -> Void
    let dismissAll: () -> Void
    
    @State private var searchText = ""
    @State var selectedPodcast: Podcast?
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                
                VStack(spacing: 0) {
                    if let podcast = selectedPodcast {
                        EpisodesBrowseView(
                            podcast: podcast,
                            episodes: searchManager.episodes,
                            isLoading: searchManager.isLoadingEpisodes,
                            downloadManager: downloadManager,
                            speechPlayer: speechPlayer,
                            searchManager: searchManager,
                            onBack: { selectedPodcast = nil },
                            onDismiss: dismissAll
                        )
                    } else {
                        // Search Bar
                        GlassSearchBar(
                            text: $searchText,
                            placeholder: "Search podcasts...",
                            onCommit: { searchManager.searchPodcasts(query: searchText) }
                        )
                        .padding()
                        
                        if searchManager.isSearching {
                            Spacer(); ProgressView("Searching..."); Spacer()
                        } else if searchManager.searchResults.isEmpty && !searchText.isEmpty {
                            Spacer(); Text("No results found").foregroundColor(.gray); Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(searchManager.searchResults) { podcast in
                                        // Using Shared Component
                                        GlassMediaListRow(
                                            title: podcast.title,
                                            subtitle: podcast.author,
                                            artworkURL: URL(string: podcast.artworkUrl),
                                            artworkIcon: "mic.fill",
                                            artworkColor: .royalPurple,
                                            isFavorite: searchManager.isFavorite(podcast),
                                            onFavoriteToggle: { searchManager.toggleFavorite(podcast) }
                                        )
                                        .onTapGesture {
                                            selectedPodcast = podcast
                                            searchManager.loadEpisodes(for: podcast)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
            }
        }
    }
}

// MARK: - Podcast Episodes Sheet

struct PodcastEpisodesSheet: View {
    let podcast: Podcast
    @ObservedObject var searchManager: PodcastSearchManager
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    let dismiss: () -> Void
    let dismissAll: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                EpisodesBrowseView(
                    podcast: podcast,
                    episodes: searchManager.episodes,
                    isLoading: searchManager.isLoadingEpisodes,
                    downloadManager: downloadManager,
                    speechPlayer: speechPlayer,
                    searchManager: searchManager,
                    onBack: nil,
                    onDismiss: dismissAll
                )
            }
            .navigationTitle("Episodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
            }
        }
    }
}

// MARK: - Episodes Browse View

struct EpisodesBrowseView: View {
    let podcast: Podcast
    let episodes: [Episode]
    let isLoading: Bool
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    @ObservedObject var searchManager: PodcastSearchManager
    let onBack: (() -> Void)?
    let onDismiss: () -> Void
    
    @State private var showDownloadedOnly = false
    @State var showingToast = false
    @State var toastMessage = ""
    
    var filteredEpisodes: [Episode] {
        showDownloadedOnly
            ? episodes.filter { downloadManager.isDownloaded(filename: filenameForEpisode($0)) }
            : episodes
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    VStack(spacing: 20) {
                        // Back Button
                        if let onBack = onBack {
                            HStack {
                                Button(action: onBack) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                        Text("Back")
                                    }
                                }
                                .foregroundColor(.royalPurple)
                                Spacer()
                            }
                        }
                        
                        // Header
                        MediaDetailHeader(
                            title: podcast.title,
                            subtitle: podcast.author,
                            artworkURL: URL(string: podcast.artworkUrl),
                            artworkIcon: "mic.fill",
                            artworkColor: .royalPurple,
                            isFavorite: searchManager.isFavorite(podcast),
                            onFavoriteToggle: { searchManager.toggleFavorite(podcast) }
                        )
                        
                        // Filter
                        GlassSegmentedFilter(
                            selection: $showDownloadedOnly,
                            options: [(false, "All"), (true, "Downloaded")],
                            color: .royalPurple
                        )
                    }
                    .padding(.bottom, 10)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 0, trailing: 16))
                
                // Loading State
                if isLoading {
                    Section {
                        HStack { Spacer(); ProgressView("Loading episodes..."); Spacer() }
                            .listRowBackground(Color.clear)
                    }
                } else if filteredEpisodes.isEmpty {
                    Section {
                        HStack { Spacer(); Text("No episodes found").foregroundColor(.secondary); Spacer() }
                            .listRowBackground(Color.clear)
                    }
                } else {
                    // Episode Rows
                    Section {
                        ForEach(filteredEpisodes) { episode in
                            // Using Shared Component
                            GlassDownloadRow(
                                title: episode.title,
                                subtitle: formatDuration(episode.duration),
                                isDownloaded: downloadManager.isDownloaded(filename: filenameForEpisode(episode)),
                                isDownloading: downloadManager.isDownloading(episodeId: episode.id.uuidString),
                                color: .royalPurple,
                                onDownload: { downloadEpisode(episode) },
                                onPlay: downloadManager.isDownloaded(filename: filenameForEpisode(episode)) ? { playEpisode(episode) } : nil
                            )
                            .glassListRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if downloadManager.isDownloaded(filename: filenameForEpisode(episode)) {
                                    Button {
                                        downloadManager.deleteEpisode(filename: filenameForEpisode(episode))
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.royalPurple)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            if showingToast {
                VStack {
                    Spacer()
                    GlassToastView(message: toastMessage, iconColor: .royalPurple)
                        .padding(.bottom, 20)
                }
                .zIndex(100)
            }
        }
    }
    
    private func filenameForEpisode(_ episode: Episode) -> String {
        "\(podcast.title)_\(episode.title).mp3"
            .components(separatedBy: CharacterSet(charactersIn: ":/\\?%*|\"<>"))
            .joined(separator: "_")
    }
    
    private func playEpisode(_ episode: Episode) {
        let filename = filenameForEpisode(episode)
        let track = Track(
            title: filename
                .replacingOccurrences(of: ".mp3", with: "")
                .replacingOccurrences(of: "_", with: " "),
            artist: podcast.title,
            filename: filename
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        speechPlayer.playNow(track)
        onDismiss()
    }
    
    private func downloadEpisode(_ episode: Episode) {
        if downloadManager.isDownloaded(filename: filenameForEpisode(episode)) {
            showToast("Already downloaded")
            return
        }
        downloadManager.downloadEpisode(episode, podcastTitle: podcast.title)
        showToast("Downloading...")
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showingToast = false }
        }
    }
    
    // Duration Helper
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
}

// MARK: - Favorites Full View

struct FavoritesFullView: View {
    @ObservedObject var searchManager: PodcastSearchManager
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    let dismiss: () -> Void
    let dismissAll: () -> Void
    
    @State private var selectedPodcast: Podcast?
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                VStack {
                    if let podcast = selectedPodcast {
                        EpisodesBrowseView(
                            podcast: podcast,
                            episodes: searchManager.episodes,
                            isLoading: searchManager.isLoadingEpisodes,
                            downloadManager: downloadManager,
                            speechPlayer: speechPlayer,
                            searchManager: searchManager,
                            onBack: { selectedPodcast = nil },
                            onDismiss: dismissAll
                        )
                    } else if searchManager.favoritePodcasts.isEmpty {
                        Spacer()
                        Text("No favorites yet").foregroundColor(.gray)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(searchManager.favoritePodcasts) { podcast in
                                    // Using Shared Component
                                    GlassMediaListRow(
                                        title: podcast.title,
                                        subtitle: podcast.author,
                                        artworkURL: URL(string: podcast.artworkUrl),
                                        artworkIcon: "mic.fill",
                                        artworkColor: .royalPurple,
                                        isFavorite: searchManager.isFavorite(podcast),
                                        onFavoriteToggle: { searchManager.toggleFavorite(podcast) }
                                    )
                                    .onTapGesture {
                                        selectedPodcast = podcast
                                        searchManager.loadEpisodes(for: podcast)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
            }
        }
    }
}
