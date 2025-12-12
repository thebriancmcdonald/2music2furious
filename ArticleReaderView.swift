//
//  ArticleReaderView.swift
//  2 Music 2 Furious
//
//  Full-screen article reader with text-to-speech
//  Features: Word highlighting, tap-to-seek, chapter navigation
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
    @State private var lastScrolledCharPosition: Int = -1  // Track last scrolled character position

    var currentChapter: ArticleChapter {
        guard article.chapters.indices.contains(currentChapterIndex) else {
            return article.chapters.first ?? ArticleChapter(title: "Empty", content: "No content")
        }
        return article.chapters[currentChapterIndex]
    }

    var body: some View {
        ZStack {
            // Background
            GlassBackgroundView(primaryColor: .royalPurple, secondaryColor: .blue)

            VStack(spacing: 0) {
                // Content
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Header
                            articleHeader

                            // Chapter Title (if multiple chapters)
                            if article.chapters.count > 1 {
                                chapterHeader
                            }

                            // Article Content with highlighting
                            HighlightedTextView(
                                text: currentChapter.content,
                                highlightRange: tts.currentWordRange,
                                isPlaying: tts.isPlaying,
                                onTapWord: { position in
                                    // Reset scroll tracker so auto-scroll works from new position
                                    lastScrolledCharPosition = position
                                    // Use seekAndPlay to avoid race conditions
                                    tts.seekAndPlay(to: position)
                                }
                            )
                            .id("content")
                            .padding(.horizontal)

                            // Chapter navigation at bottom
                            if article.chapters.count > 1 {
                                chapterNavigation
                                    .padding(.top, 20)
                            }

                            // Bottom padding for controls
                            Color.clear.frame(height: 120)
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: tts.currentWordRange) { newRange in
                        // Auto-scroll when TTS is playing to keep spoken word visible
                        guard tts.isPlaying,
                              newRange.location != NSNotFound,
                              !currentChapter.content.isEmpty else { return }

                        let currentPos = newRange.location
                        // Use NSString length to match NSRange positions from TTS
                        let textLength = (currentChapter.content as NSString).length

                        // Only scroll if we've moved forward by ~200 characters or jumped backward
                        // This keeps the word visible without constant micro-scrolling
                        let movedForward = currentPos > lastScrolledCharPosition + 200
                        let jumpedBackward = currentPos < lastScrolledCharPosition - 50

                        if movedForward || jumpedBackward || lastScrolledCharPosition < 0 {
                            lastScrolledCharPosition = currentPos

                            // Calculate progress and position the spoken word ~25% from top
                            let progress = Double(currentPos) / Double(max(textLength, 1))
                            let anchorY = max(0.0, min(progress - 0.08, 0.92))

                            withAnimation(.easeInOut(duration: 0.5)) {
                                scrollProxy.scrollTo("content", anchor: UnitPoint(x: 0.5, y: anchorY))
                            }
                        }
                    }
                }

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
                // Chapter selector in nav bar
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
            // Restore reading position
            currentChapterIndex = article.lastReadChapter
            loadChapterForTTS()

            // Handle chapter finished
            tts.onChapterFinished = {
                goToNextChapter()
            }
        }
        .onDisappear {
            // Stop TTS and save position
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
        tts.loadText(currentChapter.content)
        lastScrolledCharPosition = -1  // Reset scroll tracking for new chapter

        // Restore position if this is the saved chapter
        if currentChapterIndex == article.lastReadChapter && article.lastReadPosition > 0 {
            tts.seek(to: article.lastReadPosition)
        }
    }

    // MARK: - Article Header

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(article.title)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                if let author = article.author {
                    Label(author, systemImage: "person")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Label(article.displaySource, systemImage: "globe")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(article.formattedReadingTime)
                    .font(.subheadline)
                    .foregroundColor(.royalPurple)
            }

            Divider()
                .background(Color.white.opacity(0.2))
        }
        .padding(.horizontal)
    }

    // MARK: - Chapter Header

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CHAPTER \(currentChapterIndex + 1)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.royalPurple)

            Text(currentChapter.title)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundColor(.primary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Chapter Navigation

    private var chapterNavigation: some View {
        HStack(spacing: 16) {
            Button(action: { goToPreviousChapter() }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Previous")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(currentChapterIndex > 0 ? .royalPurple : .secondary.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            }
            .disabled(currentChapterIndex == 0)

            Spacer()

            Button(action: { goToNextChapter() }) {
                HStack {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(currentChapterIndex < article.chapters.count - 1 ? .royalPurple : .secondary.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            }
            .disabled(currentChapterIndex >= article.chapters.count - 1)
        }
        .padding(.horizontal)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))

                    Rectangle()
                        .fill(Color.royalPurple)
                        .frame(width: geo.size.width * tts.progress)
                }
            }
            .frame(height: 3)

            HStack(spacing: 20) {
                // Chapter indicator
                if article.chapters.count > 1 {
                    Button(action: { showingChapterList = true }) {
                        VStack(spacing: 2) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 16))
                            Text("\(currentChapterIndex + 1)/\(article.chapters.count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                    }
                }

                Spacer()

                // Skip back (10 words)
                Button(action: { tts.skipBackward(words: 15) }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                }

                // Play/Pause
                Button(action: { tts.togglePlayPause() }) {
                    Image(systemName: tts.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.royalPurple))
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                }

                // Skip forward (30 words)
                Button(action: { tts.skipForward(words: 30) }) {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                }

                Spacer()

                // Speed control
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

    // MARK: - Chapter List Overlay

    private var chapterListOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showingChapterList = false }

            VStack(spacing: 0) {
                HStack {
                    Text("Chapters")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingChapterList = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
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
                                    Text("\(index + 1)")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(index == currentChapterIndex ? .royalPurple : .secondary)
                                        .frame(width: 30)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chapter.title)
                                            .font(.system(size: 15, weight: index == currentChapterIndex ? .semibold : .regular))
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)

                                        Text("\(chapter.wordCount) words · \(chapter.estimatedReadingTime) min")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if index == currentChapterIndex {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.royalPurple)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    index == currentChapterIndex
                                        ? Color.royalPurple.opacity(0.1)
                                        : Color.clear
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(.horizontal, 20)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: showingChapterList)
    }

    // MARK: - Settings Overlay

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showingSettings = false }

            VStack(spacing: 0) {
                HStack {
                    Text("Reader Settings")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingSettings = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()

                Divider()

                VStack(spacing: 20) {
                    // Voice selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TTSManager.availableVoices.prefix(6), id: \.identifier) { voice in
                                    Button(action: {
                                        tts.selectedVoiceIdentifier = voice.identifier
                                    }) {
                                        VStack(spacing: 4) {
                                            Text(voice.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)

                                            if voice.quality == .enhanced {
                                                Text("Enhanced")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            tts.selectedVoiceIdentifier == voice.identifier
                                                ? Color.royalPurple
                                                : Color.white.opacity(0.1)
                                        )
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Speed slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Speed")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(String(format: "%.2f", tts.playbackSpeed))x")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.royalPurple)
                        }

                        Slider(value: Binding(
                            get: { Double(tts.playbackSpeed) },
                            set: { tts.playbackSpeed = Float($0) }
                        ), in: 0.5...2.0, step: 0.25)
                        .tint(.royalPurple)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 20)
            }
            .frame(maxHeight: 300)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(.horizontal, 20)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: showingSettings)
    }

    // MARK: - Navigation Helpers

    private func goToPreviousChapter() {
        if currentChapterIndex > 0 {
            tts.stop()
            withAnimation {
                currentChapterIndex -= 1
            }
        }
    }

    private func goToNextChapter() {
        if currentChapterIndex < article.chapters.count - 1 {
            tts.stop()
            withAnimation {
                currentChapterIndex += 1
            }
            // Auto-play next chapter
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                tts.play()
            }
        }
    }
}

