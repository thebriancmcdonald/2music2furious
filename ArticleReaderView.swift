//
//  ArticleReaderView.swift
//  2 Music 2 Furious
//
//  Full-screen article reader with chapter navigation
//  Phase 1: Display only - TTS will be added in Phase 2
//

import SwiftUI

struct ArticleReaderView: View {
    let article: Article
    @ObservedObject var articleManager: ArticleManager
    @ObservedObject var speechPlayer: AudioPlayer

    @Environment(\.dismiss) private var dismiss

    @State private var currentChapterIndex: Int = 0
    @State private var showingChapterList = false
    @State private var scrollOffset: CGFloat = 0

    // TTS placeholders for Phase 2
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 1.0

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
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        articleHeader

                        // Chapter Title (if multiple chapters)
                        if article.chapters.count > 1 {
                            chapterHeader
                        }

                        // Article Content
                        Text(currentChapter.content)
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundColor(.primary)
                            .lineSpacing(8)
                            .padding(.horizontal)

                        // Chapter navigation at bottom
                        if article.chapters.count > 1 {
                            chapterNavigation
                                .padding(.top, 20)
                        }

                        // Bottom padding for controls
                        Color.clear.frame(height: 100)
                    }
                    .padding(.vertical)
                }

                // Playback Controls (Phase 2 - currently placeholder)
                playbackControls
            }

            // Chapter list overlay
            if showingChapterList {
                chapterListOverlay
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
        }
        .onAppear {
            // Restore reading position
            currentChapterIndex = article.lastReadChapter
        }
        .onDisappear {
            // Save reading position
            articleManager.updateProgress(
                articleId: article.id,
                chapterIndex: currentChapterIndex,
                position: 0 // Character position - will be more precise with TTS
            )
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
            // Previous Chapter
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

            // Next Chapter
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
            Divider()
                .background(Color.white.opacity(0.2))

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

                // Skip back
                Button(action: { /* Phase 2: TTS skip back */ }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 44, height: 44)
                }
                .disabled(true) // Phase 2

                // Play/Pause
                Button(action: { /* Phase 2: TTS play/pause */ }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.royalPurple.opacity(0.5)))
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                }
                .disabled(true) // Phase 2

                // Skip forward
                Button(action: { /* Phase 2: TTS skip forward */ }) {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 44, height: 44)
                }
                .disabled(true) // Phase 2

                Spacer()

                // Speed control
                Button(action: { /* Phase 2: cycle speed */ }) {
                    Text("\(String(format: "%.1f", playbackSpeed))x")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .disabled(true) // Phase 2
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Chapter List Overlay

    private var chapterListOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showingChapterList = false }

            // Chapter list
            VStack(spacing: 0) {
                // Header
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

                // Chapter list
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

    // MARK: - Navigation Helpers

    private func goToPreviousChapter() {
        if currentChapterIndex > 0 {
            withAnimation {
                currentChapterIndex -= 1
            }
        }
    }

    private func goToNextChapter() {
        if currentChapterIndex < article.chapters.count - 1 {
            withAnimation {
                currentChapterIndex += 1
            }
        }
    }
}
