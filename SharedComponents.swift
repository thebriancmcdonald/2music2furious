//
//  SharedComponents.swift
//  2 Music 2 Furious - MILESTONE 11
//
//  Unified Glass UI Components for consistent Apple-style design
//  Consolidates: Toast, Search Bar, Empty State, Description, Artwork, Headers, Rows
//

import SwiftUI
import MediaPlayer

// MARK: - SYSTEMIC COLOR LOGIC
extension Color {
    // 1. MASTER THEME COLOR
    // Change this single line to .green, .orange, etc. to update the whole app.
    static let brandPrimary = Color.purple
    
    // 2. SEMANTIC NAMES (Use these in your Views)
    static let royalPurple = brandPrimary // For text, icons, borders
    
    // 3. AUTOMATIC DARK VARIANT
    // Mathematically mixes the brand color with 40% black for large button backgrounds
    static let deepResumePurple = brandPrimary.mix(with: .black, by: 0.4)
    
    // Helper: Mixes two colors together
    func mix(with other: Color, by amount: Double) -> Color {
        let uiColor1 = UIColor(self)
        let uiColor2 = UIColor(other)
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        uiColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        uiColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        let r = r1 * CGFloat(1 - amount) + r2 * CGFloat(amount)
        let g = g1 * CGFloat(1 - amount) + g2 * CGFloat(amount)
        let b = b1 * CGFloat(1 - amount) + b2 * CGFloat(amount)
        let a = a1 * CGFloat(1 - amount) + a2 * CGFloat(amount)
        
        return Color(UIColor(red: r, green: g, blue: b, alpha: a))
    }
}

// MARK: - Glass Toast View (Universal)

struct GlassToastView: View {
    let message: String
    var icon: String = "checkmark.circle.fill"
    var iconColor: Color = .royalPurple
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Glass Search Bar

struct GlassSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onCommit: () -> Void = {}
    var onClear: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text, onCommit: onCommit)
                .submitLabel(.search)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                    onClear?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Glass Empty State View

struct GlassEmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actions: [(icon: String, title: String, action: () -> Void)] = []
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
            
            if !actions.isEmpty {
                HStack(spacing: 16) {
                    ForEach(actions.indices, id: \.self) { i in
                        Button(action: actions[i].action) {
                            VStack(spacing: 12) {
                                Image(systemName: actions[i].icon)
                                    .font(.system(size: 24))
                                Text(actions[i].title)
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)
                            }
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 90) // Fixed height ensures buttons are same size
                            .background(.ultraThinMaterial)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            }
            
            Spacer()
        }
    }
}

// MARK: - Expandable Description View

struct ExpandableDescriptionView: View {
    let text: String
    var title: String = "Description"
    var color: Color = .royalPurple
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 4)
                .animation(.spring(), value: isExpanded)
            
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                Text(isExpanded ? "Show Less" : "Show More")
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .onTapGesture { withAnimation { isExpanded.toggle() } }
    }
}

// MARK: - Media Artwork View (Universal)

struct MediaArtworkView: View {
    let url: URL?
    var data: Data? = nil
    let size: CGFloat
    var cornerRadius: CGFloat = 20
    var fallbackIcon: String = "music.note"
    var fallbackColor: Color = .royalPurple
    
