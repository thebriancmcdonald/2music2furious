//
//  PodcastSearchView.swift
//  2 Music 2 Furious - MILESTONE 7.3
//
//  Layout: [Done] Podcasts [Upload] [Search]
//

import SwiftUI
import UniformTypeIdentifiers

// Updated Sort Enum
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
    
    // Updated Sort State
    @State private var sortOption: DownloadSortOption = .date
    @State private var sortAscending = false // Default to False (Newest first)
    
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    // Updated Sort Logic
    var sortedDownloads: [String] {
        let downloads = downloadManager.downloadedEpisodes
        switch sortOption {
        case .date:
            // Ascending = Oldest first; Descending = Newest first
            return sortAscending ? downloads : downloads.reversed()
        case .name:
            let sorted = downloads.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return sortAscending ? sorted : sorted.reversed()
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    if searchManager.favoritePodcasts.count > 0 {
                        favoritesSection
                    }
                    downloadedHeader
                    if downloadManager.downloadedEpisodes.isEmpty {
                        emptyDownloadsView
                    } else {
                        downloadedList
                    }
                }
                
                if showingToast {
                    VStack {
                        Spacer()
                        PodcastToastView(message: toastMessage)
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: showingToast)
                }
            }
            .navigationTitle("Podcasts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Left: Done Button
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                // Trailing: Upload button
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavCircleButton(systemName: "square.and.arrow.up") {
                        showingFilePicker = true
                    }
                }
                
                // Trailing: Search button
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavCircleButton(systemName: "magnifyingglass") {
                        showingSearch = true
                    }
                }
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
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
    
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 16))
                Text("Favorites")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { showingFavorites = true }) {
                    HStack(spacing: 4) {
                        Text("View All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(searchManager.favoritePodcasts) { podcast in
                        Button(action: {
                            searchManager.loadEpisodes(for: podcast)
                            showingPodcastEpisodes = podcast
                        }) {
                            VStack(spacing: 6) {
                                AsyncImage(url: URL(string: podcast.artworkUrl)) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 70, height: 70)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                                )
                                
                                Text(podcast.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 70, height: 30, alignment: .top)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
            Divider()
        }
    }
    
    private var downloadedHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                Text("Downloaded")
                    .font(.system(size: 16, weight: .semibold))
                if !downloadManager.downloadedEpisodes.isEmpty {
                    Text("(\(downloadManager.downloadedEpisodes.count))")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            if !downloadManager.downloadedEpisodes.isEmpty {
                HStack(spacing: 8) {
                    ForEach(DownloadSortOption.allCases, id: \.self) { option in
                        Button(action: {
                            if sortOption == option {
                                sortAscending.toggle()
                            } else {
                                sortOption = option
                                sortAscending = (option == .name)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(option.rawValue)
                                if sortOption == option {
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10))
                                }
                            }
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(sortOption == option ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(sortOption == option ? .white : .primary)
                            .cornerRadius(8)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var emptyDownloadsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No downloaded episodes")
                .font(.headline)
                .foregroundColor(.gray)
            Text("Search for podcasts and download episodes,\nor tap upload to add audio files")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: { showingSearch = true }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search Podcasts")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding(.top, 8)
            Spacer()
        }
    }
    
    private var downloadedList: some View {
        List {
            ForEach(sortedDownloads, id: \.self) { filename in
                DownloadedEpisodeRow(
                    filename: filename,
                    onPlay: { playEpisode(filename: filename) }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        downloadManager.deleteEpisode(filename: filename)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
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

// MARK: - Downloaded Episode Row

struct DownloadedEpisodeRow: View {
    let filename: String
    let onPlay: () -> Void
    
    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        filename
                            .replacingOccurrences(of: ".mp3", with: "")
                            .replacingOccurrences(of: ".m4a", with: "")
                            .replacingOccurrences(of: "_", with: " ")
                    )
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    Text("Tap to play")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
                Image(systemName: "play.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Episode Download Row

struct EpisodeDownloadRow: View {
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
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(2)
                Text(
                    isDownloaded ? "Tap to play" :
                        isDownloading ? "Downloading..." :
                        "Tap to download"
                )
                .font(.caption)
                .foregroundColor(
                    isDownloaded ? .green :
                        isDownloading ? .blue :
                        .secondary
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if isDownloaded {
                onPlay()
            } else if !isDownloading {
                onDownload()
            }
        }
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
                } else {
                    // Search Bar with Overlay Border
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(
                            "Search podcasts...",
                            text: $searchText,
                            onCommit: { searchManager.searchPodcasts(query: searchText) }
                        )
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .padding()
                    
                    if searchManager.isSearching {
                        Spacer()
                        ProgressView("Searching...")
                        Spacer()
                    } else if searchManager.searchResults.isEmpty && !searchText.isEmpty {
                        Spacer()
                        Text("No results found")
                            .foregroundColor(.gray)
                        Spacer()
                    } else {
                        List(searchManager.searchResults) { podcast in
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: podcast.artworkUrl)) { $0.resizable() } placeholder: { Color.gray }
                                    .frame(width: 50, height: 50)
                                    .cornerRadius(8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(podcast.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(podcast.author)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(action: { searchManager.toggleFavorite(podcast) }) {
                                    Image(systemName: searchManager.isFavorite(podcast) ? "star.fill" : "star")
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPodcast = podcast
                                searchManager.loadEpisodes(for: podcast)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
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
    
    @State private var showDownloadedOnly = false
    @State var showingToast = false
    @State var toastMessage = ""
    
    var filteredEpisodes: [Episode] {
        showDownloadedOnly
            ? searchManager.episodes.filter {
                downloadManager.isDownloaded(filename: filenameForEpisode($0))
            }
            : searchManager.episodes
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: podcast.artworkUrl)) { $0.resizable() } placeholder: { Color.gray }
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
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
                    
                    Picker("Filter", selection: $showDownloadedOnly) {
                        Text("All").tag(false)
                        Text("Downloaded").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    Divider()
                    
                    if searchManager.isLoadingEpisodes {
                        Spacer()
                        ProgressView("Loading episodes...")
                        Spacer()
                    } else if filteredEpisodes.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: showDownloadedOnly ? "arrow.down.circle" : "mic")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text(showDownloadedOnly ? "No downloaded episodes" : "No episodes found")
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else {
                        List(filteredEpisodes) { episode in
                            EpisodeDownloadRow(
                                episode: episode,
                                podcast: podcast,
                                downloadManager: downloadManager,
                                onPlay: { playEpisode(episode) },
                                onDownload: { downloadEpisode(episode) }
                            )
                        }
                        .listStyle(.plain)
                    }
                }
                
                if showingToast {
                    VStack {
                        Spacer()
                        PodcastToastView(message: toastMessage)
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: showingToast)
                }
            }
            .navigationTitle("Episodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
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
        
        dismissAll()
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

// MARK: - Episodes Browse View

struct EpisodesBrowseView: View {
    let podcast: Podcast
    let episodes: [Episode]
    let isLoading: Bool
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    @ObservedObject var searchManager: PodcastSearchManager
    let onBack: () -> Void
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
            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: podcast.artworkUrl)) { $0.resizable() } placeholder: { Color.gray }
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
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
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                Picker("Filter", selection: $showDownloadedOnly) {
                    Text("All").tag(false)
                    Text("Downloaded").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.bottom, 8)
                Divider()
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading episodes...")
                    Spacer()
                } else if filteredEpisodes.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: showDownloadedOnly ? "arrow.down.circle" : "mic")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text(showDownloadedOnly ? "No downloaded episodes" : "No episodes found")
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    List(filteredEpisodes) { episode in
                        EpisodeDownloadRow(
                            episode: episode,
                            podcast: podcast,
                            downloadManager: downloadManager,
                            onPlay: { playEpisode(episode) },
                            onDownload: { downloadEpisode(episode) }
                        )
                    }
                    .listStyle(.plain)
                }
            }
            
            if showingToast {
                VStack {
                    Spacer()
                    PodcastToastView(message: toastMessage)
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: showingToast)
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
                    VStack(spacing: 12) {
                        Image(systemName: "star")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No favorites yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    List(searchManager.favoritePodcasts) { podcast in
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: podcast.artworkUrl)) { $0.resizable() } placeholder: { Color.gray }
                                .frame(width: 50, height: 50)
                                .cornerRadius(8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(podcast.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(podcast.author)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(action: { searchManager.toggleFavorite(podcast) }) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPodcast = podcast
                            searchManager.loadEpisodes(for: podcast)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
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
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
    }
}

// MARK: - Nav Circle Button (custom toolbar buttons)

private struct NavCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color(.systemGray5))
                )
                .contentShape(Circle())
        }
        // Plain style so SwiftUI does not group them into one pill
        .buttonStyle(.plain)
    }
}
