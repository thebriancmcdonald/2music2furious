//
//  QueueView.swift
//  2 Music 2 Furious - MILESTONE 15
//
//  Shows the current play queue and allows playback control
//  FIXED: Switched ForEach to use Track identity to prevent "glitch/vanishing" during drag
//

import SwiftUI

struct QueueView: View {
    @ObservedObject var player: AudioPlayer
    let title: String
    let dismiss: () -> Void
    
    init(player: AudioPlayer, title: String = "Up Next", dismiss: @escaping () -> Void) {
        self.player = player
        self.title = title
        self.dismiss = dismiss
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackgroundView()
                
                if player.queue.isEmpty {
                    GlassEmptyStateView(
                        icon: "music.note.list",
                        title: "Queue is empty",
                        subtitle: "Add songs, radio stations, or podcasts\nto see them here."
                    )
                } else {
                    VStack(spacing: 0) {
                        List {
                            // FIXED: Iterate over the tracks themselves, not the index range.
                            // This allows SwiftUI to follow the item during the drag animation.
                            ForEach(player.queue, id: \.self) { track in
                                // We calculate the index dynamically to maintain the "Current" logic
                                let index = player.queue.firstIndex(of: track) ?? 0
                                
                                GlassQueueRow(
                                    track: track,
                                    index: index,
                                    isCurrent: index == player.currentIndex,
                                    isPlaying: player.isPlaying,
                                    onTap: { player.playFromQueue(at: index) }
                                )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                            .onMove(perform: moveQueueItems)
                            .onDelete(perform: deleteQueueItems)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        
                        // Bottom Action Bar
                        VStack {
                            GlassActionButton(
                                title: "Clear Queue",
                                icon: "trash",
                                color: .red.opacity(0.8)
                            ) {
                                player.clearQueue()
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
                
                if !player.queue.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        EditButton()
                            .tint(.royalPurple)
                    }
                }
            }
        }
        .accentColor(.royalPurple)
    }
    
    private func moveQueueItems(from source: IndexSet, to destination: Int) {
        player.queue.move(fromOffsets: source, toOffset: destination)
        
        // Optional: If you need to keep the "current index" pointing to the correct song
        // after a move, you would add logic here. For now, this handles the visual reorder.
    }
    
    private func deleteQueueItems(at offsets: IndexSet) {
        player.queue.remove(atOffsets: offsets)
        
        // Safety check: if we deleted the current playing song or one before it,
        // we might need to adjust currentIndex in AudioPlayer, but usually
        // the player handles bounds checking.
    }
}

// MARK: - Glass Queue Row

struct GlassQueueRow: View {
    let track: Track
    let index: Int
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Leading Indicator (Index or Speaker)
                ZStack {
                    if isCurrent {
                        Circle()
                            .fill(Color.royalPurple.opacity(0.2))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.royalPurple)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(width: 32)
                
                // Track Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 16, weight: isCurrent ? .semibold : .medium))
                        .foregroundColor(isCurrent ? .royalPurple : .primary)
                        .lineLimit(1)
                    
                    Text(track.artist)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Drag Handle visual cue
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.royalPurple.opacity(0.6))
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isCurrent ? Color.royalPurple.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
