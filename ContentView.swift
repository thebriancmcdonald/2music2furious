//
//  ContentView.swift
//  2 Music 2 Furious - MILESTONE 11
//
//  Main app view with dual audio players
//  UPDATES: Bottom row buttons right-aligned, Text button icon changed to document
//

import SwiftUI
import UniformTypeIdentifiers
import MediaPlayer
import AVFoundation
import Combine

struct ContentView: View {
    
    // MARK: - State Objects
    
    @StateObject private var musicPlayer = AudioPlayer(type: "Music")
    @StateObject private var speechPlayer = AudioPlayer(type: "Speech")
    @StateObject private var musicLibrary = MusicLibraryManager()
    @StateObject private var bookManager = BookManager.shared
    @StateObject private var podcastSearch = PodcastSearchManager()
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var radioAPI = RadioBrowserAPI()
    @StateObject private var articleManager = ArticleManager.shared

    // MARK: - State for UI

    @State private var showingMusicLibrary = false
    @State private var showingBookLibrary = false
    @State private var showingPodcastSearch = false
    @State private var showingRadioSearch = false
    @State private var showingMusicQueue = false
    @State private var showingSpeechQueue = false
    @State private var showingArticleLibrary = false
    
    // Feature Toggles
    @State private var backgroundModeEnabled = false
    @State private var voiceBoostEnabled = false
    
    // MARK: - App lifecycle
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        ZStack {
            // Background
            backgroundGradient
            
            VStack(spacing: 12) {
                // Header
                header
                    .padding(.top, 4)
                
                // Music Panel
                musicPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Speech Panel
                speechPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Bottom padding
                Color.clear.frame(height: 2)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        // MARK: - Sheets
        .sheet(isPresented: $showingMusicLibrary) {
            MusicLibraryView(library: musicLibrary, musicPlayer: musicPlayer, dismiss: { showingMusicLibrary = false })
        }
        .sheet(isPresented: $showingBookLibrary) {
            BookLibraryView(bookManager: bookManager, speechPlayer: speechPlayer, dismiss: { showingBookLibrary = false })
        }
        .sheet(isPresented: $showingPodcastSearch) {
            PodcastSearchView(searchManager: podcastSearch, downloadManager: downloadManager, speechPlayer: speechPlayer, dismiss: { showingPodcastSearch = false })
        }
        .sheet(isPresented: $showingRadioSearch) {
            RadioSearchView(radioAPI: radioAPI, musicPlayer: musicPlayer, dismiss: { showingRadioSearch = false })
        }
        .sheet(isPresented: $showingMusicQueue) {
            QueueView(player: musicPlayer, title: "Music Queue", dismiss: { showingMusicQueue = false })
        }
        .sheet(isPresented: $showingSpeechQueue) {
            QueueView(player: speechPlayer, title: "Speech Queue", dismiss: { showingSpeechQueue = false })
        }
        .sheet(isPresented: $showingArticleLibrary) {
            ArticleLibraryView(articleManager: articleManager, speechPlayer: speechPlayer, dismiss: { showingArticleLibrary = false })
        }
        // MARK: - Lifecycle
        .onAppear {
            musicLibrary.checkAuthorization()
            setupGlobalAudioSession()
            setupGlobalRemoteCommands()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                musicPlayer.saveCurrentPosition()
                speechPlayer.saveCurrentPosition()
            }
        }
        .onChange(of: backgroundModeEnabled) { musicPlayer.isDucking = $0 }
        .onChange(of: voiceBoostEnabled) { speechPlayer.isBoostEnabled = $0 }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        GeometryReader { _ in
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color(red: 0.1, green: 0.1, blue: 0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                ZStack {
                    Circle().fill(Color.blue.opacity(0.15)).blur(radius: 80).offset(x: -100, y: -200)
                    Circle().fill(Color.purple.opacity(0.15)).blur(radius: 80).offset(x: 100, y: 200)
                }
            )
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("2 MUSIC 2 FURIOUS")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .cyan.opacity(0.5), radius: 10, x: 0, y: 0)
            
            Spacer()
            
            Button(action: {
                if musicPlayer.isPlaying || speechPlayer.isPlaying {
                    musicPlayer.pause(); speechPlayer.pause()
                } else {
                    if musicPlayer.currentTrack != nil { musicPlayer.play() }
                    if speechPlayer.currentTrack != nil { speechPlayer.play() }
                }
            }) {
                let anyPlaying = musicPlayer.isPlaying || speechPlayer.isPlaying
                HStack(spacing: 6) {
                    Image(systemName: anyPlaying ? "pause.fill" : "play.fill")
                    Text(anyPlaying ? "PAUSE ALL" : "PLAY ALL")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1)))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Music Panel
    
