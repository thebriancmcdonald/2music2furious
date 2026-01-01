//
//  ArticleReaderView.swift
//  2 Music 2 Furious
//
//  Full-screen article reader with text-to-speech
//  RICH TEXT UPDATE: Applies FormattingSpans for Instapaper-style reading
//  
//  Key Features:
//  - Rich formatting (bold, italic, headers, blockquotes, links)
//  - TTS sync preserved (plain text indices match display)
//  - Tappable links open in Safari
//  - Word highlighting during playback
//

import SwiftUI
import AVFoundation
import UIKit

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
    
    // Content for display and TTS
    // The ArticleExtractor already handles whitespace normalization,
    // so we use content directly when we have formatting spans.
    var cleanedContent: String {
        // With rich formatting, use content as-is (spans are aligned to it)
        if currentChapter.formattingSpans != nil && !currentChapter.formattingSpans!.isEmpty {
            return currentChapter.content
        }
        
        // Legacy plain-text articles: minimal cleanup
        return currentChapter.content
    }
    
    // Formatting spans adjusted for cleaned content (if needed)
    var adjustedSpans: [FormattingSpan]? {
        // For now, spans should already align with content
        // If cleaning changes indices, we'd need to adjust here
        return currentChapter.formattingSpans
    }

    var body: some View {
        ZStack {
            // Background
            GlassBackgroundView(primaryColor: .royalPurple, secondaryColor: .blue)

            VStack(spacing: 0) {
                // RICH TEXT READER VIEW
                RichTextReaderView(
                    articleTitle: article.title,
                    author: article.author,
                    source: article.displaySource,
                    chapterTitle: article.chapters.count > 1 ? currentChapter.title : nil,
                    content: cleanedContent,
                    formattingSpans: adjustedSpans,
                    highlightRange: tts.currentWordRange,
                    isPlaying: tts.isPlaying,
                    lineSpacing: lineSpacing,
                    paragraphSpacing: paragraphSpacing,
                    onTapWord: { position in
                        tts.seekAndPlay(to: position)
                    },
                    onTapLink: { url in
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
        // Load the CLEANED content into TTS - indices match the visual view
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

// MARK: - RICH TEXT READER VIEW

/// UIViewRepresentable that renders rich text with formatting spans
/// Preserves TTS sync by using plain text indices
struct RichTextReaderView: UIViewRepresentable {
    let articleTitle: String
    let author: String?
    let source: String
    let chapterTitle: String?
    let content: String
    let formattingSpans: [FormattingSpan]?
    let highlightRange: NSRange
    let isPlaying: Bool
    
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    
    let onTapWord: (Int) -> Void
    let onTapLink: (URL) -> Void
    
    private let contentOffset: Int
    private let fullAttributedText: NSAttributedString
    private let linkRanges: [(NSRange, URL)]  // Store link locations for tap detection
    
    // Purple color matching app theme
    private static let purpleColor = UIColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 1.0)
    
    init(articleTitle: String,
         author: String?,
         source: String,
         chapterTitle: String?,
         content: String,
         formattingSpans: [FormattingSpan]?,
         highlightRange: NSRange,
         isPlaying: Bool,
         lineSpacing: CGFloat,
         paragraphSpacing: CGFloat,
         onTapWord: @escaping (Int) -> Void,
         onTapLink: @escaping (URL) -> Void) {
        
        self.articleTitle = articleTitle
        self.author = author
        self.source = source
        self.chapterTitle = chapterTitle
        self.content = content
        self.formattingSpans = formattingSpans
        self.highlightRange = highlightRange
        self.isPlaying = isPlaying
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.onTapWord = onTapWord
        self.onTapLink = onTapLink
        
        // Build the attributed string
        let (attributedString, offset, links) = Self.buildAttributedString(
            articleTitle: articleTitle,
            author: author,
            source: source,
            chapterTitle: chapterTitle,
            content: content,
            formattingSpans: formattingSpans,
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing
        )
        
        self.fullAttributedText = attributedString
        self.contentOffset = offset
        self.linkRanges = links
    }
    
    /// Builds the complete attributed string with header and formatted body
    private static func buildAttributedString(
        articleTitle: String,
        author: String?,
        source: String,
        chapterTitle: String?,
        content: String,
        formattingSpans: [FormattingSpan]?,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat
    ) -> (NSAttributedString, Int, [(NSRange, URL)]) {
        
        let combined = NSMutableAttributedString()
        var linkRanges: [(NSRange, URL)] = []
        
        // -- HEADER --
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.alignment = .left
        headerStyle.paragraphSpacing = 8
        
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: headerStyle
        ]
        combined.append(NSAttributedString(string: articleTitle + "\n", attributes: titleAttrs))
        
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .subheadline),
            .foregroundColor: UIColor.white.withAlphaComponent(0.6),
            .paragraphStyle: headerStyle
        ]
        
        var metaString = source
        if let auth = author { metaString += " • \(auth)" }
        combined.append(NSAttributedString(string: metaString + "\n\n", attributes: metaAttrs))
        
        if let chTitle = chapterTitle {
            let chAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: purpleColor,
                .paragraphStyle: headerStyle
            ]
            combined.append(NSAttributedString(string: chTitle + "\n\n", attributes: chAttrs))
        }
        
        let contentOffset = combined.length
        
        // -- BODY --
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = lineSpacing
        bodyStyle.paragraphSpacing = paragraphSpacing
        
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: UIColor.white,
            .paragraphStyle: bodyStyle
        ]
        
        // Start with plain body text
        let bodyText = NSMutableAttributedString(string: content, attributes: bodyAttrs)
        
        // Apply formatting spans
        // CRITICAL: Convert Character indices to UTF-16 NSRange for NSAttributedString
        // Swift String uses Character (grapheme cluster) counts, but NSAttributedString uses UTF-16
        if let spans = formattingSpans {
            for span in spans {
                guard span.location >= 0 && span.location + span.length <= content.count else { continue }
                
                // Safely convert Character indices to String.Index, then to NSRange
                let startIdx = content.index(content.startIndex, offsetBy: span.location)
                let endIdx = content.index(startIdx, offsetBy: span.length)
                let range = NSRange(startIdx..<endIdx, in: content)
                
                switch span.style {
                case .bold:
                    bodyText.addAttribute(.font, value: UIFont.systemFont(ofSize: 18, weight: .bold), range: range)
                    
                case .italic:
                    bodyText.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 18), range: range)
                    
                case .boldItalic:
                    if let descriptor = UIFont.systemFont(ofSize: 18, weight: .bold).fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
                        bodyText.addAttribute(.font, value: UIFont(descriptor: descriptor, size: 18), range: range)
                    }
                    
                case .header1:
                    let h1Style = NSMutableParagraphStyle()
                    h1Style.lineSpacing = lineSpacing
                    h1Style.paragraphSpacing = paragraphSpacing + 8
                    h1Style.paragraphSpacingBefore = 16
                    bodyText.addAttributes([
                        .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: h1Style
                    ], range: range)
                    
                case .header2:
                    let h2Style = NSMutableParagraphStyle()
                    h2Style.lineSpacing = lineSpacing
                    h2Style.paragraphSpacing = paragraphSpacing + 4
                    h2Style.paragraphSpacingBefore = 12
                    bodyText.addAttributes([
                        .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: h2Style
                    ], range: range)
                    
                case .header3:
                    let h3Style = NSMutableParagraphStyle()
                    h3Style.lineSpacing = lineSpacing
                    h3Style.paragraphSpacing = paragraphSpacing + 2
                    h3Style.paragraphSpacingBefore = 8
                    bodyText.addAttributes([
                        .font: UIFont.systemFont(ofSize: 19, weight: .semibold),
                        .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                        .paragraphStyle: h3Style
                    ], range: range)
                    
                case .blockquote:
                    let quoteStyle = NSMutableParagraphStyle()
                    quoteStyle.lineSpacing = lineSpacing
                    quoteStyle.paragraphSpacing = paragraphSpacing
                    quoteStyle.firstLineHeadIndent = 16
                    quoteStyle.headIndent = 16
                    quoteStyle.tailIndent = -8
                    bodyText.addAttributes([
                        .font: UIFont.italicSystemFont(ofSize: 17),
                        .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                        .backgroundColor: UIColor.white.withAlphaComponent(0.05),
                        .paragraphStyle: quoteStyle
                    ], range: range)
                    
                case .listItem:
                    let listStyle = NSMutableParagraphStyle()
                    listStyle.lineSpacing = lineSpacing
                    listStyle.paragraphSpacing = paragraphSpacing / 2
                    listStyle.firstLineHeadIndent = 0
                    listStyle.headIndent = 20
                    bodyText.addAttribute(.paragraphStyle, value: listStyle, range: range)
                    
                case .link:
                    bodyText.addAttributes([
                        .foregroundColor: purpleColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: purpleColor.withAlphaComponent(0.5)
                    ], range: range)
                    
                    // Store link range for tap detection
                    if let urlString = span.url, let url = URL(string: urlString) {
                        let adjustedRange = NSRange(location: range.location + contentOffset, length: range.length)
                        linkRanges.append((adjustedRange, url))
                    }
                    
                case .code:
                    bodyText.addAttributes([
                        .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                        .foregroundColor: UIColor(red: 0.9, green: 0.7, blue: 1.0, alpha: 1.0),
                        .backgroundColor: UIColor.white.withAlphaComponent(0.1)
                    ], range: range)
                    
                case .preformatted:
                    let preStyle = NSMutableParagraphStyle()
                    preStyle.lineSpacing = 4
                    preStyle.paragraphSpacing = paragraphSpacing
                    bodyText.addAttributes([
                        .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                        .foregroundColor: UIColor(red: 0.85, green: 0.85, blue: 0.9, alpha: 1.0),
                        .backgroundColor: UIColor.black.withAlphaComponent(0.3),
                        .paragraphStyle: preStyle
                    ], range: range)
                }
            }
        }
        
        combined.append(bodyText)
        return (combined, contentOffset, linkRanges)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: UIScreen.main.bounds.height / 2, right: 16)
        
        // Disable default link interaction (we handle it ourselves)
        textView.isSelectable = false
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        textView.addGestureRecognizer(tapGesture)
        
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Update coordinator with current values
        context.coordinator.onTapWord = onTapWord
        context.coordinator.onTapLink = onTapLink
        context.coordinator.contentOffset = contentOffset
        context.coordinator.linkRanges = linkRanges
        
        // Update text if changed (but not during playback to avoid flicker)
        if !isPlaying {
            if textView.attributedText.string != fullAttributedText.string {
                textView.attributedText = fullAttributedText
            }
        }
        
        // Apply highlighting during playback
        if isPlaying && highlightRange.location != NSNotFound {
            let mutableText = NSMutableAttributedString(attributedString: fullAttributedText)
            
            let viewLocation = highlightRange.location + contentOffset
            let viewLength = highlightRange.length
            
            if viewLocation + viewLength <= mutableText.length {
                // Snap to word boundaries for cleaner highlighting
                let rawRange = NSRange(location: viewLocation, length: viewLength)
                let snappedRange = snapToWordBoundary(text: mutableText.string, range: rawRange)
                
                let highlightAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor.white,
                    .backgroundColor: Self.purpleColor
                ]
                mutableText.addAttributes(highlightAttrs, range: snappedRange)
                textView.attributedText = mutableText
                
                // Auto-scroll to keep highlighted word visible
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
    }
    
    /// Ensures full words are highlighted even if TTS range is partial
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
        Coordinator(contentOffset: contentOffset, linkRanges: linkRanges, onTapWord: onTapWord, onTapLink: onTapLink)
    }

    class Coordinator: NSObject {
        var contentOffset: Int
        var linkRanges: [(NSRange, URL)]
        var onTapWord: (Int) -> Void
        var onTapLink: (URL) -> Void

        init(contentOffset: Int, linkRanges: [(NSRange, URL)], onTapWord: @escaping (Int) -> Void, onTapLink: @escaping (URL) -> Void) {
            self.contentOffset = contentOffset
            self.linkRanges = linkRanges
            self.onTapWord = onTapWord
            self.onTapLink = onTapLink
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
            
            // Check if tap is on a link first
            for (range, url) in linkRanges {
                if NSLocationInRange(characterIndex, range) {
                    onTapLink(url)
                    return
                }
            }
            
            // Otherwise, handle as word tap for TTS seeking
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
                    onTapWord(wordStart - contentOffset)
                }
            }
        }
    }
}

// MARK: - Legacy Support (Backward Compatibility)

/// Alias for old code that might reference UnifiedReaderTextView
typealias UnifiedReaderTextView = RichTextReaderView
