//
//  AudioPlayer.swift
//  2 Music 2 Furious - MILESTONE 10.2
//
//  FIXES:
//  - "High Gain" Boost increased to 4.0x (+12dB)
//  - Uses 'AVAudioMixerNode' for guaranteed compilation
//  - Restored 'currentTime' and 'duration' for UI sliders
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
import SwiftUI

class AudioPlayer: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isPlaying = false
    @Published var currentTrack: Track?
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var isShuffled = false
    
    // UI Metadata
    @Published var artwork: UIImage? = nil
    
    // Volume Control
    @Published var volume: Float = 0.5 {
        didSet { updatePlayerVolume() }
    }
    
    // Audio Features
    @Published var isDucking = false {
        didSet { updatePlayerVolume() }
    }
    
    @Published var isBoostEnabled = false {
        didSet {
            updateAudioEffects() // Toggles the Gain Boost
        }
    }
    
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            if isUsingEngine {
                timePitchNode.rate = playbackSpeed
            } else {
                avPlayer?.rate = isPlaying ? playbackSpeed : 0
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var duration: Double {
        if isUsingEngine {
            guard let file = audioFile else { return 0 }
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            return seconds
        } else {
            guard let item = avPlayer?.currentItem else { return 0 }
            let seconds = item.duration.seconds
            return (seconds.isNaN || seconds.isInfinite) ? 0 : seconds
        }
    }
    
    var currentTime: Double {
        if isUsingEngine {
            // Calculate engine time: Offset + (NodesElapsedFrames / SampleRate)
            guard isPlaying,
                  let nodeTime = playerNode.lastRenderTime,
                  let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
                return seekOffset
            }
            return seekOffset + (Double(playerTime.sampleTime) / audioSampleRate)
        } else {
            let seconds = avPlayer?.currentTime().seconds ?? 0
            return (seconds.isNaN || seconds.isInfinite) ? 0 : seconds
        }
    }
    
    // MARK: - Engine Properties (The "Pro" Stack)
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitchNode = AVAudioUnitTimePitch()
    private let boosterNode = AVAudioMixerNode() // REPLACEMENT: Dedicated Gain Stage
    
    // Engine State
    private var audioFile: AVAudioFile?
    private var audioSampleRate: Double = 44100
    private var seekOffset: TimeInterval = 0 // Tracks position manually for Engine
    private var isUsingEngine = false
    
    // Legacy / Stream Player
    private var avPlayer: AVPlayer?
    private var playerItemObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    
    let playerType: String
    private let positionKey = "playbackPositions"
    
    // MARK: - Initialization
    
    init(type: String) {
        self.playerType = type
        super.init()
        setupEngine()
    }
    
    private func setupEngine() {
        // Attach Nodes
        engine.attach(playerNode)
        engine.attach(timePitchNode)
        engine.attach(boosterNode) // Attach our gain booster
        
        // Connect Chain: Player -> TimePitch (Speed) -> Booster (Gain) -> Main Mixer
        // Note: We use the engine's main mixer as the final output
        engine.connect(playerNode, to: timePitchNode, format: nil)
        engine.connect(timePitchNode, to: boosterNode, format: nil)
        engine.connect(boosterNode, to: engine.mainMixerNode, format: nil)
        
        // Default Booster Volume (1.0 = standard)
        boosterNode.outputVolume = 1.0
    }
    
    // MARK: - Audio Effects Logic
    
    private func updateAudioEffects() {
        if isUsingEngine {
            // "BOOM" MODE:
            // 4.0 is approx +12dB. Pushing it hard but safe enough.
            boosterNode.outputVolume = isBoostEnabled ? 4.0 : 1.0
            
            // Handle Ducking via the MAIN mixer to avoid conflicting with the boost
            engine.mainMixerNode.outputVolume = isDucking ? 0.2 : volume
        }
        
        // Also update Audio Session Mode
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setMode(isBoostEnabled ? .spokenAudio : .default)
        } catch { print("Session Mode Error: \(error)") }
    }
    
    private func updatePlayerVolume() {
        if isUsingEngine {
            // Volume is controlled by the Main Mixer (final stage)
            // The booster node handles the "Boost" offset separately
            let targetVol = isDucking ? volume * 0.2 : volume
            engine.mainMixerNode.outputVolume = targetVol
        } else {
            var finalVolume = volume
            if isDucking { finalVolume = volume * 0.2 }
            avPlayer?.volume = finalVolume
        }
    }
    
    // MARK: - Artwork Extraction
    
    private func extractArtwork(from asset: AVURLAsset) {
        DispatchQueue.main.async { self.artwork = nil }
        
        let url = asset.url
        if url.absoluteString.contains("ipod-library") {
            if let libraryArt = extractLibraryArtwork(url: url) {
                DispatchQueue.main.async { self.artwork = libraryArt }
            }
            return
        }
        
        Task {
            if let image = await extractCommonArtwork(from: asset) {
                await MainActor.run { self.updateArtwork(image) }
                return
            }
            if let image = await extractAllMetadata(from: asset) {
                await MainActor.run { self.updateArtwork(image) }
            }
        }
    }
    
    private func extractLibraryArtwork(url: URL) -> UIImage? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let idString = queryItems.first(where: { $0.name == "id" })?.value,
              let persistentID = UInt64(idString) else { return nil }
        
        let predicate = MPMediaPropertyPredicate(value: NSNumber(value: persistentID), forProperty: MPMediaItemPropertyPersistentID)
        let query = MPMediaQuery()
        query.addFilterPredicate(predicate)
        
        if let item = query.items?.first, let artwork = item.artwork {
            return artwork.image(at: CGSize(width: 600, height: 600))
        }
        return nil
    }
    
    private func extractCommonArtwork(from asset: AVAsset) async -> UIImage? {
        do {
            let metadata = try await asset.load(.commonMetadata)
            if let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first,
               let data = try await item.load(.dataValue),
               let image = UIImage(data: data) {
                return image
            }
        } catch { return nil }
        return nil
    }
    
    private func extractAllMetadata(from asset: AVAsset) async -> UIImage? {
        do {
            let formats = try await asset.load(.availableMetadataFormats)
            for format in formats {
                let metadata = try await asset.loadMetadata(for: format)
                for item in metadata {
                    if let data = try? await item.load(.dataValue), let image = UIImage(data: data) { return image }
                    if let value = try? await item.load(.value), let data = value as? Data, let image = UIImage(data: data) { return image }
                }
            }
        } catch { return nil }
        return nil
    }
    
    private func updateArtwork(_ image: UIImage) {
        withAnimation(.easeIn(duration: 0.5)) { self.artwork = image }
    }

    // MARK: - Position Memory
    
    func saveCurrentPosition() {
        guard let track = currentTrack else { return }
        let position = self.currentTime
        if position > 5 { savePosition(for: track.filename, position: position) }
    }
    
    private func savePosition(for filename: String, position: Double) {
        var positions = UserDefaults.standard.dictionary(forKey: positionKey) as? [String: Double] ?? [:]
        positions[filename] = position
        UserDefaults.standard.set(positions, forKey: positionKey)
    }
    
    private func getPosition(for filename: String) -> Double {
        let positions = UserDefaults.standard.dictionary(forKey: positionKey) as? [String: Double] ?? [:]
        return positions[filename] ?? 0
    }
    
    private func clearPosition(for filename: String) {
        var positions = UserDefaults.standard.dictionary(forKey: positionKey) as? [String: Double] ?? [:]
        positions.removeValue(forKey: filename)
        UserDefaults.standard.set(positions, forKey: positionKey)
    }
    
    private func restoreSavedPosition() {
        guard let track = currentTrack else { return }
        let savedPosition = getPosition(for: track.filename)
        if savedPosition > 5 { seek(to: savedPosition) }
    }
    
    // MARK: - Playback Loading
    
    func playNow(_ track: Track) {
        saveCurrentPosition()
        pause()
        queue.insert(track, at: 0)
        currentIndex = 0
        currentTrack = track
        loadTrackAndPlay(at: 0)
    }
    
    func loadTrack(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        saveCurrentPosition()
        currentIndex = index
        currentTrack = queue[index]
        stopCurrentPlayback()
        
        guard let track = currentTrack else { return }
        if track.filename.starts(with: "ipod-library://") { loadFromAssetURL(track.filename) }
        else if track.filename.starts(with: "http") { loadRadioStream() }
        else { loadLocalFile() }
    }
    
    private func loadTrackAndPlay(at index: Int) {
        loadTrack(at: index)
        // For AVPlayer (Stream), we wait for ready. For Engine (Local), we play immediately.
        if isUsingEngine { play() }
    }
    
    private func stopCurrentPlayback() {
        saveCurrentPosition()
        
        // Stop Engine
        if engine.isRunning {
            playerNode.stop()
            engine.stop()
        }
        
        // Stop AVPlayer
        avPlayer?.pause()
        if let observer = timeObserver { avPlayer?.removeTimeObserver(observer); timeObserver = nil }
        playerItemObserver?.invalidate()
        playerItemObserver = nil
        avPlayer = nil
        
        audioFile = nil
        seekOffset = 0
    }
    
    // MARK: - Loaders
    
    private func loadFromAssetURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        isUsingEngine = false
        let asset = AVURLAsset(url: url)
        extractArtwork(from: asset)
        let item = AVPlayerItem(asset: asset)
        setupAVPlayer(with: item)
        // Note: Engine is NOT used for Library assets to respect DRM/Protected content usually
    }
    
    private func loadRadioStream() {
        guard let track = currentTrack, let url = URL(string: track.filename) else { return }
        isUsingEngine = false
        self.artwork = nil
        let item = AVPlayerItem(url: url)
        setupAVPlayer(with: item)
        // Note: Engine is not used for streams to avoid complex buffer management
    }
    
    private func setupAVPlayer(with item: AVPlayerItem) {
        avPlayer = AVPlayer(playerItem: item)
        updatePlayerVolume()
        setupEndObserver(for: item)
        
        // Add Ready Observer
        playerItemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                DispatchQueue.main.async {
                    self?.restoreSavedPosition()
                    if self?.currentTrack?.filename.starts(with: "http") == true { self?.play() } // Auto play radio
                }
            }
        }
    }
    
    private func loadLocalFile() {
        guard let track = currentTrack else { return }
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(track.filename)
        
        // EXTRACT ARTWORK
        let asset = AVURLAsset(url: path)
        extractArtwork(from: asset)
        
        // SETUP ENGINE FOR LOCAL FILE
        do {
            isUsingEngine = true
            audioFile = try AVAudioFile(forReading: path)
            audioSampleRate = audioFile!.processingFormat.sampleRate
            
            engine.reset()
            // We need to re-connect if the format changed, but usually standard connect works.
            // Schedule the file
            scheduleFileSegment(from: 0)
            
            try engine.start()
            updateAudioEffects()
            restoreSavedPosition()
            
        } catch {
            print("Error loading local file into Engine: \(error)")
            // Fallback?
        }
    }
    
    private func scheduleFileSegment(from startTime: Double) {
        guard let file = audioFile else { return }
        
        let startFrame = AVAudioFramePosition(startTime * file.processingFormat.sampleRate)
        let remainingFrames = AVAudioFrameCount(file.length - startFrame)
        
        guard remainingFrames > 0 else { return }
        
        playerNode.stop()
        if remainingFrames > 100 { // Check simply to avoid tiny segment errors
            playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: remainingFrames, at: nil) {
                // Completion handler (End of file)
                // Note: This is called when buffer is empty, not necessarily playback end
            }
        }
        seekOffset = startTime
        
        // Re-apply Speed
        timePitchNode.rate = playbackSpeed
    }
    
    // MARK: - Observers
    
    private func setupEndObserver(for item: AVPlayerItem) {
        NotificationCenter.default.addObserver(self, selector: #selector(itemDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: item)
    }
    
    @objc private func itemDidFinishPlaying(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.trackFinished()
        }
    }
    
    private func trackFinished() {
        if let track = currentTrack { clearPosition(for: track.filename) }
        if playerType == "Music" { next() }
        else { isPlaying = false }
    }
    
    // MARK: - Playback Controls
    
    func play() {
        if isUsingEngine {
            if !engine.isRunning { try? engine.start() }
            playerNode.play()
        } else {
            avPlayer?.play()
            avPlayer?.rate = playbackSpeed // Re-apply speed
        }
        isPlaying = true
    }
    
    func pause() {
        saveCurrentPosition()
        if isUsingEngine {
            playerNode.pause()
            engine.pause() // Pause engine to save battery
        } else {
            avPlayer?.pause()
        }
        isPlaying = false
    }
    
    func togglePlayPause() { isPlaying ? pause() : play() }
    
    func next() {
        guard !queue.isEmpty else { return }
        if let track = currentTrack { clearPosition(for: track.filename) }
        let wasPlaying = isPlaying
        currentIndex = (currentIndex + 1) % queue.count
        loadTrackAndPlay(at: currentIndex)
        if !wasPlaying { pause() } // Keep paused if we were paused
    }
    
    func previous() {
        guard !queue.isEmpty else { return }
        let time = currentTime
        if time > 3 {
            seek(to: 0)
        } else {
            currentIndex = currentIndex == 0 ? queue.count - 1 : currentIndex - 1
            loadTrackAndPlay(at: currentIndex)
        }
    }
    
    func seek(to time: Double) {
        if isUsingEngine {
            scheduleFileSegment(from: time)
            if isPlaying { playerNode.play() }
        } else {
            avPlayer?.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: 600))
        }
    }
    
    func skipForward(seconds: Double = 30) {
        let new = currentTime + seconds
        (duration > 0 && new >= duration) ? next() : seek(to: new)
    }
    
    func skipBackward(seconds: Double = 30) { seek(to: max(0, currentTime - seconds)) }
    
    func cycleSpeed() {
        let speeds: [Float] = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0]
        if let idx = speeds.firstIndex(where: { abs($0 - playbackSpeed) < 0.01 }) {
            playbackSpeed = speeds[(idx + 1) % speeds.count]
        } else {
            playbackSpeed = 1.0
        }
    }
    
    func shuffle() {
        guard queue.count > 1 else { return }
        isShuffled.toggle()
        if isShuffled {
            let current = currentTrack
            queue.shuffle()
            if let t = current, let idx = queue.firstIndex(where: { $0.id == t.id }) { currentIndex = idx }
        }
    }
    
    func clearQueue() {
        saveCurrentPosition()
        stopCurrentPlayback()
        queue.removeAll()
        currentTrack = nil
        currentIndex = 0
        isPlaying = false
        artwork = nil
    }
    
    func addTrack(from url: URL) {
        let filename = url.lastPathComponent
        let title = filename.replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: ".").first ?? filename
        addTrackToQueue(Track(title: title, artist: "Unknown", filename: filename))
    }
    
    func addTrackToQueue(_ track: Track) {
        queue.append(track)
        if queue.count == 1 { loadTrack(at: 0) }
    }
    
    func addRadioStream(name: String, streamURL: String) { playNow(Track(title: name, artist: "Radio", filename: streamURL)) }
    func playFromQueue(at index: Int) { loadTrackAndPlay(at: index) }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        playerItemObserver?.invalidate()
        if let observer = timeObserver { avPlayer?.removeTimeObserver(observer) }
        engine.stop()
    }
}
