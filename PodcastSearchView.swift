//
//  PodcastSearchView.swift
//  2 Music 2 Furious - MILESTONE 15
//
//  Podcast search and download
//  UPDATED: Uses shared GlassEpisodeRow for standardized "Played" tracking
//  UPDATED: Added Drag-to-Reorder for Favorites
//  NEW: Episode Detail View via info button (navigation push)
//  NEW: Full episode metadata stored with downloads
//  NEW: Properly formatted descriptions with clickable links
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Formatted Description View (Clickable Links + Paragraphs)

struct FormattedDescriptionView: View {
    let text: String
    let fontSize: CGFloat
    
    init(text: String, fontSize: CGFloat = 15) {
        self.text = text
        self.fontSize = fontSize
    }
    
    private var cleanedText: String {
        cleanHTML(text)
    }
    
    var body: some View {
        FormattedTextViewRepresentable(
            text: cleanedText,
            fontSize: fontSize
        )
    }
    
    private func cleanHTML(_ html: String) -> String {
        var text = html
        
        // Convert <br>, <br/>, <br /> to newlines
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        
        // Convert </p> and </div> to double newlines (paragraph breaks)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n\n", options: .caseInsensitive)
        
        // Convert <li> to bullet points
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "\n• ", options: .regularExpression)
        
        // Remove all remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&#x27;", with: "'")
        text = text.replacingOccurrences(of: "&#x2F;", with: "/")
        text = text.replacingOccurrences(of: "&mdash;", with: "\u{2014}")
        text = text.replacingOccurrences(of: "&ndash;", with: "\u{2013}")
        text = text.replacingOccurrences(of: "&hellip;", with: "\u{2026}")
        text = text.replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
        text = text.replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
        text = text.replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
        text = text.replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
        
        // Decode numeric entities (&#123; format)
        let numericEntityPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericEntityPattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: text),
                   let numRange = Range(match.range(at: 1), in: text),
                   let codePoint = Int(text[numRange]),
                   let scalar = Unicode.Scalar(codePoint) {
                    text.replaceSubrange(matchRange, with: String(Character(scalar)))
                }
            }
        }
        
        // Clean up excessive newlines (more than 2 in a row)
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - UIKit Text View with proper sizing

private struct FormattedTextViewRepresentable: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = [.link]
        textView.linkTextAttributes = [
            .foregroundColor: UIColor(Color.royalPurple),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 12
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraphStyle
        ]
        
        textView.attributedText = NSAttributedString(string: text, attributes: attributes)
        textView.invalidateIntrinsicContentSize()
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

// MARK: - Navigation Destinations

enum PodcastNavDestination: Hashable {
    case search
    case favorites
    case podcastDetail(Podcast)
    case downloadedEpisodeDetail(String) // filename
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
                                downloadManager: downloadManager,
                                onPlay: { playEpisode(filename: filename) },
                                onInfo: {
                                    navigationPath.append(PodcastNavDestination.downloadedEpisodeDetail(filename))
                                }
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
                        navigationPath: $navigationPath,
                        dismissAll: dismiss
                    )
                case .downloadedEpisodeDetail(let filename):
                    DownloadedEpisodeDetailView(
                        filename: filename,
                        downloadManager: downloadManager,
                        searchManager: searchManager,
                        onPlay: {
                            playEpisode(filename: filename)
                        },
                        onDelete: {
                            downloadManager.deleteEpisode(filename: filename)
                            navigationPath.removeLast()
                        }
                    )
                }
            }
        }
        .accentColor(.royalPurple)
        .onAppear {
            searchManager.loadIfNeeded()
            downloadManager.loadIfNeeded()
        }
    }
    
    // MARK: - Helpers
    
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
        // Try to get metadata first
        if let metadata = downloadManager.getMetadata(for: filename) {
            let track = Track(
                title: metadata.episodeTitle,
                artist: metadata.podcastTitle,
                filename: filename
            )
            let artworkUrl = URL(string: metadata.podcastArtworkUrl)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            speechPlayer.playNow(track, artworkURL: artworkUrl)
            dismiss()
            return
        }
        
        // Fallback: parse from filename
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

// MARK: - Glass Downloaded Episode Row (With Info Button)

struct GlassDownloadedRow: View {
    let filename: String
    @ObservedObject var searchManager: PodcastSearchManager
    @ObservedObject var downloadManager: DownloadManager
    let onPlay: () -> Void
    var onInfo: (() -> Void)? = nil
    
    // Use metadata if available, otherwise fallback to parsing
    private var metadata: DownloadedEpisodeMetadata? {
        downloadManager.getMetadata(for: filename)
    }
    
