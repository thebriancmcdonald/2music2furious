//
//  BookLibraryView.swift
//  2 Music 2 Furious - MILESTONE 8.0
//
//  Audiobook library
//  Updates: Enhanced Detail View (Glass Header, Expandable Desc, Filter Bar)
//

import SwiftUI
import UniformTypeIdentifiers

struct BookLibraryView: View {
    @ObservedObject var bookManager: BookManager
    @ObservedObject var speechPlayer: AudioPlayer
    let dismiss: () -> Void
    
    @State private var showingFilePicker = false
    @State private var showingLibriVox = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                
                if bookManager.books.isEmpty { emptyStateView }
                else {
                    List {
                        ForEach(bookManager.books) { book in
                            ZStack {
                                NavigationLink(destination: LocalBookDetailView(book: book, bookManager: bookManager, onPlayChapter: { index in playBook(book, startingAt: index) })) { EmptyView() }.opacity(0)
                                GlassBookRow(book: book, onPlay: { playBook(book) })
                            }
                            .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) { Button(role: .destructive) { bookManager.removeBook(book) } label: { Label("Delete", systemImage: "trash") } }
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
                
                if showingToast {
                    VStack { Spacer(); BookToastView(message: toastMessage).padding(.bottom, 20) }
                        .transition(.move(edge: .bottom).combined(with: .opacity)).animation(.spring(), value: showingToast).zIndex(100)
                }
            }
            .navigationTitle("Books").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(action: { dismiss() }) { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary) } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingFilePicker = true } label: { Image(systemName: "square.and.arrow.up") }
                    Button { showingLibriVox = true } label: { Image(systemName: "magnifyingglass") }
                }
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in handleFileUpload(result: result) }
            .sheet(isPresented: $showingLibriVox) { LibriVoxSearchView(bookManager: bookManager, dismiss: { showingLibriVox = false }) }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack { Circle().fill(.ultraThinMaterial).frame(width: 120, height: 120); Image(systemName: "books.vertical").font(.system(size: 50)).foregroundColor(.secondary) }
            VStack(spacing: 8) { Text("Your Library is Empty").font(.title3.weight(.semibold)); Text("Import files from your device or\nsearch the public domain.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center) }.padding(.horizontal)
            HStack(spacing: 16) {
                glassButton(icon: "square.and.arrow.up", title: "Upload File", action: { showingFilePicker = true })
                glassButton(icon: "magnifyingglass", title: "Search LibriVox", action: { showingLibriVox = true })
            }.padding(.horizontal, 24).padding(.top, 10)
            Spacer()
        }
    }
    
    private func glassButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 24)); Text(title).font(.system(size: 14, weight: .medium)) }
                .foregroundColor(.primary).frame(maxWidth: .infinity).padding(.vertical, 20).background(.ultraThinMaterial).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1)).shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
    }
    
    private func handleFileUpload(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var uploadedTracks: [Track] = []
            for url in urls {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let filename = url.lastPathComponent
                    let destinationURL = documentsPath.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: destinationURL.path) { try FileManager.default.removeItem(at: destinationURL) }
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    let title = filename.replacingOccurrences(of: "_", with: " ").components(separatedBy: ".").dropLast().joined(separator: ".")
                    let track = Track(title: title, artist: "Audiobook", filename: filename)
                    uploadedTracks.append(track)
                }
            }
            if !uploadedTracks.isEmpty {
                let newBooks = bookManager.processUploadedTracks(uploadedTracks)
                for book in newBooks { bookManager.addBook(book) }
                showToast("Added \(newBooks.count) audiobook(s)")
            }
        } catch { print("Upload error: \(error)"); showToast("Upload failed") }
    }
    
    private func playBook(_ book: Book, startingAt index: Int? = nil) {
        speechPlayer.clearQueue()
        for chapter in book.chapters { speechPlayer.addTrackToQueue(chapter) }
        let startIndex = index ?? book.currentChapterIndex
        if speechPlayer.queue.count > 0 {
            let safeIndex = min(max(0, startIndex), speechPlayer.queue.count - 1)
            speechPlayer.loadTrack(at: safeIndex)
            speechPlayer.play()
        }
        dismiss()
    }
    
    private func showToast(_ message: String) {
        toastMessage = message; withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { showingToast = false } }
    }
}

// MARK: - Local Book Detail View (Refined)

