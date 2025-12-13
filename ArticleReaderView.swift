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
    
    // Appearance Settings
    @State private var lineSpacing: CGFloat = 8.0
    @State private var paragraphSpacing: CGFloat = 8.0

    var currentChapter: ArticleChapter {
        guard article.chapters.indices.contains(currentChapterIndex) else {
            return article.chapters.first ?? ArticleChapter(title: "Empty", content: "No content")
        }
        return article.chapters[currentChapterIndex]
    }
    
    // CRITICAL FIX: Centralized Content Cleaning
    // We must use EXACTLY the same string for both the Visual Text and the TTS Engine.
    // If we clean one but not the other, the character indices drift, causing "half-word" highlighting.
    var cleanedContent: String {
        return currentChapter.content
            .replacingOccurrences(of: "\n\n", with: "\n")
            .replacingOccurrences(of: "\r\n\r\n", with: "\n")
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
                    content: cleanedContent, // Pass the CLEANED content
                    highlightRange: tts.currentWordRange,
                    isPlaying: tts.isPlaying,
                    lineSpacing: lineSpacing,
                    paragraphSpacing: paragraphSpacing,
                    onTapWord: { position in
                        tts.seekAndPlay(to: position)
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
        // CRITICAL FIX: Load the CLEANED content into TTS.
        // Now indices match the visual view 1:1.
        tts.loadText(cleanedContent)
        
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
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { showingSettings = false }
            VStack(spacing: 0) {
                HStack {
                    Text("Reader Settings").font(.headline)
                    Spacer()
                    Button(action: { showingSettings = false }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundColor(.secondary)
                    }
                }
                .padding()
                Divider()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Voice Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Voice").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(TTSManager.availableVoices.prefix(6), id: \.identifier) { voice in
                                        Button(action: { tts.selectedVoiceIdentifier = voice.identifier }) {
                                            VStack(spacing: 4) {
                                                Text(voice.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(tts.selectedVoiceIdentifier == voice.identifier ? Color.royalPurple : Color.white.opacity(0.1))
                                            .foregroundColor(.white).cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Line Spacing
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Line Spacing").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                            HStack(spacing: 12) {
                                spacingButton(title: "Tight", value: 4.0, selection: $lineSpacing)
                                spacingButton(title: "Normal", value: 8.0, selection: $lineSpacing)
                                spacingButton(title: "Relaxed", value: 14.0, selection: $lineSpacing)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Paragraph Spacing
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paragraph Spacing").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                            HStack(spacing: 12) {
                                spacingButton(title: "Tight", value: 8.0, selection: $paragraphSpacing)
                                spacingButton(title: "Normal", value: 16.0, selection: $paragraphSpacing)
                                spacingButton(title: "Relaxed", value: 24.0, selection: $paragraphSpacing)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Speed
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Speed").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                                Spacer()
                                Text("\(String(format: "%.2f", tts.playbackSpeed))x").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.royalPurple)
                            }
                            Slider(value: Binding(get: { Double(tts.playbackSpeed) }, set: { tts.playbackSpeed = Float($0) }), in: 0.5...2.0, step: 0.25).tint(.royalPurple)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 20)
                }
            }
            .frame(maxHeight: 500)
            .background(.ultraThinMaterial).cornerRadius(20).padding(.horizontal, 20)
        }
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
    let highlightRange: NSRange
    let isPlaying: Bool
    
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    
    let onTapWord: (Int) -> Void
    
    private let contentOffset: Int
    private let fullAttributedText: NSAttributedString
    
    init(articleTitle: String,
         author: String?,
         source: String,
         chapterTitle: String?,
         content: String,
         highlightRange: NSRange,
         isPlaying: Bool,
         lineSpacing: CGFloat,
         paragraphSpacing: CGFloat,
         onTapWord: @escaping (Int) -> Void) {
        
        self.articleTitle = articleTitle
        self.author = author
        self.source = source
        self.chapterTitle = chapterTitle
        self.content = content
        self.highlightRange = highlightRange
        self.isPlaying = isPlaying
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.onTapWord = onTapWord
        
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
        combined.append(NSAttributedString(string: content, attributes: bodyAttrs))
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
