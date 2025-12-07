//
//  AudioPlayer.swift
//  2 Music 2 Furious - MILESTONE 8.3
//
//  FEATURES:
//  - Fixed Build Errors (AVMetadataFormat syntax)
//  - robust "Brute Force" Artwork Extraction
//  - Volume Boost & Ducking
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
import SwiftUI // Required for withAnimation

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
            updatePlayerVolume()
            if playerType == "Speech" { updateAudioSessionMode() }
        }
    }
    
    // MARK: - Computed Properties
    
    var duration: Double {
        if isUsingAVPlayer {
            guard let item = avPlayer?.currentItem else { return 0 }
            let seconds = item.duration.seconds
            return (seconds.isNaN || seconds.isInfinite) ? 0 : seconds
        } else {
            return audioPlayer?.duration ?? 0
        }
    }
    
    var currentTime: Double {
        if isUsingAVPlayer {
            let seconds = avPlayer?.currentTime().seconds ?? 0
            return (seconds.isNaN || seconds.isInfinite) ? 0 : seconds
        } else {
            return audioPlayer?.currentTime ?? 0
        }
    }
    
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            audioPlayer?.rate = playbackSpeed
            if isPlaying && isUsingAVPlayer { avPlayer?.rate = playbackSpeed }
        }
    }
    
    // MARK: - Private Properties
    
    var audioPlayer: AVAudioPlayer?
    var avPlayer: AVPlayer?
    private var isUsingAVPlayer = false
    private var playerItemObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    let playerType: String
    private let positionKey = "playbackPositions"
    
    // MARK: - Initialization
    
    init(type: String) {
        self.playerType = type
        super.init()
    }
    
    // MARK: - Artwork Extraction (Fixed for Build)
    
    private func extractArtwork(from asset: AVURLAsset) {
        // 1. Reset immediately
        DispatchQueue.main.async { self.artwork = nil }
        
        let url = asset.url
        
        // 2. Library Tracks (Apple Music/iTunes)
        if url.absoluteString.contains("ipod-library") {
            if let libraryArt = extractLibraryArtwork(url: url) {
                DispatchQueue.main.async { self.artwork = libraryArt }
            }
            return
        }
        
        // 3. Local Files (Deep Scan)
        Task {
            // Strategy A: Common Metadata (Fastest)
            if let image = await extractCommonArtwork(from: asset) {
                await updateArtwork(image)
                return
            }
            
            // Strategy B: Iterate ALL Metadata (Robust)
            if let image = await extractAllMetadata(from: asset) {
                await updateArtwork(image)
            }
        }
    }
    
    // Helper 1: Apple Music Library
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
    
    // Helper 2: Standard Common Metadata
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
    
    // Helper 3: Iterate EVERYTHING (Fixes Build Errors & Finds ID3/iTunes art)
    private func extractAllMetadata(from asset: AVAsset) async -> UIImage? {
        do {
            // Load all available formats (ID3, iTunes, etc)
            let formats = try await asset.load(.availableMetadataFormats)
            
            for format in formats {
                let metadata = try await asset.loadMetadata(for: format)
                
                for item in metadata {
                    // Check if the item has data value
                    if let data = try? await item.load(.dataValue) {
                        // Check if that data is an image
                        if let image = UIImage(data: data) {
                            return image
                        }
                    }
                    
                    // Fallback for older "value" property (sometimes needed for ID3)
                    if let value = try? await item.load(.value),
                       let data = value as? Data,
                       let image = UIImage(data: data) {
                        return image
                    }
                }
            }
        } catch { return nil }
        return nil
    }
    
    @MainActor
    private func updateArtwork(_ image: UIImage) {
        withAnimation(.easeIn(duration: 0.5)) {
            self.artwork = image
        }
    }
    
    // MARK: - Volume & Audio Logic
    
    private func updatePlayerVolume() {
        var finalVolume = volume
        if isDucking { finalVolume = volume * 0.2 }
        if isBoostEnabled { finalVolume = pow(volume, 0.5) }
        
        audioPlayer?.volume = finalVolume
        avPlayer?.volume = finalVolume
    }
    
    private func updateAudioSessionMode() {
        do {
            let session = AVAudioSession.sharedInstance()
            if isBoostEnabled { try session.setMode(.spokenAudio) }
            else { try session.setMode(.default) }
        } catch { print("❌ Failed to set audio mode: \(error)") }
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
    
    private func loadTrackAndPlay(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        currentIndex = index
        currentTrack = queue[index]
        stopCurrentPlayback()
        
        guard let track = currentTrack else { return }
        if track.filename.starts(with: "ipod-library://") { loadFromAssetURLAndPlay(track.filename) }
        else if track.filename.starts(with: "http") { loadRadioStreamAndPlay() }
        else { loadLocalFileAndPlay() }
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
    
    private func stopCurrentPlayback() {
        saveCurrentPosition()
        audioPlayer?.stop()
        audioPlayer = nil
        avPlayer?.pause()
        if let observer = timeObserver { avPlayer?.removeTimeObserver(observer); timeObserver = nil }
        playerItemObserver?.invalidate()
        playerItemObserver = nil
        avPlayer = nil
    }
    
    // MARK: - Loaders
    
    private func loadFromAssetURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        isUsingAVPlayer = true
        let asset = AVURLAsset(url: url)
        extractArtwork(from: asset)
        let item = AVPlayerItem(asset: asset)
        avPlayer = AVPlayer(playerItem: item)
        updatePlayerVolume()
        setupTimeObserver()
        setupEndObserver(for: item)
    }
    
    private func loadFromAssetURLAndPlay(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        isUsingAVPlayer = true
        let asset = AVURLAsset(url: url)
        extractArtwork(from: asset)
        let item = AVPlayerItem(asset: asset)
        avPlayer = AVPlayer(playerItem: item)
        updatePlayerVolume()
        setupTimeObserver()
        playerItemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                DispatchQueue.main.async { self?.restoreSavedPosition(); self?.play() }
            }
        }
        setupEndObserver(for: item)
    }
    
    private func loadRadioStream() {
        guard let track = currentTrack, let url = URL(string: track.filename) else { return }
        isUsingAVPlayer = true
        self.artwork = nil
        avPlayer = AVPlayer(playerItem: AVPlayerItem(url: url))
        updatePlayerVolume()
    }
    
    private func loadRadioStreamAndPlay() {
        guard let track = currentTrack, let url = URL(string: track.filename) else { return }
        isUsingAVPlayer = true
        self.artwork = nil
        let item = AVPlayerItem(url: url)
        avPlayer = AVPlayer(playerItem: item)
        updatePlayerVolume()
        playerItemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay { DispatchQueue.main.async { self?.play() } }
        }
    }
    
    private func loadLocalFile() {
        guard let track = currentTrack else { return }
        isUsingAVPlayer = false
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(track.filename)
        let asset = AVURLAsset(url: path)
        extractArtwork(from: asset)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: path)
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackSpeed
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            updatePlayerVolume()
        } catch { print("Error loading: \(error)") }
    }
    
    private func loadLocalFileAndPlay() {
        guard let track = currentTrack else { return }
        isUsingAVPlayer = false
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(track.filename)
        let asset = AVURLAsset(url: path)
        extractArtwork(from: asset)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: path)
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackSpeed
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            updatePlayerVolume()
            if playerType == "Speech" { restoreSavedPosition() }
            play()
        } catch { print("Error loading: \(error)") }
    }
    
    // MARK: - Observers & Controls
    
    private func setupTimeObserver() {
        guard playerType == "Speech" else { return }
        let interval = CMTimeMakeWithSeconds(10, preferredTimescale: 1)
        timeObserver = avPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in self?.saveCurrentPosition() }
    }
    
    private func setupEndObserver(for item: AVPlayerItem) {
        NotificationCenter.default.addObserver(self, selector: #selector(avPlayerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: item)
    }
    
    @objc private func avPlayerDidFinishPlaying(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let track = self.currentTrack { self.clearPosition(for: track.filename) }
            if self.playerType == "Music" { self.next() }
            else { self.isPlaying = false }
        }
    }
    
    func play() {
        if isUsingAVPlayer { avPlayer?.play(); avPlayer?.rate = playbackSpeed }
        else { audioPlayer?.play() }
        isPlaying = true
    }
    
    func pause() {
        saveCurrentPosition()
        if isUsingAVPlayer { avPlayer?.pause() } else { audioPlayer?.pause() }
        isPlaying = false
    }
    
    func togglePlayPause() { isPlaying ? pause() : play() }
    
    func next() {
        guard !queue.isEmpty else { return }
        if let track = currentTrack { clearPosition(for: track.filename) }
        let wasPlaying = isPlaying
        currentIndex = (currentIndex + 1) % queue.count
        wasPlaying ? loadTrackAndPlay(at: currentIndex) : loadTrack(at: currentIndex)
    }
    
    func previous() {
        guard !queue.isEmpty else { return }
        let time = currentTime
        let wasPlaying = isPlaying
        if time > 3 {
            seek(to: 0)
            if wasPlaying { play() }
        } else {
            currentIndex = currentIndex == 0 ? queue.count - 1 : currentIndex - 1
            wasPlaying ? loadTrackAndPlay(at: currentIndex) : loadTrack(at: currentIndex)
        }
    }
    
    func seek(to time: Double) {
        if isUsingAVPlayer { avPlayer?.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: 600)) }
        else { audioPlayer?.currentTime = time }
    }
    
    func skipForward(seconds: Double = 30) {
        let new = currentTime + seconds
        (duration > 0 && new >= duration) ? next() : seek(to: new)
    }
    
    func skipBackward(seconds: Double = 30) { seek(to: max(0, currentTime - seconds)) }
    
    func cycleSpeed() {
        let speeds: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0]
        if let idx = speeds.firstIndex(of: playbackSpeed) { playbackSpeed = speeds[(idx + 1) % speeds.count] }
        else { playbackSpeed = 1.0 }
        if isPlaying && isUsingAVPlayer { avPlayer?.rate = playbackSpeed }
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
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if let track = currentTrack { clearPosition(for: track.filename) }
        (flag && playerType == "Music") ? next() : (isPlaying = false)
    }
}