// MARK: - Highlighted Text View with Tap-to-Seek

struct HighlightedTextView: View {
    let text: String
    let highlightRange: NSRange
    let isPlaying: Bool
    let onTapWord: (Int) -> Void

    var body: some View {
        TappableTextView(
            text: text,
            highlightRange: highlightRange,
            isPlaying: isPlaying,
            onTap: onTapWord
        )
        .fixedSize(horizontal: false, vertical: true)  // Allow full vertical expansion
    }
}

// UITextView wrapper for accurate tap-to-seek
struct TappableTextView: UIViewRepresentable {
    let text: String
    let highlightRange: NSRange
    let isPlaying: Bool
    let onTap: (Int) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        textView.addGestureRecognizer(tapGesture)

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Create attributed string
        let attributedString = NSMutableAttributedString(string: text)

        // IMPORTANT: Use NSString length for NSRange operations (UTF-16 code units)
        // Swift String.count uses grapheme clusters which differs for emoji/special chars
        let nsTextLength = (text as NSString).length

        // Base style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        paragraphStyle.lineBreakMode = .byWordWrapping

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]

        attributedString.addAttributes(baseAttributes, range: NSRange(location: 0, length: nsTextLength))

        // Apply highlight ONLY to the current word (not everything after)
        // Cap highlight length to reasonable word size (max 50 chars)
        if isPlaying && highlightRange.location != NSNotFound && highlightRange.length > 0 {
            let safeLocation = min(highlightRange.location, nsTextLength)
            // Cap length to actual word length, max 50 characters
            let maxWordLength = min(highlightRange.length, 50)
            let safeLength = min(maxWordLength, max(0, nsTextLength - safeLocation))

            if safeLength > 0 {
                let highlightAttributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor.white,
                    .backgroundColor: UIColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1.0) // Royal purple
                ]
                attributedString.addAttributes(highlightAttributes, range: NSRange(location: safeLocation, length: safeLength))
            }
        }

        textView.attributedText = attributedString

        // Force layout update to ensure full content is shown
        textView.setNeedsLayout()
        textView.layoutIfNeeded()

        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        var onTap: (Int) -> Void

        init(onTap: @escaping (Int) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }

            let location = gesture.location(in: textView)

            // Get character index at tap location
            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer

            // Account for text container inset
            var point = location
            point.x -= textView.textContainerInset.left
            point.y -= textView.textContainerInset.top

            // Get the character index
            let characterIndex = layoutManager.characterIndex(
                for: point,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            // Find the start of the word at this position
            let text = textView.text ?? ""
            let nsText = text as NSString
            var wordStart = characterIndex

            // Move backward to find word start
            while wordStart > 0 {
                let prevChar = nsText.character(at: wordStart - 1)
                if CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(prevChar)!) {
                    break
                }
                wordStart -= 1
            }

            onTap(wordStart)
        }
    }

    // Calculate intrinsic size to show all content
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}
