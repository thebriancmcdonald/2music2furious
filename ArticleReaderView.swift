//
//  ArticleReaderView.swift
//  2 Music 2 Furious
//
//  Full-screen article reader with text-to-speech
//  Fixed:
//  - "Half Word" highlighting bug (Text/TTS Synchronization)
//  - Word Snapping for cleaner visuals
//  - Scroll, Buttons, and Layout fully working
//

import SwiftUI
import AVFoundation

struct ArticleReaderView: View {
    let article: Article
    @ObservedObject var articleManager: ArticleManager
    @ObservedObject var speechPlayer: AudioPlayer

    @Environment(\.dismiss) private var dismiss
    @StateObject private var tts = TTSManager.shared

    @State private var currentChapterIndex: Int = 0
    @State private var showingChapterList = false
    @State private var showingSettings = false

    // Voice Settings - Expandable Sections
    // Note: Siri voices not available via AVSpeechSynthesizer API (Apple restriction)
    // All voice sections collapsed by default
    @State private var showPremiumVoices = false
    @State private var showEnhancedVoices = false
    @State private var showDefaultVoices = false
    @State private var showDownloadConfirmation = false
    @State private var pendingDownloadVoiceName: String = ""

    // Appearance Settings
    @State private var lineSpacing: CGFloat = 6.0
    @State private var paragraphSpacing: CGFloat = 0.0  // Paragraphs already have \n\n from extraction

    var currentChapter: ArticleChapter {
        guard article.chapters.indices.contains(currentChapterIndex) else {
            return article.chapters.first ?? ArticleChapter(title: "Empty", content: "No content")
        }
        return article.chapters[currentChapterIndex]
    }
    
    // CRITICAL: Use the EXACT content string that spans were indexed against.
    // FormattingSpans are character indices into currentChapter.content.
    // Any modification (like replacing \n\n with \n) will misalign the spans.
    // The ArticleExtractor already handles newline normalization, so we use content as-is.
    var displayContent: String {
        return currentChapter.content
    }