    var podcastName: String {
        if let meta = metadata { return meta.podcastTitle }
        
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
        if let meta = metadata { return meta.episodeTitle }
        
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
        if let meta = metadata, !meta.podcastArtworkUrl.isEmpty {
            return URL(string: meta.podcastArtworkUrl)
        }
        if let match = searchManager.favoritePodcasts.first(where: { $0.title == podcastName }) {
            return URL(string: match.artworkUrl)
        }
        return nil
    }
    
    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                MediaArtworkView(
                    url: artworkUrl, size: 50, cornerRadius: 10,
                    fallbackIcon: "mic.fill", fallbackColor: .royalPurple
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
                
                // Info button
                if let onInfo = onInfo {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onInfo()
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Play button
                ZStack {
                    Circle().fill(Color(white: 0.3)).frame(width: 28, height: 28)
                    Image(systemName: "play.fill").font(.system(size: 12)).foregroundColor(.white).offset(x: 1)
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Downloaded Episode Detail View (Uses Stored Metadata)

struct DownloadedEpisodeDetailView: View {
    let filename: String
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var searchManager: PodcastSearchManager
    let onPlay: () -> Void
    let onDelete: () -> Void
    
    private var metadata: DownloadedEpisodeMetadata? {
        downloadManager.getMetadata(for: filename)
    }
    
    private var episodeName: String {
        if let meta = metadata { return meta.episodeTitle }
        let cleanName = filename.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".m4a", with: "")
        if let underscoreIndex = cleanName.firstIndex(of: "_") {
            return String(cleanName[cleanName.index(after: underscoreIndex)...])
        }
        return cleanName
    }
    
    private var podcastName: String {
        if let meta = metadata { return meta.podcastTitle }
        let cleanName = filename.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".m4a", with: "")
        if let underscoreIndex = cleanName.firstIndex(of: "_") {
            return String(cleanName[..<underscoreIndex])
        }
        return "Unknown Podcast"
    }
    
    private var artworkUrl: URL? {
        if let meta = metadata, !meta.podcastArtworkUrl.isEmpty {
            return URL(string: meta.podcastArtworkUrl)
        }
        return nil
    }
    
    private var formattedDate: String? {
        guard let meta = metadata else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: meta.episodePubDate)
    }
    
    private var formattedDuration: String? {
        guard let meta = metadata, meta.episodeDuration > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = meta.episodeDuration >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: meta.episodeDuration)
    }
    
    private var episodeDescription: String? {
        guard let meta = metadata, !meta.episodeDescription.isEmpty else { return nil }
        return meta.episodeDescription
    }
    
    private var tertiaryText: String {
        var parts: [String] = []
        if let duration = formattedDuration { parts.append(duration) }
        if let date = formattedDate { parts.append(date) }
        if parts.isEmpty { return "Downloaded" }
        return parts.joined(separator: " • ")
    }
    
