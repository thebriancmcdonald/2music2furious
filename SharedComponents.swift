//
//  SharedComponents.swift
//  2 Music 2 Furious - MILESTONE 13
//
//  Unified Glass UI Components
//  FIXED: glassPanel and glassCard no longer clip their content, allowing popups to overflow.
//

import SwiftUI
import MediaPlayer

// MARK: - SYSTEMIC COLOR LOGIC
extension Color {
    static let brandPrimary = Color.purple
    static let royalPurple = brandPrimary
    static let deepResumePurple = brandPrimary.mix(with: .black, by: 0.4)
    
    func mix(with other: Color, by amount: Double) -> Color {
        let uiColor1 = UIColor(self)
        let uiColor2 = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        uiColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        uiColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(UIColor(
            red: r1 * CGFloat(1 - amount) + r2 * CGFloat(amount),
            green: g1 * CGFloat(1 - amount) + g2 * CGFloat(amount),
            blue: b1 * CGFloat(1 - amount) + b2 * CGFloat(amount),
            alpha: a1 * CGFloat(1 - amount) + a2 * CGFloat(amount)
        ))
    }
}

// MARK: - Glass Toast View

struct GlassToastView: View {
    let message: String
    var icon: String = "checkmark.circle.fill"
    var iconColor: Color = .royalPurple
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(iconColor)
            Text(message).font(.subheadline.weight(.medium)).foregroundColor(.primary).lineLimit(1)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.thinMaterial).clipShape(Capsule())
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
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField(placeholder, text: $text, onCommit: onCommit).submitLabel(.search)
            if !text.isEmpty {
                Button(action: { text = ""; onClear?() }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
        }
        .padding(.leading, 10).padding(.trailing, text.isEmpty ? 10 : 0).padding(.vertical, 6)
        .background(.ultraThinMaterial).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Glass Empty State

struct GlassEmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actions: [(icon: String, title: String, action: () -> Void)] = []
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 120, height: 120)
                Image(systemName: icon).font(.system(size: 50)).foregroundColor(.secondary)
            }
            VStack(spacing: 8) {
                Text(title).font(.title3.weight(.semibold))
                if let subtitle = subtitle {
                    Text(subtitle).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
            }.padding(.horizontal)
            
            if !actions.isEmpty {
                HStack(spacing: 16) {
                    ForEach(actions.indices, id: \.self) { i in
                        Button(action: actions[i].action) {
                            VStack(spacing: 12) {
                                Image(systemName: actions[i].icon).font(.system(size: 24))
                                Text(actions[i].title).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.9)
                            }
                            .foregroundColor(.primary).frame(maxWidth: .infinity).frame(height: 90)
                            .background(.ultraThinMaterial).cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                        }
                    }
                }.padding(.horizontal, 24).padding(.top, 10)
            }
            Spacer()
        }
    }
}

// MARK: - Expandable Description

struct ExpandableDescriptionView: View {
    let text: String
    var title: String = "Description"
    var color: Color = .royalPurple
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).font(.system(size: 15)).foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 4).animation(.spring(), value: isExpanded)
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                Text(isExpanded ? "Show Less" : "Show More")
                    .font(.caption.weight(.bold)).foregroundColor(color)
                    .padding(.top, 4).frame(height: 44, alignment: .top).contentShape(Rectangle())
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial).cornerRadius(16)
        .onTapGesture { withAnimation { isExpanded.toggle() } }
    }
}

// MARK: - Media Artwork View

struct MediaArtworkView: View {
    let url: URL?
    var data: Data? = nil
    var image: UIImage? = nil
    let size: CGFloat
    var cornerRadius: CGFloat = 20
    var fallbackIcon: String = "music.note"
    var fallbackColor: Color = .royalPurple
    
