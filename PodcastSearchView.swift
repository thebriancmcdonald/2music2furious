//
//  PodcastSearchView.swift
//  2 Music 2 Furious - MILESTONE 14
//
//  Podcast search and download
//  UPDATED: Uses shared GlassEpisodeRow for standardized "Played" tracking
//  UPDATED: Added Drag-to-Reorder for Favorites
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Navigation Destinations

enum PodcastNavDestination: Hashable {
    case search
    case favorites
    case podcastDetail(Podcast)
}

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
    
    // Navigation State
    @State private var navigationPath = NavigationPath()
    
    // File picker stays as system modal
    @State private var showingFilePicker = false
    
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
        NavigationStack(path: $navigationPath) {
            ZStack {
                GlassBackgroundView()
                
                List {
                    // SECTION 1: FAVORITES
                    if !searchManager.favoritePodcasts.isEmpty {
                        FavoritesCarousel(
                            title: "Favorites",
                            items: searchManager.favoritePodcasts,
                            onSeeAll: { navigationPath.append(PodcastNavDestination.favorites) }
                        ) { podcast in
                            CarouselItemView(
                                title: podcast.title,
                                artworkURL: URL(string: podcast.artworkUrl),
                                size: 70,
                                fallbackIcon: "mic.fill",
                                fallbackColor: .royalPurple
                            ) {
                                searchManager.loadEpisodes(for: podcast)
                                navigationPath.append(PodcastNavDestination.podcastDetail(podcast))
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
                                (icon: "magnifyingglass", title: "Search Podcasts", action: { navigationPath.append(PodcastNavDestination.search) })
                            ]
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .frame(height: 400)
                    } else {
                        ForEach(sortedDownloads, id: \.self) { filename in
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
                    
                    Button(action: { navigationPath.append(PodcastNavDestination.search) }) {
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
            // MARK: - Navigation Destinations
            .navigationDestination(for: PodcastNavDestination.self) { destination in
                switch destination {
                case .search:
                    PodcastSearchDestination(
                        searchManager: searchManager,
                        downloadManager: downloadManager,
                        speechPlayer: speechPlayer,
                        navigationPath: $navigationPath,
                        dismissAll: dismiss
                    )
                case .favorites:
                    FavoritesDestination(
                        searchManager: searchManager,
                        downloadManager: downloadManager,
                        speechPlayer: speechPlayer,
                        navigationPath: $navigationPath,
                        dismissAll: dismiss
                    )
                case .podcastDetail(let podcast):
                    PodcastDetailDestination(
                        podcast: podcast,
                        searchManager: searchManager,
                        downloadManager: downloadManager,
                        speechPlayer: speechPlayer,
                        dismissAll: dismiss
                    )
                }
            }
        }
        .accentColor(.royalPurple)
        .onAppear {
            searchManager.loadIfNeeded()
        }
    }
    
    // MARK: - Actions
    
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
        let nameWithoutExt = filename
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
        
        var podcastName = "Podcast"
        var episodeTitle = nameWithoutExt
        var artworkUrl: URL? = nil
        
        for favorite in searchManager.favoritePodcasts {
            let podcastPrefix = favorite.title + "_"
            if nameWithoutExt.hasPrefix(podcastPrefix) {
                podcastName = favorite.title
                episodeTitle = String(nameWithoutExt.dropFirst(podcastPrefix.count))
                artworkUrl = URL(string: favorite.artworkUrl)
                break
            }
        }
        
        if podcastName == "Podcast", let underscoreIndex = nameWithoutExt.firstIndex(of: "_") {
            podcastName = String(nameWithoutExt[..<underscoreIndex])
            episodeTitle = String(nameWithoutExt[nameWithoutExt.index(after: underscoreIndex)...])
        }
        
        let track = Track(title: episodeTitle, artist: podcastName, filename: filename)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        speechPlayer.playNow(track, artworkURL: artworkUrl)
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

// MARK: - Glass Downloaded Episode Row (Unchanged)
struct GlassDownloadedRow: View {
    let filename: String
    @ObservedObject var searchManager: PodcastSearchManager
    let onPlay: () -> Void
    
    var podcastName: String {
        let cleanName = filename.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".m4a", with: "")
        for favorite in searchManager.favoritePodcasts {
            let podcastPrefix = favorite.title + "_"
            if cleanName.hasPrefix(podcastPrefix) { return favorite.title }
        }
        if let underscoreIndex = cleanName.firstIndex(of: "_") {
            return String(cleanName[..<underscoreIndex])
        }
        return "Unknown Podcast"
    }
    
    var episodeName: String {
        let cleanName = filename.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".m4a", with: "")
        for favorite in searchManager.favoritePodcasts {
            let podcastPrefix = favorite.title + "_"
            if cleanName.hasPrefix(podcastPrefix) { return String(cleanName.dropFirst(podcastPrefix.count)) }
        }
        if let underscoreIndex = cleanName.firstIndex(of: "_") {
            return String(cleanName[cleanName.index(after: underscoreIndex)...])
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
        Button(action: onPlay) {
            HStack(spacing: 16) {
                MediaArtworkView(
                    url: artworkUrl, size: 50, cornerRadius: 10,
                    fallbackIcon: "mic.fill", fallbackColor: .royalPurple
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(episodeName).font(.system(size: 15, weight: .medium)).foregroundColor(.primary).lineLimit(2).multilineTextAlignment(.leading)
                    Text(podcastName).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                ZStack {
                    Circle().fill(Color(white: 0.3)).frame(width: 28, height: 28)
                    Image(systemName: "play.fill").font(.system(size: 12)).foregroundColor(.white).offset(x: 1)
                }
            }.padding(12).glassCard(cornerRadius: 16)
        }.buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Search Destination

struct PodcastSearchDestination: View {
    @ObservedObject var searchManager: PodcastSearchManager
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    @Binding var navigationPath: NavigationPath
    let dismissAll: () -> Void
    
    @State private var searchText = ""
    
    var body: some View {
        ZStack {
            GlassBackgroundView()
            VStack(spacing: 0) {
                GlassSearchBar(text: $searchText, placeholder: "Search podcasts...", onCommit: { searchManager.searchPodcasts(query: searchText) }).padding()
                if searchManager.isSearching {
                    Spacer(); ProgressView("Searching..."); Spacer()
                } else if searchManager.searchResults.isEmpty && !searchText.isEmpty {
                    Spacer(); Text("No results found").foregroundColor(.gray); Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(searchManager.searchResults) { podcast in
                                GlassMediaListRow(
                                    title: podcast.title, subtitle: podcast.author,
                                    artworkURL: URL(string: podcast.artworkUrl), artworkIcon: "mic.fill", artworkColor: .royalPurple,
                                    isFavorite: searchManager.isFavorite(podcast), onFavoriteToggle: { searchManager.toggleFavorite(podcast) }
                                ).onTapGesture {
                                    searchManager.loadEpisodes(for: podcast)
                                    navigationPath.append(PodcastNavDestination.podcastDetail(podcast))
                                }
                            }
                        }.padding(.horizontal)
                    }
                }
            }
        }.navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Favorites Destination (With Drag Reorder)

struct FavoritesDestination: View {
    @ObservedObject var searchManager: PodcastSearchManager
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    @Binding var navigationPath: NavigationPath
    let dismissAll: () -> Void
    
    var body: some View {
        ZStack {
            GlassBackgroundView()
            if searchManager.favoritePodcasts.isEmpty {
                VStack { Spacer(); Text("No favorites yet").foregroundColor(.gray); Spacer() }
            } else {
                List {
                    ForEach(searchManager.favoritePodcasts) { podcast in
                        GlassMediaListRow(
                            title: podcast.title, subtitle: podcast.author,
                            artworkURL: URL(string: podcast.artworkUrl), artworkIcon: "mic.fill", artworkColor: .royalPurple,
                            isFavorite: searchManager.isFavorite(podcast), onFavoriteToggle: { searchManager.toggleFavorite(podcast) }
                        )
                        .onTapGesture {
                            searchManager.loadEpisodes(for: podcast)
                            navigationPath.append(PodcastNavDestination.podcastDetail(podcast))
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onMove(perform: moveFavorites)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
    }
    
    private func moveFavorites(from source: IndexSet, to destination: Int) {
        searchManager.favoritePodcasts.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Podcast Detail Destination

struct PodcastDetailDestination: View {
    let podcast: Podcast
    @ObservedObject var searchManager: PodcastSearchManager
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    let dismissAll: () -> Void
    
    @State private var showDownloadedOnly = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    var filteredEpisodes: [Episode] {
        showDownloadedOnly
            ? searchManager.episodes.filter { downloadManager.isDownloaded(filename: filenameForEpisode($0)) }
            : searchManager.episodes
    }
    
    var body: some View {
        ZStack {
            GlassBackgroundView()
            
            List {
                Section {
                    VStack(spacing: 20) {
                        MediaDetailHeader(
                            title: podcast.title, subtitle: podcast.author,
                            artworkURL: URL(string: podcast.artworkUrl), artworkIcon: "mic.fill", artworkColor: .royalPurple,
                            isFavorite: searchManager.isFavorite(podcast), onFavoriteToggle: { searchManager.toggleFavorite(podcast) }
                        )
                        GlassSegmentedFilter(
                            selection: $showDownloadedOnly,
                            options: [(false, "All"), (true, "Downloaded")],
                            color: .royalPurple
                        )
                    }.padding(.bottom, 10)
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 0, trailing: 16))
                
                if searchManager.isLoadingEpisodes {
                    Section { HStack { Spacer(); ProgressView("Loading episodes..."); Spacer() }.listRowBackground(Color.clear) }
                } else if filteredEpisodes.isEmpty {
                    Section { HStack { Spacer(); Text("No episodes found").foregroundColor(.secondary); Spacer() }.listRowBackground(Color.clear) }
                } else {
                    Section {
                        ForEach(filteredEpisodes) { episode in
                            let isPlayed = searchManager.isPlayed(episode)
                            
                            // UPDATED: Using Shared GlassEpisodeRow
                            GlassEpisodeRow(
                                title: episode.title,
                                duration: formatDuration(episode.duration),
                                isPlayed: isPlayed,
                                isDownloaded: downloadManager.isDownloaded(filename: filenameForEpisode(episode)),
                                isDownloading: downloadManager.isDownloading(episodeId: episode.id.uuidString),
                                downloadColor: .royalPurple,
                                onDownload: { downloadEpisode(episode) },
                                onPlay: downloadManager.isDownloaded(filename: filenameForEpisode(episode)) ? { playEpisode(episode) } : nil
                            )
                            .glassListRow()
                            .swipeActions(edge: .leading) {
                                Button {
                                    searchManager.togglePlayed(episode)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Label(isPlayed ? "Unmark" : "Played", systemImage: isPlayed ? "eye.slash" : "eye")
                                }.tint(.orange)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if downloadManager.isDownloaded(filename: filenameForEpisode(episode)) {
                                    Button {
                                        downloadManager.deleteEpisode(filename: filenameForEpisode(episode))
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }.tint(.royalPurple)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            
            if showingToast {
                VStack { Spacer(); GlassToastView(message: toastMessage, iconColor: .royalPurple).padding(.bottom, 20) }.zIndex(100)
            }
        }.navigationTitle("Episodes").navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Helpers
    
    private func filenameForEpisode(_ episode: Episode) -> String {
        "\(podcast.title)_\(episode.title).mp3"
            .components(separatedBy: CharacterSet(charactersIn: ":/\\?%*|\"<>"))
            .joined(separator: "_")
    }
    
    private func playEpisode(_ episode: Episode) {
        let filename = filenameForEpisode(episode)
        let track = Track(
            title: filename.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: "_", with: " "),
            artist: podcast.title,
            filename: filename
        )
        var artworkUrl: URL? = nil
        if let url = URL(string: podcast.artworkUrl) { artworkUrl = url }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        speechPlayer.playNow(track, artworkURL: artworkUrl)
        dismissAll()
    }
    
    private func downloadEpisode(_ episode: Episode) {
        if downloadManager.isDownloaded(filename: filenameForEpisode(episode)) { showToast("Already downloaded"); return }
        downloadManager.downloadEpisode(episode, podcastTitle: podcast.title)
        showToast("Downloading...")
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showingToast = false } }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
}
