//
//  QueueView.swift
//  2 Music 2 Furious - MILESTONE 15
//
//  Shows the current play queue and allows playback control
//  UPDATED: Added Drag-to-Reorder functionality
//

import SwiftUI

struct QueueView: View {
    @ObservedObject var player: AudioPlayer
    let title: String
    let dismiss: () -> Void
    
    init(player: AudioPlayer, title: String = "Queue", dismiss: @escaping () -> Void) {
        self.player = player
        self.title = title
        self.dismiss = dismiss
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassBackgroundView()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text(title).font(.title2.weight(.bold))
                        Spacer()
                        EditButton() // Native SwiftUI Edit Button for Reordering
                            .foregroundColor(.purple)
                            .padding(.trailing, 8)
                        GlassCloseButton(action: dismiss)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    
                    if player.queue.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: "music.note.list").font(.system(size: 50)).foregroundColor(.secondary)
                            Text("Queue is empty").font(.headline).foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        // Converted to List for .onMove support
                        List {
                            ForEach(0..<player.queue.count, id: \.self) { index in
                                QueueRow(
                                    track: player.queue[index],
                                    index: index,
                                    isCurrent: index == player.currentIndex,
                                    isPlaying: player.isPlaying,
                                    onTap: {
                                        player.playFromQueue(at: index)
                                    }
                                )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            .onMove(perform: moveQueueItems) // Drag to reorder
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                    
                    if !player.queue.isEmpty {
                        Button(action: { player.clearQueue() }) {
                            Text("Clear Queue").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding()
                                .background(Color.red.opacity(0.2)).background(.ultraThinMaterial).cornerRadius(12)
                        }.padding()
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .accentColor(.purple)
    }
    
    // Logic to move items in the array
    private func moveQueueItems(from source: IndexSet, to destination: Int) {
        player.queue.move(fromOffsets: source, toOffset: destination)
        
        // Optional: If you track "currentIndex" by integer, you might need to update it here
        // depending on your AudioPlayer logic. For now, this just moves the items.
    }
}

struct QueueRow: View {
    let track: Track
    let index: Int
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.fill")
                            .foregroundColor(.purple).font(.system(size: 14))
                    } else {
                        Text("\(index + 1)").font(.caption.weight(.bold)).foregroundColor(.secondary)
                    }
                }.frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 16, weight: isCurrent ? .bold : .medium))
                        .foregroundColor(isCurrent ? .purple : .primary).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(12)
            .background(isCurrent ? Color.purple.opacity(0.1) : Color.clear)
            .background(.ultraThinMaterial).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isCurrent ? Color.purple.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
        }.buttonStyle(PlainButtonStyle())
    }
}