    private var musicPanel: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                // 1. Label & Header Controls
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        Text("MUSIC").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Quiet Button
                    Button(action: { backgroundModeEnabled.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: backgroundModeEnabled ? "speaker.zzz.fill" : "speaker.wave.3.fill")
                            Text("QUIET").font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(backgroundModeEnabled ? Color.deepResumePurple : Color.black.opacity(0.3))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(backgroundModeEnabled ? Color.royalPurple : Color.white.opacity(0.2), lineWidth: 1))
                    }.foregroundColor(.white)
                }
                
                Spacer()
                
                // 2. Track Info
                TrackInfoView(player: musicPlayer)
                
                Spacer()
                
                // 3. Seek Bar
                SeekBarView(player: musicPlayer)
                
                Spacer()
                
                // 4. Controls
                PlaybackControlsView(player: musicPlayer, skipBackSeconds: 15)
                
                Spacer()
                
                // 5. Up Next (Card Style)
                UpNextView(player: musicPlayer) {
                    showingMusicQueue = true
                }
                
                Spacer()
                
                // 6. Action Buttons (Right Aligned)
                HStack(spacing: 8) {
                    Spacer()
                    
                    Button(action: {
                        if musicLibrary.authorizationStatus == .notDetermined { musicLibrary.requestAuthorization() }
                        showingMusicLibrary = true
                    }) { glassButtonStyle(icon: "music.note.list", text: "Library") }
                    
                    Button(action: { showingRadioSearch = true }) { glassButtonStyle(icon: "antenna.radiowaves.left.and.right", text: "Radio") }
                }
            }
            
            // Right Volume
            VerticalVolumeView(player: musicPlayer)
        }
        .padding(16)
        .background(panelBackground(for: musicPlayer))
        .glassPanel()
    }
    
    // MARK: - Speech Panel
    
    private var speechPanel: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                // 1. Label & Header Controls
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        Text("SPEECH").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Boost Button
                    Button(action: { voiceBoostEnabled.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: voiceBoostEnabled ? "waveform.path.ecg" : "waveform")
                            Text("BOOST").font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(voiceBoostEnabled ? Color.deepResumePurple : Color.black.opacity(0.3))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(voiceBoostEnabled ? Color.royalPurple : Color.white.opacity(0.2), lineWidth: 1))
                    }.foregroundColor(.white)
                }
                
                Spacer()
                
                // 2. Track Info
                TrackInfoView(player: speechPlayer)
                
                Spacer()
                
                // 3. Seek Bar
                SeekBarView(player: speechPlayer)
                
                Spacer()
                
                // 4. Controls
                PlaybackControlsView(player: speechPlayer, skipBackSeconds: 15)
                
                Spacer()
                
                // 5. Up Next (Card Style)
                UpNextView(player: speechPlayer) {
                    showingSpeechQueue = true
                }
                
                Spacer()
                
                // 6. Action Buttons (Right Aligned)
                HStack(spacing: 8) {
                    Spacer()
                    
                    Button(action: { showingPodcastSearch = true }) { glassButtonStyle(icon: "mic.fill", text: "Podcasts") }
                    
                    Button(action: { showingBookLibrary = true }) { glassButtonStyle(icon: "book.fill", text: "Audiobooks") }

                    Button(action: { showingArticleLibrary = true }) { glassButtonStyle(icon: "doc.text.fill", text: "Text") }
                }
            }
            
            // Right Volume
            VerticalVolumeView(player: speechPlayer)
        }
        .padding(16)
        .background(panelBackground(for: speechPlayer))
        .glassPanel()
    }
    
    // MARK: - Album Art Background Logic
    
    @ViewBuilder
    private func panelBackground(for player: AudioPlayer) -> some View {
        if let artwork = player.artwork {
            GeometryReader { geo in
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: 40)
                    .overlay(Color.black.opacity(0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
    
    // MARK: - Audio Setup
    
    private func setupGlobalAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch { print("Failed to setup audio session: \(error)") }
    }
    
    private func setupGlobalRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            if musicPlayer.queue.count > 0 { musicPlayer.play() }
            if speechPlayer.queue.count > 0 { speechPlayer.play() }
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            musicPlayer.pause(); speechPlayer.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            if musicPlayer.isPlaying || speechPlayer.isPlaying { musicPlayer.pause(); speechPlayer.pause() }
            else {
                if musicPlayer.queue.count > 0 { musicPlayer.play() }
                if speechPlayer.queue.count > 0 { speechPlayer.play() }
            }
            return .success
        }
    }
    
    // MARK: - Helpers
    
    private func glassButtonStyle(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12))
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Subviews

struct TrackInfoView: View {
    @ObservedObject var player: AudioPlayer
    
    var body: some View {
        HStack(alignment: .center) {
            if let artwork = player.artwork {
                Image(uiImage: artwork)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.trailing, 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.title ?? "Select Audio")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white).lineLimit(1)
                Text(player.currentTrack?.artist ?? "No track loaded")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7)).lineLimit(1)
            }
            
            Spacer()
            
            // SPEED BUTTON
            Button(action: { player.cycleSpeed() }) {
                Text("\(String(format: "%.1f", player.playbackSpeed))x")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(player.playbackSpeed == 1.0 ? .white.opacity(0.5) : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(player.playbackSpeed == 1.0 ? Color.white.opacity(0.1) : Color.white.opacity(0.2))
                    )
                    .overlay(
                        Capsule()
                            .stroke(player.playbackSpeed == 1.0 ? Color.clear : Color.green.opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 4)
    }
}