    var body: some View {
        ZStack {
            // Background
            GlassBackgroundView(primaryColor: .royalPurple, secondaryColor: .blue)

            VStack(spacing: 0) {
                // UNIFIED READER VIEW
                UnifiedReaderTextView(
                    articleTitle: article.title,
                    author: article.author,
                    source: article.displaySource,
                    chapterTitle: article.chapters.count > 1 ? currentChapter.title : nil,
                    content: displayContent,
                    formattingSpans: currentChapter.formattingSpans,
                    images: currentChapter.images,
                    highlightRange: tts.currentWordRange,
                    isPlaying: tts.isPlaying,
                    lineSpacing: lineSpacing,
                    paragraphSpacing: paragraphSpacing,
                    onTapWord: { position in
                        tts.seekAndPlay(to: position)
                    },
                    onLinkTapped: { url in
                        UIApplication.shared.open(url)
                    }
                )
                .id("reader_L\(Int(lineSpacing))_P\(Int(paragraphSpacing))_\(currentChapter.id)")
                
                // Playback Controls
                playbackControls
            }

            // Chapter list overlay
            if showingChapterList {
                chapterListOverlay
            }

            // Settings overlay
            if showingSettings {
                settingsOverlay
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if article.chapters.count > 1 {
                    Button(action: { showingChapterList.toggle() }) {
                        HStack(spacing: 4) {
                            Text("Ch \(currentChapterIndex + 1)/\(article.chapters.count)")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.ultraThinMaterial))
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            currentChapterIndex = article.lastReadChapter
            loadChapterForTTS()
            tts.onChapterFinished = { goToNextChapter() }
        }
        .onDisappear {
            tts.stop()
            articleManager.updateProgress(
                articleId: article.id,
                chapterIndex: currentChapterIndex,
                position: tts.currentCharacterPosition
            )
        }
        .onChange(of: currentChapterIndex) { _ in
            loadChapterForTTS()
        }
    }

    // MARK: - TTS Helpers
    private func loadChapterForTTS() {
        tts.stop()
        // Use displayContent - same string used for visual display and span indices
        tts.loadText(displayContent)

        if currentChapterIndex == article.lastReadChapter && article.lastReadPosition > 0 {
            tts.seek(to: article.lastReadPosition)
        }
    }

    // MARK: - Playback Controls
    private var playbackControls: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.1))
                    Rectangle().fill(Color.royalPurple).frame(width: geo.size.width * tts.progress)
                }
            }
            .frame(height: 3)

            HStack(spacing: 20) {
                if article.chapters.count > 1 {
                    Button(action: { showingChapterList = true }) {
                        VStack(spacing: 2) {
                            Image(systemName: "list.bullet").font(.system(size: 16))
                            Text("\(currentChapterIndex + 1)/\(article.chapters.count)").font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                    }
                }
                Spacer()
                Button(action: { tts.skipBackward(words: 15) }) {
                    Image(systemName: "gobackward.15").font(.system(size: 22)).foregroundColor(.white.opacity(0.9)).frame(width: 44, height: 44)
                }
                Button(action: { tts.togglePlayPause() }) {
                    Image(systemName: tts.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.royalPurple))
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                }
                Button(action: { tts.skipForward(words: 30) }) {
                    Image(systemName: "goforward.30").font(.system(size: 22)).foregroundColor(.white.opacity(0.9)).frame(width: 44, height: 44)
                }
                Spacer()
                Button(action: { tts.cycleSpeed() }) {
                    Text("\(String(format: "%.2f", tts.playbackSpeed))x")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(tts.playbackSpeed == 1.0 ? .white.opacity(0.7) : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
    
    // MARK: - Settings Overlay
    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showingSettings = false }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Reader Settings")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: { showingSettings = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider()
                    .background(Color.white.opacity(0.1))

                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: Voice Section
                        voiceSection
                            .padding(.top, 16)

                        // Divider
                        sectionDivider

                        // MARK: Playback Speed Section
                        speedSection

                        // Divider
                        sectionDivider

                        // MARK: Text Appearance Section
                        textAppearanceSection
                            .padding(.bottom, 24)
                    }
                }
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.75)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(.horizontal, 20)
        }
        .alert("Download \(pendingDownloadVoiceName) Voices", isPresented: $showDownloadConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To get \(pendingDownloadVoiceName.lowercased()) voices:\n\n1. Open the Settings app\n2. Go to Accessibility\n3. Tap Spoken Content\n4. Tap Voices\n5. Select English\n6. Download voices (look for \(pendingDownloadVoiceName))\n\nReturn here after downloading.")
        }
    }

    // MARK: - Voice Section
    // Note: Siri voices are NOT available to third-party apps via AVSpeechSynthesizer (Apple restriction)
    // We only show Premium, Enhanced, and Standard tiers
    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VOICE")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 4) {
                let premiumVoices = TTSManager.premiumVoices
                let enhancedVoices = TTSManager.enhancedVoices
                let standardVoices = TTSManager.standardVoices

                // Premium Voices Section
                voiceTierSection(
                    tier: .premium,
                    voices: premiumVoices,
                    isExpanded: $showPremiumVoices
                )

                // Enhanced Voices Section
                voiceTierSection(
                    tier: .enhanced,
                    voices: enhancedVoices,
                    isExpanded: $showEnhancedVoices
                )

                // Standard Voices Section
                voiceTierSection(
                    tier: .standard,
                    voices: standardVoices,
                    isExpanded: $showDefaultVoices
                )
            }
        }
        // All voice sections start collapsed - user can expand as needed
    }

    // Voice quality tier enum for styling
    // Note: Siri voices are NOT available via AVSpeechSynthesizer API (Apple restriction)
    private enum VoiceTier {
        case premium
        case enhanced
        case standard

        var title: String {
            switch self {
            case .premium: return "Premium"
            case .enhanced: return "Enhanced"
            case .standard: return "Standard"
            }
        }

        var icon: String {
            switch self {
            case .premium: return "star.fill"
            case .enhanced: return "wand.and.stars"
            case .standard: return "speaker.wave.2"
            }
        }

        var iconColor: Color {
            switch self {
            case .premium: return .yellow
            case .enhanced: return .cyan
            case .standard: return .gray
            }
        }

        var description: String {
            switch self {
            case .premium: return "Highest quality, most natural"
            case .enhanced: return "High quality voices"
            case .standard: return "Basic system voices"
            }
        }
    }

    // MARK: - Voice Tier Section
    private func voiceTierSection(
        tier: VoiceTier,
        voices: [AVSpeechSynthesisVoice],
        isExpanded: Binding<Bool>
    ) -> some View {
        VStack(spacing: 0) {
            // Header button
            Button(action: {
                if voices.isEmpty && tier != .standard {
                    // Show download prompt for empty siri/premium/enhanced tiers
                    pendingDownloadVoiceName = tier.title
                    showDownloadConfirmation = true
                } else if !voices.isEmpty {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.wrappedValue.toggle()
                    }
                }
            }) {
                HStack(spacing: 10) {
                    // Chevron (only show if has voices)
                    if !voices.isEmpty {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 14)
                    } else {
                        // Download icon for empty tiers
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(tier != .standard ? tier.iconColor.opacity(0.7) : .secondary)
                            .frame(width: 14)
                    }

                    // Tier icon
                    Image(systemName: tier.icon)
                        .font(.system(size: 14))
                        .foregroundColor(voices.isEmpty ? tier.iconColor.opacity(0.5) : tier.iconColor)
                        .frame(width: 20)

                    // Title and count
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(tier.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(voices.isEmpty ? .white.opacity(0.5) : .white)

                            if !voices.isEmpty {
                                Text("(\(voices.count))")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }

                        if voices.isEmpty {
                            Text(tier != .standard ? "Tap to download" : "None available")
                                .font(.caption2)
                                .foregroundColor(tier != .standard ? tier.iconColor.opacity(0.7) : .secondary)
                        } else if !isExpanded.wrappedValue {
                            Text(tier.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Download badge for empty premium/enhanced
                    if voices.isEmpty && tier != .standard {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                            .foregroundColor(tier.iconColor.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isExpanded.wrappedValue && !voices.isEmpty ? tier.iconColor.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded content
            if isExpanded.wrappedValue && !voices.isEmpty {
                VStack(spacing: 0) {
                    ForEach(voices, id: \.identifier) { voice in
                        voiceRow(voice: voice, tier: tier)
                    }
                }
                .padding(.leading, 44) // Indent under the header
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Voice Row
    private func voiceRow(voice: AVSpeechSynthesisVoice, tier: VoiceTier) -> some View {
        let isSelected = tts.selectedVoiceIdentifier == voice.identifier
        let metadata = TTSManager.voiceMetadata(for: voice)

        return Button(action: {
            tts.selectedVoiceIdentifier = voice.identifier
        }) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? tier.iconColor : .white.opacity(0.25))
                    .frame(width: 22)

                // Voice info
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.9))

                    HStack(spacing: 4) {
                        if !metadata.region.isEmpty {
                            Text(metadata.region)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if !metadata.gender.isEmpty {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(metadata.gender)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Preview button
                Button(action: {
                    tts.previewVoice(identifier: voice.identifier)
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(tier.iconColor.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? tier.iconColor.opacity(0.12) : Color.clear)
            )
            .padding(.trailing, 20)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Speed Section
    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PLAYBACK SPEED")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                HStack {
                    Text("Speed")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text("\(String(format: "%.2f", tts.playbackSpeed))×")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.royalPurple)
                }

                Slider(
                    value: Binding(
                        get: { Double(tts.playbackSpeed) },
                        set: { tts.playbackSpeed = Float($0) }
                    ),
                    in: 0.5...2.0,
                    step: 0.05
                )
                .tint(.royalPurple)

                HStack {
                    Text("0.5×")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("2.0×")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Text Appearance Section
    private var textAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEXT APPEARANCE")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 16) {
                // Line Spacing
                VStack(alignment: .leading, spacing: 8) {
                    Text("Line Spacing")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))

                    HStack(spacing: 8) {
                        spacingButton(title: "Tight", value: 2.0, selection: $lineSpacing)
                        spacingButton(title: "Normal", value: 6.0, selection: $lineSpacing)
                        spacingButton(title: "Relaxed", value: 12.0, selection: $lineSpacing)
                    }
                }

                // Paragraph Spacing
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paragraph Spacing")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))

                    HStack(spacing: 8) {
                        spacingButton(title: "Compact", value: 0.0, selection: $paragraphSpacing)
                        spacingButton(title: "Normal", value: 6.0, selection: $paragraphSpacing)
                        spacingButton(title: "Relaxed", value: 14.0, selection: $paragraphSpacing)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Section Divider
    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }
    
    private func spacingButton(title: String, value: CGFloat, selection: Binding<CGFloat>) -> some View {
        Button(action: { withAnimation(.spring()) { selection.wrappedValue = value } }) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selection.wrappedValue == value ? Color.royalPurple : Color.white.opacity(0.1))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Navigation Helpers
    private func goToPreviousChapter() {
        if currentChapterIndex > 0 {
            tts.stop()
            withAnimation { currentChapterIndex -= 1 }
        }
    }

    private func goToNextChapter() {
        if currentChapterIndex < article.chapters.count - 1 {
            tts.stop()
            withAnimation { currentChapterIndex += 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { tts.play() }
        }
    }
    
    // MARK: - Overlays (Chapter List)
    private var chapterListOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { showingChapterList = false }
            VStack(spacing: 0) {
                HStack {
                    Text("Chapters").font(.headline)
                    Spacer()
                    Button(action: { showingChapterList = false }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundColor(.secondary)
                    }
                }
                .padding()
                Divider()
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(article.chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button(action: {
                                currentChapterIndex = index
                                showingChapterList = false
                            }) {
                                HStack {
                                    Text("\(index + 1)").font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(index == currentChapterIndex ? .royalPurple : .secondary)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chapter.title).font(.system(size: 15, weight: index == currentChapterIndex ? .semibold : .regular))
                                            .foregroundColor(.primary).lineLimit(2)
                                        Text("\(chapter.wordCount) words").font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if index == currentChapterIndex { Image(systemName: "checkmark.circle.fill").foregroundColor(.royalPurple) }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(index == currentChapterIndex ? Color.royalPurple.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.6).background(.ultraThinMaterial).cornerRadius(20).padding(.horizontal, 20)
        }
    }
}

// MARK: - UNIFIED READER TEXT VIEW (Cleaned & Snapping)

struct UnifiedReaderTextView: UIViewRepresentable {
    let articleTitle: String
    let author: String?
    let source: String
    let chapterTitle: String?
    let content: String
    let formattingSpans: [FormattingSpan]?
    let images: [ArticleImage]?
    let highlightRange: NSRange
    let isPlaying: Bool

    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat

    let onTapWord: (Int) -> Void
    let onLinkTapped: ((URL) -> Void)?

    private let contentOffset: Int
    private let fullAttributedText: NSAttributedString

    init(articleTitle: String,
         author: String?,
         source: String,
         chapterTitle: String?,
         content: String,
         formattingSpans: [FormattingSpan]? = nil,
         images: [ArticleImage]? = nil,
         highlightRange: NSRange,
         isPlaying: Bool,
         lineSpacing: CGFloat,
         paragraphSpacing: CGFloat,
         onTapWord: @escaping (Int) -> Void,
         onLinkTapped: ((URL) -> Void)? = nil) {

        self.articleTitle = articleTitle
        self.author = author
        self.source = source
        self.chapterTitle = chapterTitle
        self.content = content
        self.formattingSpans = formattingSpans
        self.images = images
        self.highlightRange = highlightRange
        self.isPlaying = isPlaying
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.onTapWord = onTapWord
        self.onLinkTapped = onLinkTapped

        // Construct Full Text
        let combined = NSMutableAttributedString()

        // -- HEADER --
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.alignment = .left
        headerStyle.paragraphSpacing = 8

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.label,
            .paragraphStyle: headerStyle
        ]
        combined.append(NSAttributedString(string: articleTitle + "\n", attributes: titleAttrs))

        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .subheadline),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: headerStyle
        ]

        var metaString = source
        if let auth = author { metaString += " • \(auth)" }
        combined.append(NSAttributedString(string: metaString + "\n\n", attributes: metaAttrs))

        if let chTitle = chapterTitle {
            let chAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.systemPurple,
                .paragraphStyle: headerStyle
            ]
            combined.append(NSAttributedString(string: chTitle + "\n\n", attributes: chAttrs))
        }

        self.contentOffset = combined.length

        // -- BODY --
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = lineSpacing
        bodyStyle.paragraphSpacing = paragraphSpacing

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: UIColor.label,
            .paragraphStyle: bodyStyle
        ]

        // Content is already cleaned by parent view
        let bodyText = NSMutableAttributedString(string: content, attributes: bodyAttrs)

        // Apply formatting spans
        if let spans = formattingSpans {
            let baseFont = UIFont.systemFont(ofSize: 18, weight: .regular)
            let boldFont = UIFont.systemFont(ofSize: 18, weight: .bold)
            let italicFont = UIFont.italicSystemFont(ofSize: 18)
            let boldItalicFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) ?? baseFont.fontDescriptor, size: 18)
            let codeFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)

            for span in spans {
                // Convert character indices to NSRange safely
                guard span.location >= 0, span.length > 0 else { continue }
                let endLocation = span.location + span.length
                guard endLocation <= content.count else { continue }

                let startIdx = content.index(content.startIndex, offsetBy: span.location)
                let endIdx = content.index(content.startIndex, offsetBy: endLocation)
                let nsRange = NSRange(startIdx..<endIdx, in: content)

                guard nsRange.location != NSNotFound, nsRange.location + nsRange.length <= bodyText.length else { continue }

                switch span.style {
                case .bold:
                    bodyText.addAttribute(.font, value: boldFont, range: nsRange)
                case .italic:
                    bodyText.addAttribute(.font, value: italicFont, range: nsRange)
                case .boldItalic:
                    bodyText.addAttribute(.font, value: boldItalicFont, range: nsRange)
                case .header1:
                    let h1Font = UIFont.systemFont(ofSize: 26, weight: .bold)
                    bodyText.addAttribute(.font, value: h1Font, range: nsRange)
                case .header2:
                    let h2Font = UIFont.systemFont(ofSize: 22, weight: .bold)
                    bodyText.addAttribute(.font, value: h2Font, range: nsRange)
                case .header3:
                    let h3Font = UIFont.systemFont(ofSize: 19, weight: .semibold)
                    bodyText.addAttribute(.font, value: h3Font, range: nsRange)
                case .blockquote:
                    bodyText.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: nsRange)
                    bodyText.addAttribute(.font, value: italicFont, range: nsRange)
                case .link:
                    bodyText.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: nsRange)
                    bodyText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                    if let urlString = span.url, let url = URL(string: urlString) {
                        bodyText.addAttribute(.link, value: url, range: nsRange)
                    }
                case .code, .preformatted:
                    bodyText.addAttribute(.font, value: codeFont, range: nsRange)
                    bodyText.addAttribute(.backgroundColor, value: UIColor.systemGray5, range: nsRange)
                case .listItem:
                    break // List items are already formatted with bullets in text
                case .caption:
                    // Captions: smaller, italic, gray - visible but distinct
                    let captionFont = UIFont.italicSystemFont(ofSize: 14)
                    bodyText.addAttribute(.font, value: captionFont, range: nsRange)
                    bodyText.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: nsRange)
                }
            }
        }

        // Insert images at their placeholder positions (reverse order to preserve indices)
        if let articleImages = images {
            print("🖼️ [DISPLAY] Have \(articleImages.count) images to display")
            // Sort by location descending so we can insert without affecting earlier positions
            let sortedImages = articleImages.sorted { $0.location > $1.location }

            for articleImage in sortedImages {
                // Find the placeholder character position
                let placeholderLocation = articleImage.location
                print("🖼️ [DISPLAY] Image at location \(placeholderLocation), localPath: \(articleImage.localPath ?? "nil")")
                guard placeholderLocation >= 0, placeholderLocation < bodyText.length else {
                    print("🖼️ [DISPLAY] ❌ Location out of bounds (bodyText.length: \(bodyText.length))")
                    continue
                }

                // Load the image
                if let uiImage = ArticleExtractor.loadImage(for: articleImage) {
                    print("🖼️ [DISPLAY] ✅ Loaded image: \(uiImage.size)")
                    // Calculate width to fit screen width minus padding (16pt each side + textContainer insets)
                    let screenWidth = UIScreen.main.bounds.width
                    let horizontalPadding: CGFloat = 40  // 16pt padding + textContainerInset
                    let maxWidth = screenWidth - horizontalPadding

                    // Scale image to fit width while maintaining aspect ratio
                    let aspectRatio = uiImage.size.height / uiImage.size.width
                    let displayWidth = maxWidth
                    // Cap height to avoid absurdly tall images
                    let displayHeight = min(displayWidth * aspectRatio, 500)

                    print("🖼️ [DISPLAY] Rendering at size: \(displayWidth) x \(displayHeight)")

                    // Create scaled image
                    let scaledSize = CGSize(width: displayWidth, height: displayHeight)
                    let renderer = UIGraphicsImageRenderer(size: scaledSize)
                    let scaledImage = renderer.image { ctx in
                        uiImage.draw(in: CGRect(origin: .zero, size: scaledSize))
                    }

                    // Create text attachment with the image
                    let attachment = NSTextAttachment()
                    attachment.image = scaledImage

                    // Create attributed string with attachment
                    let imageString = NSMutableAttributedString(attachment: attachment)

                    // Add a newline after the image for spacing
                    imageString.append(NSAttributedString(string: "\n"))

                    // Replace the placeholder character with the image
                    let placeholderRange = NSRange(location: placeholderLocation, length: 1)
                    bodyText.replaceCharacters(in: placeholderRange, with: imageString)
                    print("🖼️ [DISPLAY] ✅ Replaced placeholder at \(placeholderLocation), bodyText length now: \(bodyText.length)")
                } else {
                    print("🖼️ [DISPLAY] ❌ Failed to load image from: \(articleImage.localPath ?? "nil")")
                }
            }
        } else {
            print("🖼️ [DISPLAY] No images array passed to view")
        }

        combined.append(bodyText)
        self.fullAttributedText = combined
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: UIScreen.main.bounds.height / 2, right: 16)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        textView.addGestureRecognizer(tapGesture)
        
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.attributedText.string != fullAttributedText.string ||
           !textView.attributedText.isEqual(to: fullAttributedText) {
             if !isPlaying {
                 textView.attributedText = fullAttributedText
             }
        }
        
        if isPlaying && highlightRange.location != NSNotFound {
            let mutableText = NSMutableAttributedString(attributedString: fullAttributedText)
            
            let viewLocation = highlightRange.location + contentOffset
            let viewLength = highlightRange.length
            
            if viewLocation + viewLength <= mutableText.length {
                // FIXED: Snap to Word Boundaries
                // If TTS returns "art" of "smart", we expand to "smart"
                let rawRange = NSRange(location: viewLocation, length: viewLength)
                let snappedRange = snapToWordBoundary(text: mutableText.string, range: rawRange)
                
                let highlightAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor.white,
                    .backgroundColor: UIColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1.0)
                ]
                mutableText.addAttributes(highlightAttrs, range: snappedRange)
                textView.attributedText = mutableText
                
                DispatchQueue.main.async {
                    let layoutManager = textView.layoutManager
                    let textContainer = textView.textContainer
                    
                    layoutManager.ensureLayout(for: textContainer)
                    
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: snappedRange, actualCharacterRange: nil)
                    let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    
                    let viewHeight = textView.bounds.height
                    let targetOffsetY = rect.origin.y - (viewHeight * 0.4)
                    
                    let maxOffset = textView.contentSize.height - viewHeight + textView.contentInset.bottom
                    let clampedOffset = max(0 - textView.contentInset.top, min(targetOffsetY, maxOffset))
                    
                    if abs(textView.contentOffset.y - clampedOffset) > 20 {
                        textView.setContentOffset(CGPoint(x: 0, y: clampedOffset), animated: true)
                    }
                }
            }
        }
        
        context.coordinator.onTap = onTapWord
        context.coordinator.contentOffset = contentOffset
    }
    
    // NEW HELPER: Ensures full words are highlighted even if TTS range is partial
    func snapToWordBoundary(text: String, range: NSRange) -> NSRange {
        let nsString = text as NSString
        guard range.location < nsString.length else { return range }
        
        var start = range.location
        var end = range.location + range.length
        
        // Expand start left
        while start > 0 {
            let char = nsString.character(at: start - 1)
            if CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(char)!) {
                break
            }
            start -= 1
        }
        
        // Expand end right
        while end < nsString.length {
            let char = nsString.character(at: end)
            if CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(char)!) {
                break
            }
            end += 1
        }
        
        return NSRange(location: start, length: end - start)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(contentOffset: contentOffset, onTap: onTapWord)
    }

    class Coordinator: NSObject {
        var contentOffset: Int
        var onTap: (Int) -> Void

        init(contentOffset: Int, onTap: @escaping (Int) -> Void) {
            self.contentOffset = contentOffset
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            let location = gesture.location(in: textView)
            
            var point = location
            point.x -= textView.textContainerInset.left
            point.y -= textView.textContainerInset.top

            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer
            let characterIndex = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            
            let bodyIndex = characterIndex - contentOffset
            if bodyIndex >= 0 {
                let text = textView.text ?? ""
                let nsText = text as NSString
                if characterIndex < nsText.length {
                    var wordStart = characterIndex
                    while wordStart > contentOffset {
                        let prevChar = nsText.character(at: wordStart - 1)
                        if CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(prevChar)!) {
                            break
                        }
                        wordStart -= 1
                    }
                    onTap(wordStart - contentOffset)
                }
            }
        }
    }
}
