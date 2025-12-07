//
//  BookLibraryView.swift
//  2 Music 2 Furious - MILESTONE 7.3
//
//  Audiobook library with Upload and LibriVox integration
//  Layout: [Upload] [LibriVox] Books [Done]
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
                if bookManager.books.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(bookManager.books) { book in
                            BookRow(
                                book: book,
                                onPlay: { playBook(book) }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    bookManager.removeBook(book)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                
                // Toast
                if showingToast {
                    VStack {
                        Spacer()
                        BookToastView(message: toastMessage)
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: showingToast)
                }
            }
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        // Upload button
                        Button(action: { showingFilePicker = true }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        
                        // LibriVox button
                        Button(action: { showingLibriVox = true }) {
                            Text("LibriVox")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleFileUpload(result: result)
            }
            .sheet(isPresented: $showingLibriVox) {
                LibriVoxSearchView(bookManager: bookManager, dismiss: { showingLibriVox = false })
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No audiobooks yet")
                .font(.title2)
                .foregroundColor(.gray)
            
            Text("Upload your own audiobook files\nor browse LibriVox for free classics")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            HStack(spacing: 16) {
                Button(action: { showingFilePicker = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Upload")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                
                Button(action: { showingLibriVox = true }) {
                    HStack {
                        Image(systemName: "book.fill")
                        Text("LibriVox")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(10)
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
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
                    
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    
                    let title = filename
                        .replacingOccurrences(of: "_", with: " ")
                        .components(separatedBy: ".").dropLast().joined(separator: ".")
                    
                    let track = Track(title: title, artist: "Audiobook", filename: filename)
                    uploadedTracks.append(track)
                }
            }
            
            if !uploadedTracks.isEmpty {
                // Process and auto-group the tracks
                let newBooks = bookManager.processUploadedTracks(uploadedTracks)
                for book in newBooks {
                    bookManager.addBook(book)
                }
                
                let totalChapters = newBooks.reduce(0) { $0 + $1.chapters.count }
                if newBooks.count == 1 && totalChapters > 1 {
                    showToast("Added book with \(totalChapters) chapters")
                } else if newBooks.count == 1 {
                    showToast("Added 1 audiobook")
                } else {
                    showToast("Added \(newBooks.count) audiobooks")
                }
            }
        } catch {
            print("Upload error: \(error)")
            showToast("Upload failed")
        }
    }
    
    private func playBook(_ book: Book) {
        speechPlayer.clearQueue()
        for chapter in book.chapters {
            speechPlayer.addTrackToQueue(chapter)
        }
        if speechPlayer.queue.count > 0 {
            speechPlayer.loadTrack(at: book.currentChapterIndex)
            speechPlayer.play()
        }
        dismiss()
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation {
            showingToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showingToast = false
            }
        }
    }
}

// MARK: - Book Row

struct BookRow: View {
    let book: Book
    let onPlay: () -> Void
    
    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                // Book icon
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "book.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 20))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.displayTitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text("\(book.chapters.count) chapter\(book.chapters.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Toast View

struct BookToastView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
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
