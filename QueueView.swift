//
//  QueueView.swift
//  2 Music 2 Furious - MILESTONE 7.3
//
//  Queue management with separate Clear and Shuffle buttons
//

import SwiftUI

struct QueueView: View {
    @ObservedObject var player: AudioPlayer
    let title: String
    let dismiss: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                if player.queue.isEmpty {
                    Text("Queue is empty")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                        QueueRow(
                            track: track,
                            index: index,
                            isCurrentTrack: index == player.currentIndex,
                            onTap: {
                                player.playFromQueue(at: index)
                                dismiss()
                            }
                        )
                    }
                    .onMove { from, to in
                        player.queue.move(fromOffsets: from, toOffset: to)
                        if let fromIndex = from.first {
                            if fromIndex == player.currentIndex {
                                player.currentIndex = to > fromIndex ? to - 1 : to
                            } else if fromIndex < player.currentIndex && to > player.currentIndex {
                                player.currentIndex -= 1
                            } else if fromIndex > player.currentIndex && to <= player.currentIndex {
                                player.currentIndex += 1
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            if offset < player.currentIndex {
                                player.currentIndex -= 1
                            } else if offset == player.currentIndex {
                                player.pause()
                            }
                        }
                        player.queue.remove(atOffsets: offsets)
                        
                        if player.queue.isEmpty {
                            player.currentTrack = nil
                            player.currentIndex = 0
                        } else if player.currentIndex >= player.queue.count {
                            player.currentIndex = player.queue.count - 1
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !player.queue.isEmpty {
                        HStack(spacing: 16) {
                            // Clear button
                            Button(action: { player.clearQueue() }) {
                                Text("Clear")
                                    .foregroundColor(.red)
                            }
                            
                            // Shuffle button (Music only)
                            if player.playerType == "Music" {
                                Button(action: { player.shuffle() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "shuffle")
                                        if player.isShuffled {
                                            Text("On")
                                                .font(.system(size: 12))
                                        }
                                    }
                                    .foregroundColor(player.isShuffled ? .orange : .blue)
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct QueueRow: View {
    let track: Track
    let index: Int
    let isCurrentTrack: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(isCurrentTrack ? .blue : .secondary)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 16, weight: isCurrentTrack ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isCurrentTrack {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