    @State private var cachedImage: UIImage? = nil
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let data = data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            } else if let cachedImage = cachedImage {
                Image(uiImage: cachedImage).resizable().aspectRatio(contentMode: .fill)
            } else if url != nil && isLoading {
                ZStack {
                    fallbackColor.opacity(0.1)
                    ProgressView().scaleEffect(0.8)
                }
            } else {
                ZStack {
                    fallbackColor.opacity(0.1)
                    Image(systemName: fallbackIcon).font(.system(size: size * 0.4)).foregroundColor(fallbackColor)
                }
            }
        }
        .frame(width: size, height: size).cornerRadius(cornerRadius).clipped().shadow(radius: 5)
        .onAppear { if image == nil { loadCachedImage() } }
        .onChange(of: url) { _ in cachedImage = nil; isLoading = true; loadCachedImage() }
    }
    
    private func loadCachedImage() {
        guard let url = url else { isLoading = false; return }
        ImageCache.shared.image(for: url) { loadedImage in
            withAnimation(.easeIn(duration: 0.15)) {
                self.cachedImage = loadedImage
                self.isLoading = false
            }
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
                url: artworkURL, data: artworkData, size: 100,
                cornerRadius: 20, fallbackIcon: artworkIcon, fallbackColor: artworkColor
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.subheadline).foregroundColor(.secondary)
                if let tertiary = tertiaryText {
                    Text(tertiary).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if let onFavorite = onFavoriteToggle, let isFav = isFavorite {
                Button(action: onFavorite) {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .font(.system(size: 24)).foregroundColor(.orange)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
        }
        .padding().background(.ultraThinMaterial).cornerRadius(24)
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
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(loadingText)
                } else {
                    if let icon = icon { Image(systemName: icon) }
                    Text(title)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(isLoading || isDisabled ? .white.opacity(0.7) : .white)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(isLoading || isDisabled ? Color.secondary.opacity(0.3) : color)
            .cornerRadius(16)
            .shadow(color: (isLoading || isDisabled) ? Color.clear : color.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .disabled(isLoading || isDisabled).opacity(isLoading || isDisabled ? 0.7 : 1.0)
    }
}

// MARK: - Glass Media List Row

struct GlassMediaListRow: View {
    let title: String
    let subtitle: String
    var artworkURL: URL?
    var artworkIcon: String = "music.note"
    var artworkColor: Color = .royalPurple
    var details: String? = nil
    var rightIcon: String? = "chevron.right"
    var isFavorite: Bool? = nil
    var onFavoriteToggle: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkView(
                url: artworkURL, size: 56, cornerRadius: 12,
                fallbackIcon: artworkIcon, fallbackColor: artworkColor
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
                Text(subtitle).font(.system(size: 14)).foregroundColor(.secondary).lineLimit(1)
                if let details = details {
                    Text(details).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if let onFavorite = onFavoriteToggle, let isFav = isFavorite {
                Button(action: onFavorite) {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .foregroundColor(.orange).font(.system(size: 20))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(BorderlessButtonStyle())
            } else if let rightIcon = rightIcon {
                Image(systemName: rightIcon)
                    .foregroundColor(.secondary.opacity(0.5)).font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(12).glassCard(cornerRadius: 16)
    }
}

// MARK: - Glass Download Row (Simple)

struct GlassDownloadRow: View {
    var index: Int? = nil
    let title: String
    let subtitle: String
    var isDownloaded: Bool
    var isDownloading: Bool
    var color: Color = .royalPurple
    var onDownload: () -> Void
    var onPlay: (() -> Void)? = nil
    
    var body: some View {
        Button(action: {
            if isDownloading { return }
            if isDownloaded { onPlay?() } else { onDownload() }
        }) {
            HStack(spacing: 12) {
                if let index = index {
                    Text("\(index)").font(.system(size: 14, weight: .bold)).foregroundColor(.secondary).frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundColor(.primary).lineLimit(1).multilineTextAlignment(.leading)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if isDownloaded {
                    if onPlay != nil {
                        ZStack {
                            Circle().fill(Color(white: 0.3)).frame(width: 28, height: 28)
                            Image(systemName: "play.fill").font(.system(size: 12)).foregroundColor(.white).offset(x: 1)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 20))
                    }
                } else if isDownloading {
                    ProgressView().scaleEffect(0.8).frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.down.circle").foregroundColor(color).font(.system(size: 24))
                }
            }
            .padding(12).glassCard(cornerRadius: 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Glass Episode Row (Advanced - For Podcasts/Audiobooks)
// Handles "Played" dimming logic

struct GlassEpisodeRow: View {
    let title: String
    let duration: String
    let isPlayed: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    var downloadColor: Color = .royalPurple
    let onDownload: () -> Void
    let onPlay: (() -> Void)?
    
    var body: some View {
        Button(action: {
            if isDownloading { return }
            if isDownloaded { onPlay?() } else { onDownload() }
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    // Title: Dims if played
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isPlayed ? .secondary : .primary) // DIM TITLE ONLY
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    
                    // Subtitle: Remains legible + Played Status
                    HStack(spacing: 4) {
                        Text(duration)
                        if isPlayed {
                            Text("•")
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("Played")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary) // STANDARD LEGIBLE COLOR
                }
                Spacer()
                if isDownloaded {
                    if onPlay != nil {
                        ZStack {
                            Circle().fill(Color(white: 0.3)).frame(width: 28, height: 28)
                            Image(systemName: "play.fill").font(.system(size: 12)).foregroundColor(.white).offset(x: 1)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 20))
                    }
                } else if isDownloading {
                    ProgressView().scaleEffect(0.8).frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.down.circle").foregroundColor(downloadColor).font(.system(size: 24))
                }
            }
            .padding(12).glassCard(cornerRadius: 12)
        }
        .buttonStyle(PlainButtonStyle())
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
            Text(title).font(.title2.weight(.bold))
            if let count = count, count > 0 {
                Text("\(count)").font(.headline).foregroundColor(.secondary.opacity(0.7))
            }
            Spacer()
            if let icon = actionIcon, let action = onAction {
                Button(action: action) {
                    Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundColor(.secondary)
                        .padding(8).background(.ultraThinMaterial).clipShape(Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
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
        .onChange(of: selection) { newValue in onChange?(newValue) }
    }
}

// MARK: - Favorites Carousel & Item

struct FavoritesCarousel<Item: Identifiable, Content: View>: View {
    let title: String
    let items: [Item]
    var onSeeAll: (() -> Void)? = nil
    let content: (Item) -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.title2.weight(.bold))
                Spacer()
                if let seeAll = onSeeAll {
                    Button(action: seeAll) {
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.secondary)
                            .padding(8).background(.ultraThinMaterial).clipShape(Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                }
            }.padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in content(item) }
                }.padding(.horizontal, 4).padding(.bottom, 10)
            }
        }
    }
}

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
                    url: artworkURL, data: artworkData, size: size,
                    cornerRadius: 16, fallbackIcon: fallbackIcon, fallbackColor: fallbackColor
                ).shadow(radius: 4)
                Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.primary)
                    .lineLimit(2).multilineTextAlignment(.center).frame(width: size)
            }
        }.buttonStyle(BorderlessButtonStyle())
    }
}

// MARK: - Backgrounds & Buttons

struct GlassBackgroundView: View {
    var primaryColor: Color = .blue
    var secondaryColor: Color = .royalPurple
    var body: some View {
        LinearGradient(
            colors: [primaryColor.opacity(0.1), secondaryColor.opacity(0.1)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ).ignoresSafeArea()
    }
}

struct GlassCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
    }
}

struct GlassPlusButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.secondary)
                .padding(8).background(.ultraThinMaterial).clipShape(Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(BorderlessButtonStyle())
    }
}

struct GlassPlayButton: View {
    var isPlaying: Bool = false
    var size: CGFloat = 28
    var color: Color = .royalPurple
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(white: 0.3)).frame(width: size, height: size)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.4)).foregroundColor(.white).offset(x: isPlaying ? 0 : 1)
            }
            .shadow(radius: 2).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(BorderlessButtonStyle())
    }
}

// MARK: - KEY FIX: Non-clipping Glass Modifiers
// We apply the clip shape ONLY to the background, not to the View itself ("self").
// This allows overlay content (like our slider) to render outside the bounds.

extension View {
    func glassPanel(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }

    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    func glassListRow() -> some View {
        self.listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
    func glassListRowWide() -> some View {
        self.listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

struct BorderlessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