struct LocalBookDetailView: View {
    let book: Book
    @ObservedObject var bookManager: BookManager
    let onPlayChapter: (Int) -> Void
    
    @State private var filter: FilterOption = .downloaded
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case downloaded = "Downloaded"
    }
    
    // For local books, essentially all chapters present are "downloaded".
    // This exists to match the LibriVox UI as requested.
    var filteredChapters: [(Int, Track)] {
        Array(book.chapters.enumerated())
    }
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header (Matching LibriVox Style)
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            if let data = book.coverArtData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
                            } else if let url = book.coverArtUrl {
                                AsyncImage(url: url) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.purple.opacity(0.1); ProgressView() } }
                            } else {
                                Color.purple.opacity(0.1); Image(systemName: "book.fill").font(.system(size: 40)).foregroundColor(.purple)
                            }
                        }
                        .frame(width: 100, height: 100).cornerRadius(20).shadow(radius: 5)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.displayTitle).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                            Text(book.displayAuthor).font(.subheadline).foregroundColor(.secondary)
                            Text("\(book.chapters.count) Chapters").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding().background(.ultraThinMaterial).cornerRadius(24).padding(.horizontal)
                    
                    // Resume/Play Button
                    Button(action: { onPlayChapter(book.currentChapterIndex) }) {
                        HStack { Image(systemName: "play.fill"); Text("Resume") }
                            .font(.headline).foregroundColor(.white).padding(.vertical, 14).frame(maxWidth: .infinity).background(Color.blue).cornerRadius(16).shadow(color: Color.blue.opacity(0.3), radius: 5, x: 0, y: 5)
                    }
                    .padding(.horizontal)
                    
                    // Expandable Description (If exists)
                    if let desc = book.description, !desc.isEmpty {
                        LocalDescriptionView(text: desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                            .padding(.horizontal)
                    }
                    
                    // Filter Bar (UI Consistency)
                    Picker("Filter", selection: $filter) {
                        ForEach(FilterOption.allCases, id: \.self) { option in Text(option.rawValue).tag(option) }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Chapter List
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredChapters, id: \.1.id) { index, chapter in
                            Button { onPlayChapter(index) } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.caption.weight(.bold)).foregroundColor(.secondary).frame(width: 25)
                                    Text(chapter.title).font(.system(size: 15, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                                    Spacer()
                                    if index == book.currentChapterIndex { Image(systemName: "waveform").foregroundColor(.blue).font(.caption) }
                                    else { Image(systemName: "play.fill").font(.caption).foregroundColor(.secondary.opacity(0.5)) }
                                }
                                .padding(12).background(.ultraThinMaterial).cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) { bookManager.deleteChapter(at: IndexSet(integer: index), from: book) } label: { Label("Delete Download", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 50)
                }
                .padding(.top)
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }
}

// Reuse similar Description component for local file
struct LocalDescriptionView: View {
    let text: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description").font(.headline)
            Text(text).font(.system(size: 15)).foregroundColor(.secondary).lineLimit(isExpanded ? nil : 4).animation(.spring(), value: isExpanded)
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                Text(isExpanded ? "Show Less" : "Show More").font(.caption.weight(.bold)).foregroundColor(.blue)
            }
        }
        .padding().background(.ultraThinMaterial).cornerRadius(16).onTapGesture { withAnimation { isExpanded.toggle() } }
    }
}

struct GlassBookRow: View {
    let book: Book; let onPlay: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let data = book.coverArtData, let uiImage = UIImage(data: data) { Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill) }
                else if let url = book.coverArtUrl { AsyncImage(url: url) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.purple.opacity(0.1) } } }
                else { RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.1)); Image(systemName: "book.fill").font(.system(size: 24)).foregroundColor(.purple) }
            }
            .frame(width: 50, height: 50).cornerRadius(8).clipped()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle).font(.system(size: 16, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                Text("\(book.chapters.count) chapters").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onPlay) { Image(systemName: "play.circle.fill").font(.system(size: 28)).foregroundColor(.blue.opacity(0.8)).shadow(radius: 2) }.buttonStyle(BorderlessButtonStyle())
        }
        .padding(12).background(.ultraThinMaterial).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1)).shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct BookToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) { Image(systemName: "checkmark.circle.fill").foregroundColor(.green); Text(message).font(.subheadline.weight(.medium)) }
            .padding(.horizontal, 20).padding(.vertical, 12).background(.thinMaterial).clipShape(Capsule()).shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}