    var body: some View {
        ZStack {
            if let data = data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let url = url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        fallbackView
                    } else {
                        ZStack {
                            fallbackColor.opacity(0.1)
                            ProgressView()
                        }
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(cornerRadius)
        .clipped()
        .shadow(radius: 5)
    }
    
    private var fallbackView: some View {
        ZStack {
            fallbackColor.opacity(0.1)
            Image(systemName: fallbackIcon)
                .font(.system(size: size * 0.4))
                .foregroundColor(fallbackColor)
        }
    }
}

// MARK: - Media Detail Header

struct MediaDetailHeader: View {
    let title: String
    let subtitle: String
    var tertiaryText: String? = nil
    let artworkURL: URL?
    var artworkData: Data? = nil
    var artworkIcon: String = "music.note"
    var artworkColor: Color = .royalPurple
    var isFavorite: Bool? = nil
    var onFavoriteToggle: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            MediaArtworkView(
                url: artworkURL,
                data: artworkData,
                size: 100,
                cornerRadius: 20,
                fallbackIcon: artworkIcon,
                fallbackColor: artworkColor
            )
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let tertiary = tertiaryText {
                    Text(tertiary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let onFavorite = onFavoriteToggle, let isFav = isFavorite {
                Button(action: onFavorite) {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }
}

// MARK: - Glass Action Button

struct GlassActionButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var loadingText: String = "Loading..."
    var color: Color = .royalPurple
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(loadingText)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isLoading || isDisabled ? Color.gray : color)
            .cornerRadius(16)
            .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .disabled(isLoading || isDisabled)
    }
}

// MARK: - Glass Media List Row (Unified for Search Results)
// Replaces LibriVoxBookRow and GlassPodcastRow

struct GlassMediaListRow: View {
    let title: String
    let subtitle: String
    var artworkURL: URL?
    var artworkIcon: String = "music.note"
    var artworkColor: Color = .royalPurple
    var details: String? = nil // e.g. "23 chapters"
    var rightIcon: String? = "chevron.right"
    var isFavorite: Bool? = nil
    var onFavoriteToggle: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkView(
                url: artworkURL,
                size: 56,
                cornerRadius: 12,
                fallbackIcon: artworkIcon,
                fallbackColor: artworkColor
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let details = details {
                    Text(details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let onFavorite = onFavoriteToggle, let isFav = isFavorite {
                Button(action: onFavorite) {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .foregroundColor(.orange)
                        .font(.system(size: 20))
                }
                .buttonStyle(BorderlessButtonStyle())
            } else if let rightIcon = rightIcon {
                Image(systemName: rightIcon)
                    .foregroundColor(.secondary.opacity(0.5))
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }
}

// MARK: - Glass Download Row (Unified for Chapters/Episodes)
// Replaces LibriVoxChapterRow and GlassEpisodeDownloadRow

struct GlassDownloadRow: View {
    var index: Int? = nil // Optional index number (1, 2, 3...)
    let title: String
    let subtitle: String // Duration or other info
    
    // State management
    var isDownloaded: Bool
    var isDownloading: Bool
    var color: Color = .royalPurple
    
    // Actions
    var onDownload: () -> Void
    var onPlay: (() -> Void)? = nil // If nil, checkmark is shown when downloaded
    
    var body: some View {
        HStack(spacing: 12) {
            if let index = index {
                Text("\(index)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 30)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isDownloaded {
                if let onPlay = onPlay {
                    GlassPlayButton(size: 28, color: color, action: onPlay)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                }
            } else if isDownloading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(color)
                        .font(.system(size: 24))
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }
}

// MARK: - Glass Section Header

struct GlassSectionHeader: View {
    let title: String
    var count: Int? = nil
    var actionIcon: String? = nil
    var onAction: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.bold))
            
            if let count = count, count > 0 {
                Text("\(count)")
                    .font(.headline)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
            
            if let icon = actionIcon, let action = onAction {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
        }
    }
}

// MARK: - Glass Segmented Filter

struct GlassSegmentedFilter<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]
    var color: Color = .royalPurple
    var onChange: ((T) -> Void)? = nil
    
    var body: some View {
        Picker("Filter", selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .onChange(of: selection) { newValue in
            onChange?(newValue)
        }
    }
}

// MARK: - Horizontal Favorites Carousel

struct FavoritesCarousel<Item: Identifiable, Content: View>: View {
    let title: String
    let items: [Item]
    var onSeeAll: (() -> Void)? = nil
    let content: (Item) -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.title2.weight(.bold))
                Spacer()
                if let seeAll = onSeeAll {
                    Button(action: seeAll) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        content(item)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Carousel Item View

struct CarouselItemView: View {
    let title: String
    let artworkURL: URL?
    var artworkData: Data? = nil
    var size: CGFloat = 70
    var fallbackIcon: String = "music.note"
    var fallbackColor: Color = .royalPurple
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                MediaArtworkView(
                    url: artworkURL,
                    data: artworkData,
                    size: size,
                    cornerRadius: 16,
                    fallbackIcon: fallbackIcon,
                    fallbackColor: fallbackColor
                )
                .shadow(radius: 4)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: size)
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

// MARK: - Standard Background Gradient

struct GlassBackgroundView: View {
    var primaryColor: Color = .blue
    var secondaryColor: Color = .royalPurple
    
    var body: some View {
        LinearGradient(
            colors: [primaryColor.opacity(0.1), secondaryColor.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Glass Navigation Close Button

struct GlassCloseButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Chapter/Episode Row View (Local Library)

struct GlassChapterRow: View {
    let index: Int
    let title: String
    let duration: String
    var isDownloaded: Bool = true
    var isPlaying: Bool = false
    var isDownloading: Bool = false
    var color: Color = .royalPurple
    var onPlay: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
                .frame(width: 25)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isDownloaded {
                if let play = onPlay {
                    Button(action: play) {
                        if isPlaying {
                            Image(systemName: "waveform")
                                .foregroundColor(color)
                                .font(.caption)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            } else {
                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let download = onDownload {
                    Button(action: download) {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(color)
                            .font(.system(size: 20))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
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

// MARK: - Plus Button (for adding to queue)

struct GlassPlusButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.secondary)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

// MARK: - Play Button Circle

struct GlassPlayButton: View {
    var size: CGFloat = 28
    var color: Color = .royalPurple
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Grey Circle
                Circle()
                    .fill(Color(white: 0.3)) // Dark grey for contrast
                    .frame(width: size, height: size)
                
                // White Triangle
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white)
                    .offset(x: 1) // Optical alignment
            }
            .shadow(radius: 2)
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

// MARK: - View Extension for Glass Panel

extension View {
    func glassPanel(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
    
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Standard List Row Modifiers

extension View {
    func glassListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
    
    func glassListRowWide() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}