struct PlaybackControlsView: View {
    @ObservedObject var player: AudioPlayer
    var skipBackSeconds: Double
    var body: some View {
        HStack {
            Spacer()
            Button(action: { player.previous() }) {
                Image(systemName: "backward.end.fill").font(.system(size: 22))
                    .foregroundColor(.white.opacity(player.queue.isEmpty ? 0.3 : 0.9))
                    .frame(width: 44, height: 44)
            }.disabled(player.queue.isEmpty)
            Spacer()
            Button(action: { player.skipBackward(seconds: skipBackSeconds) }) {
                Image(systemName: "gobackward.\(Int(skipBackSeconds))").font(.system(size: 22))
                    .foregroundColor(.white.opacity(player.queue.isEmpty ? 0.3 : 0.9))
                    .frame(width: 44, height: 44)
            }.disabled(player.queue.isEmpty)
            Spacer()
            Button(action: { player.togglePlayPause() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 32))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(.white.opacity(0.2)).shadow(color: .black.opacity(0.2), radius: 10))
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
            }.disabled(player.queue.isEmpty)
            Spacer()
            Button(action: { player.skipForward(seconds: 30) }) {
                Image(systemName: "goforward.30").font(.system(size: 22))
                    .foregroundColor(.white.opacity(player.queue.isEmpty ? 0.3 : 0.9))
                    .frame(width: 44, height: 44)
            }.disabled(player.queue.isEmpty)
            Spacer()
            Button(action: { player.next() }) {
                Image(systemName: "forward.end.fill").font(.system(size: 22))
                    .foregroundColor(.white.opacity(player.queue.isEmpty ? 0.3 : 0.9))
                    .frame(width: 44, height: 44)
            }.disabled(player.queue.isEmpty)
            Spacer()
        }
    }
}

// Updated: "Glass Inset" Card Style
struct UpNextView: View {
    @ObservedObject var player: AudioPlayer
    var onQueueTap: () -> Void
    
    var body: some View {
        Button(action: onQueueTap) {
            HStack(spacing: 12) {
                // Left Side: Content
                VStack(alignment: .leading, spacing: 4) {
                    Text("UP NEXT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    if player.queue.isEmpty {
                        Text("End of Queue")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(0..<min(2, player.queue.count), id: \.self) { i in
                                let trackIndex = (player.currentIndex + 1 + i) % player.queue.count
                                if player.queue.indices.contains(trackIndex) {
                                    Text("• \(player.queue[trackIndex].title)")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Right Side: Queue Badge (if items exist)
                if player.queue.count > 0 {
                    VStack(spacing: 2) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                        Text("\(player.queue.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.2)))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(BorderlessButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

struct VerticalVolumeView: View {
    @ObservedObject var player: AudioPlayer
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(.black.opacity(0.3)).overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                Capsule().fill(Color.white.opacity(0.9))
                    .frame(height: max(0, geo.size.height * CGFloat(player.volume)))
                    .animation(.spring(response: 0.3), value: player.volume)
            }
            .gesture(DragGesture().onChanged { value in
                player.volume = Float(max(0, min(1, Double(1 - (value.location.y / geo.size.height)))))
            })
        }
        .frame(width: 28)
    }
}

// MARK: - Optimized SeekBar with Threshold-Based Updates

struct SeekBarView: View {
    @ObservedObject var player: AudioPlayer
    @State private var sliderValue: Double = 0
    @State private var displayTime: Double = 0
    @State private var isDragging: Bool = false
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 8) {
            Text(formatTime(displayTime))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 40, alignment: .leading)
            
            Slider(
                value: $sliderValue,
                in: 0...(player.duration > 0 ? player.duration : 1)
            ) { editing in
                isDragging = editing
                if editing {
                    // User started dragging - update display to match
                    displayTime = sliderValue
                } else {
                    // User finished - seek to position
                    player.seek(to: sliderValue)
                }
            }
            .tint(.white)
            .disabled(player.duration == 0)
            .onChange(of: sliderValue) { newValue in
                if isDragging {
                    displayTime = newValue
                }
            }
            
            Text("-" + formatTime(max(0, player.duration - displayTime)))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 45, alignment: .trailing)
        }
        .onReceive(timer) { _ in
            guard !isDragging && player.isPlaying else { return }
            let newTime = player.currentTime
            // Only update if changed significantly (reduces redraws)
            if abs(newTime - displayTime) > 0.4 {
                displayTime = newTime
                sliderValue = newTime
            }
        }
        .onAppear {
            sliderValue = player.currentTime
            displayTime = player.currentTime
        }
        .onChange(of: player.currentTrack?.id) { _ in
            // Reset when track changes
            sliderValue = 0
            displayTime = 0
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN && !time.isInfinite && time >= 0 else { return "00:00" }
        let totalSeconds = Int(time)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - BorderlessButtonStyle (kept for compatibility)

struct BorderlessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

#Preview { ContentView() }