    var body: some View {
        ZStack {
            GlassBackgroundView()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    MediaDetailHeader(
                        title: episodeName,
                        subtitle: podcastName,
                        tertiaryText: tertiaryText,
                        artworkURL: artworkUrl,
                        artworkIcon: "mic.fill",
                        artworkColor: .royalPurple
                    )
                    .padding(.horizontal)
                    
                    // Play Button
                    GlassActionButton(
                        title: "Play Episode",
                        icon: "play.fill",
                        color: .royalPurple,
                        action: onPlay
                    )
                    .padding(.horizontal)
                    
                    // Description (formatted with clickable links)
                    if let description = episodeDescription, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About This Episode")
                                .font(.headline)
                            
                            FormattedDescriptionView(text: description)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .padding(.horizontal)
                    } else if metadata == nil {
                        // No metadata - older download
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Ready to Play", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.green)
                            
                            Text("This episode was downloaded before metadata storage was enabled. Re-download from the podcast to see the full description.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineSpacing(4)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                    
                    // Delete Button
                    Button(action: onDelete) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Download")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.ultraThinMaterial)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    Spacer(minLength: 50)
                }
                .padding(.top)
            }
        }
        .navigationTitle("Episode Details")
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Episode Detail View (From Podcast List - Full Description with Links)

struct EpisodeDetailView: View {
    let episode: Episode
    let podcast: Podcast
    let isDownloaded: Bool
    let isDownloading: Bool
    let isPlayed: Bool
    let onDownload: () -> Void
    let onPlay: () -> Void
    let onTogglePlayed: () -> Void
    let onDelete: (() -> Void)?
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: episode.pubDate)
    }
    
    private var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = episode.duration >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: episode.duration) ?? "Unknown"
    }
    
    var body: some View {
        ZStack {
            GlassBackgroundView()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with podcast artwork
                    MediaDetailHeader(
                        title: episode.title,
                        subtitle: podcast.title,
                        tertiaryText: "\(formattedDuration) • \(formattedDate)",
                        artworkURL: URL(string: podcast.artworkUrl),
                        artworkIcon: "mic.fill",
                        artworkColor: .royalPurple
                    )
                    .padding(.horizontal)
                    
                    // Action Buttons
                    HStack(spacing: 12) {
                        // Download/Play Button
                        GlassActionButton(
                            title: isDownloaded ? "Play Episode" : "Download",
                            icon: isDownloaded ? "play.fill" : "arrow.down.circle.fill",
                            isLoading: isDownloading,
                            loadingText: "Downloading...",
                            color: .royalPurple,
                            action: {
                                if isDownloaded {
                                    onPlay()
                                } else {
                                    onDownload()
                                }
                            }
                        )
                        
                        // Mark Played Button
                        Button(action: {
                            onTogglePlayed()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }) {
                            Image(systemName: isPlayed ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 22))
                                .foregroundColor(isPlayed ? .green : .secondary)
                                .frame(width: 50, height: 50)
                                .background(.ultraThinMaterial)
                                .cornerRadius(14)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Played Status Badge
                    if isPlayed {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Played")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal)
                    }
                    
                    // Description (formatted with clickable links)
                    if !episode.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About This Episode")
                                .font(.headline)
                            
                            FormattedDescriptionView(text: episode.description)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "text.alignleft")
                                .font(.largeTitle)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No description available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                    
                    // Delete Button (if downloaded)
                    if isDownloaded, let onDelete = onDelete {
                        Button(action: onDelete) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Download")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.ultraThinMaterial)
                            .cornerRadius(14)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding(.top)
            }
        }
        .navigationTitle("Episode Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Episode Info for Navigation

struct EpisodeNavInfo: Hashable {
    let episodeId: UUID
    let episodeTitle: String
    let episodeDescription: String
    let episodeAudioUrl: String
    let episodeDuration: TimeInterval
    let episodePubDate: Date
    let podcastId: Int
    let podcastTitle: String
    let podcastAuthor: String
    let podcastArtworkUrl: String
    let podcastFeedUrl: String
    
    init(episode: Episode, podcast: Podcast) {
        self.episodeId = episode.id
        self.episodeTitle = episode.title
        self.episodeDescription = episode.description
        self.episodeAudioUrl = episode.audioUrl
        self.episodeDuration = episode.duration
        self.episodePubDate = episode.pubDate
        self.podcastId = podcast.id
        self.podcastTitle = podcast.title
        self.podcastAuthor = podcast.author
        self.podcastArtworkUrl = podcast.artworkUrl
        self.podcastFeedUrl = podcast.feedUrl
    }
    
    var episode: Episode {
        Episode(
            title: episodeTitle,
            description: episodeDescription,
            audioUrl: episodeAudioUrl,
            duration: episodeDuration,
            pubDate: episodePubDate
        )
    }
    
    var podcast: Podcast {
        Podcast(
            id: podcastId,
            title: podcastTitle,
            author: podcastAuthor,
            artworkUrl: podcastArtworkUrl,
            feedUrl: podcastFeedUrl
        )
    }
}

// MARK: - Podcast Detail Destination

struct PodcastDetailDestination: View {
    let podcast: Podcast
    @ObservedObject var searchManager: PodcastSearchManager
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var speechPlayer: AudioPlayer
    @Binding var navigationPath: NavigationPath
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
                            let isDownloaded = downloadManager.isDownloaded(filename: filenameForEpisode(episode))
                            
                            GlassEpisodeRow(
                                title: episode.title,
                                duration: formatDuration(episode.duration),
                                isPlayed: isPlayed,
                                isDownloaded: isDownloaded,
                                isDownloading: downloadManager.isDownloading(episodeId: episode.id.uuidString),
                                downloadColor: .royalPurple,
                                onDownload: { downloadEpisode(episode) },
                                onPlay: isDownloaded ? { playEpisode(episode) } : nil,
                                onInfo: {
                                    let navInfo = EpisodeNavInfo(episode: episode, podcast: podcast)
                                    navigationPath.append(navInfo)
                                }
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
                                if isDownloaded {
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationDestination(for: EpisodeNavInfo.self) { navInfo in
                let episode = navInfo.episode
                let isDownloaded = downloadManager.isDownloaded(filename: filenameForEpisode(episode))
                
                EpisodeDetailView(
                    episode: episode,
                    podcast: navInfo.podcast,
                    isDownloaded: isDownloaded,
                    isDownloading: downloadManager.isDownloading(episodeId: episode.id.uuidString),
                    isPlayed: searchManager.isPlayed(episode),
                    onDownload: { downloadEpisode(episode) },
                    onPlay: { playEpisode(episode) },
                    onTogglePlayed: { searchManager.togglePlayed(episode) },
                    onDelete: isDownloaded ? {
                        downloadManager.deleteEpisode(filename: filenameForEpisode(episode))
                        navigationPath.removeLast()
                    } : nil
                )
            }
            
            if showingToast {
                VStack { Spacer(); GlassToastView(message: toastMessage, iconColor: .royalPurple).padding(.bottom, 20) }.zIndex(100)
            }
        }
        .navigationTitle("Episodes")
        .navigationBarTitleDisplayMode(.inline)
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
            title: episode.title,
            artist: podcast.title,
            filename: filename
        )
        let artworkUrl = URL(string: podcast.artworkUrl)
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        speechPlayer.playNow(track, artworkURL: artworkUrl)
        dismissAll()
    }
    
    private func downloadEpisode(_ episode: Episode) {
        if downloadManager.isDownloaded(filename: filenameForEpisode(episode)) { showToast("Already downloaded"); return }
        // Pass full podcast metadata for storage
        downloadManager.downloadEpisode(
            episode,
            podcastTitle: podcast.title,
            podcastAuthor: podcast.author,
            podcastArtworkUrl: podcast.artworkUrl
        )
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
