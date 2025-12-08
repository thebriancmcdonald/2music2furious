//
//  PodcastSearchView.swift
//  2 Music 2 Furious - MILESTONE 7.4
//
//  Layout: [X] ... [Upload] [Search]
//  Style: Apple Glass "Invisible UI"
//  Updates: Fixed missing subviews, Clean headers, Menu-based sorting
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
    @State private var sortAscending = false // Default: Newest first
    
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    // Sort Logic
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
                // 1. Background Gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // 2. Main List
                List {
                    // SECTION 1: FAVORITES (Horizontal Scroll)
                    if !searchManager.favoritePodcasts.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            // Clean Header
                            HStack {
                                Text("Favorites")
                                    .font(.title2.weight(.bold))
                                Spacer()
                                Button(action: { showingFavorites = true }) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(8)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.horizontal, 4)
                            
                            // Scrollable Row
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 16) {
                                    ForEach(searchManager.favoritePodcasts) { podcast in
                                        Button(action: {
                                            searchManager.loadEpisodes(for: podcast)
                                            showingPodcastEpisodes = podcast
                                        }) {
                                            VStack(spacing: 8) {
                                                AsyncImage(url: URL(string: podcast.artworkUrl)) { image in
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } placeholder: {
                                                    Color.gray.opacity(0.3)
                                                }
                                                .frame(width: 70, height: 70)
                                                .cornerRadius(16)
                                                .shadow(radius: 4)
                                                
                                                Text(podcast.title)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.center)
                                                    .frame(width: 70)
                                            }
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.bottom, 10)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    
                    // SECTION 2: DOWNLOADS HEADER
                    HStack(alignment: .firstTextBaseline) {
                        Text("Downloaded")
                            .font(.title2.weight(.bold))
                        
                        if !downloadManager.downloadedEpisodes.isEmpty {
                            Text("\(downloadManager.downloadedEpisodes.count)")
                                .font(.headline)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        // Clean Sort Menu
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
                    
                    // SECTION 3: DOWNLOADS LIST
                    if downloadManager.downloadedEpisodes.isEmpty {
                        emptyDownloadsView
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .frame(height: 300)
                    } else {
                        ForEach(sortedDownloads, id: \.self) { filename in
                            GlassDownloadedRow(
                                filename: filename,
                                searchManager: searchManager,
                                onPlay: { playEpisode(filename: filename) }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    downloadManager.deleteEpisode(filename: filename)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                
                // 3. Toast
                if showingToast {
                    VStack {
                        Spacer()
                        PodcastToastView(message: toastMessage)
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
                // Left: Clean X
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }

                // Right: Actions
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    
                    Button(action: { showingSearch = true }) {
                        Image(systemName: "magnifyingglass")
                    }
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
    }
    
    private var emptyDownloadsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
            }
            
            Text("No downloads yet")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Search for podcasts or upload files.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
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
        Button(action: onPlay) {
            HStack(spacing: 16) {
                if let url = artworkUrl {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 50, height: 50)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [.purple.opacity(0.3), .blue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 50, height: 50)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(episodeName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(podcastName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Glass Episode Download Row (Search/Browse)

struct GlassEpisodeDownloadRow: View {
    let episode: Episode
    let podcast: Podcast
    @ObservedObject var downloadManager: DownloadManager
    let onPlay: () -> Void
    let onDownload: () -> Void
    
    private var filename: String {
        "\(podcast.title)_\(episode.title).mp3"
            .components(separatedBy: CharacterSet(charactersIn: ":/\\?%*|\"<>"))
            .joined(separator: "_")
    }
    private var isDownloaded: Bool { downloadManager.isDownloaded(filename: filename) }
    private var isDownloading: Bool { downloadManager.isDownloading(episodeId: episode.id.uuidString) }
    
    var body: some View {
        HStack(spacing: 12) {
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
            } else if isDownloading {
                ProgressView()
                    .frame(width: 24, height: 24)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                
                Text(isDownloaded ? "Downloaded" : isDownloading ? "Downloading..." : "Tap arrow to download")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if isDownloaded {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
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
                LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                
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
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                            TextField("Search podcasts...", text: $searchText, onCommit: { searchManager.searchPodcasts(query: searchText) })
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                            }
                        }
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding()
                        
                        if searchManager.isSearching {
                            Spacer(); ProgressView("Searching..."); Spacer()
                        } else if searchManager.searchResults.isEmpty && !searchText.isEmpty {
                            Spacer(); Text("No results found").foregroundColor(.gray); Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(searchManager.searchResults) { podcast in
                                        GlassPodcastRow(podcast: podcast, searchManager: searchManager)
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
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                    }
                }
            }
        }
    }
}

// MARK: - Glass Podcast Row

struct GlassPodcastRow: View {
    let podcast: Podcast
    @ObservedObject var searchManager: PodcastSearchManager
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: podcast.artworkUrl)) { $0.resizable() } placeholder: { Color.gray }
                .frame(width: 56, height: 56).cornerRadius(8)
            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                Text(podcast.author).font(.system(size: 14)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: { searchManager.toggleFavorite(podcast) }) {
                Image(systemName: searchManager.isFavorite(podcast) ? "star.fill" : "star")
                    .foregroundColor(.orange).font(.system(size: 20))
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(12).background(.ultraThinMaterial).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
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
                LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
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
                    Button(action: { dismiss() }) { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary) }
                }
            }
        }
    }
}

// MARK: - Episodes Browse View (RESTORED)

struct EpisodesBrowseView: View {
    let podcast: Podcast
    let episodes: [Episode]
    let isLoading: Bool
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    @ObservedObject var searchManager: PodcastSearchManager
    let onBack: (() -> Void)? // Optional for sheet use
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
        VStack(spacing: 0) {
            // Back Button (Only if onBack exists)
            if let onBack = onBack {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    Spacer()
                }
                .padding()
            }
            
            // Header
            HStack(spacing: 16) {
                AsyncImage(url: URL(string: podcast.artworkUrl)) { $0.resizable() } placeholder: { Color.gray }
                    .frame(width: 80, height: 80)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(podcast.author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { searchManager.toggleFavorite(podcast) }) {
                    Image(systemName: searchManager.isFavorite(podcast) ? "star.fill" : "star")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                }
            }
            .padding()
            
            // Filter
            Picker("Filter", selection: $showDownloadedOnly) {
                Text("All").tag(false)
                Text("Downloaded").tag(true)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            if isLoading {
                Spacer()
                ProgressView("Loading episodes...")
                Spacer()
            } else if filteredEpisodes.isEmpty {
                Spacer()
                Text("No episodes found").foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEpisodes) { episode in
                            GlassEpisodeDownloadRow(
                                episode: episode,
                                podcast: podcast,
                                downloadManager: downloadManager,
                                onPlay: { playEpisode(episode) },
                                onDownload: { downloadEpisode(episode) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Toast
            if showingToast {
                PodcastToastView(message: toastMessage)
                    .padding(.bottom, 20)
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
                LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
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
                                    GlassPodcastRow(podcast: podcast, searchManager: searchManager)
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
                    Button(action: { dismiss() }) { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary) }
                }
            }
        }
    }
}

// MARK: - Toast View

struct PodcastToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text(message).font(.system(size: 14, weight: .medium)).foregroundColor(.white).lineLimit(1)
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(Capsule().fill(Color.black.opacity(0.85)).shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5))
    }
}
