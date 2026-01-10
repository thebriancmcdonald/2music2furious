//
//  AudioPlayer.swift
//  2 Music 2 Furious - MILESTONE 11
//
//  PERFORMANCE UPDATES:
//  - Added Lock Screen Support (MPNowPlayingInfoCenter)
//  - Added playFromQueue for QueueView compatibility
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
import SwiftUI

class AudioPlayer: NSObject, ObservableObject {
    
    @Published var isPlaying = false {
        didSet { updateNowPlayingInfo() }
    }
    @Published var currentTrack: Track?
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var isShuffled = false
    @Published var artwork: UIImage? = nil {
        didSet { updateNowPlayingInfo() }
    }
    @Published var volume: Float = 0.5 {
        didSet { updatePlayerVolume() }
    }
    @Published var isDucking = false {
        didSet { updatePlayerVolume() }
    }
    @Published var isBoostEnabled = false {
        didSet { updateAudioEffects() }
    }
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            if isUsingEngine { timePitchNode.rate = playbackSpeed }
            else { avPlayer?.rate = isPlaying ? playbackSpeed : 0 }
            updateNowPlayingInfo()
        }
    }
    
    private static var artworkCache: [String: UIImage] = [:]
    private static let cacheQueue = DispatchQueue(label: "artworkCache", attributes: .concurrent)
    private static func getCachedArtwork(for key: String) -> UIImage? { cacheQueue.sync { artworkCache[key] } }
    private static func setCachedArtwork(_ image: UIImage, for key: String) { cacheQueue.async(flags: .barrier) { artworkCache[key] = image } }
    
    var duration: Double {
        if isUsingEngine {
            guard let file = audioFile else { return 0 }
            return Double(file.length) / file.processingFormat.sampleRate
        } else {
            return avPlayer?.currentItem?.duration.seconds ?? 0
        }
    }
    
    var currentTime: Double {
        if isUsingEngine {
            guard isPlaying, let nodeTime = playerNode.lastRenderTime, let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return seekOffset }
            return seekOffset + (Double(playerTime.sampleTime) / audioSampleRate)
        } else {
            return avPlayer?.currentTime().seconds ?? 0
        }
    }
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitchNode = AVAudioUnitTimePitch()
    private let boosterNode = AVAudioMixerNode()
    private var audioFile: AVAudioFile?
    private var audioSampleRate: Double = 44100
    private var seekOffset: TimeInterval = 0
    private var isUsingEngine = false
    private var avPlayer: AVPlayer?
    private var playerItemObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    
    // NEW:
    private var currentExternalArtworkURL: URL? = nil
    
    let playerType: String
    private let positionKey = "playbackPositions"
    
    init(type: String) {
        self.playerType = type
        super.init()
        setupEngine()
    }
    
    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(timePitchNode)
        engine.attach(boosterNode)
        engine.connect(playerNode, to: timePitchNode, format: nil)
        engine.connect(timePitchNode, to: boosterNode, format: nil)
        engine.connect(boosterNode, to: engine.mainMixerNode, format: nil)
        boosterNode.outputVolume = 1.0
    }
    
    func updateNowPlayingInfo() {
        var info = [String: Any]()
        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.title
            info[MPMediaItemPropertyArtist] = track.artist
        }
        if let image = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updateAudioEffects() {
        if isUsingEngine {
            boosterNode.outputVolume = isBoostEnabled ? 4.0 : 1.0
            engine.mainMixerNode.outputVolume = isDucking ? 0.2 : volume
        }
    }
    
    private func updatePlayerVolume() {
        if isUsingEngine {
            engine.mainMixerNode.outputVolume = isDucking ? volume * 0.2 : volume
        } else {
            avPlayer?.volume = isDucking ? volume * 0.2 : volume
        }
    }
    
    func setExternalArtwork(from url: URL?) {
        self.currentExternalArtworkURL = url
        guard let url = url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.artwork = image; self?.updateNowPlayingInfo() }
        }.resume()
    }
    
    private func extractArtwork(from asset: AVURLAsset) {
        if let externalURL = currentExternalArtworkURL {
            setExternalArtwork(from: externalURL)
            return
        }
        let urlKey = asset.url.absoluteString
        if let cached = Self.getCachedArtwork(for: urlKey) {
            DispatchQueue.main.async { withAnimation(.easeIn(duration: 0.3)) { self.artwork = cached; self.updateNowPlayingInfo() } }
            return
        }
        DispatchQueue.main.async { self.artwork = nil }
        
        if asset.url.absoluteString.contains("ipod-library") {
            if let libraryArt = extractLibraryArtwork(url: asset.url) {
                Self.setCachedArtwork(libraryArt, for: urlKey)
                DispatchQueue.main.async { withAnimation(.easeIn(duration: 0.3)) { self.artwork = libraryArt; self.updateNowPlayingInfo() } }
            }
            return
        }
        Task {
            if let image = await extractCommonArtwork(from: asset) {
                Self.setCachedArtwork(image, for: urlKey)
                await MainActor.run { withAnimation(.easeIn(duration: 0.3)) { self.artwork = image; self.updateNowPlayingInfo() } }
                return
            }
            if let image = await extractAllMetadata(from: asset) {
                Self.setCachedArtwork(image, for: urlKey)
                await MainActor.run { withAnimation(.easeIn(duration: 0.3)) { self.artwork = image; self.updateNowPlayingInfo() } }
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
               let data = try await item.load(.dataValue), let image = UIImage(data: data) { return image }
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

    func saveCurrentPosition() {
        guard playerType != "Music", let track = currentTrack else { return }
        let position = self.currentTime
        if position > 5 {
            var positions = UserDefaults.standard.dictionary(forKey: positionKey) as? [String: Double] ?? [:]
            positions[track.filename] = position
            UserDefaults.standard.set(positions, forKey: positionKey)
        }
    }
    
    private func restoreSavedPosition() {
        guard playerType != "Music", let track = currentTrack else { return }
        let positions = UserDefaults.standard.dictionary(forKey: positionKey) as? [String: Double] ?? [:]
        if let saved = positions[track.filename], saved > 5 { seek(to: saved) }
    }
    
    func playNow(_ track: Track, artworkURL: URL? = nil) {
        saveCurrentPosition()
        pause()
        self.currentExternalArtworkURL = artworkURL
        queue.insert(track, at: 0)
        currentIndex = 0
        loadTrackAndPlay(at: 0)
    }
    
    func loadTrack(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        stopCurrentPlayback()
        let track = queue[index]
        currentIndex = index
        currentTrack = track
        
        if track.filename.starts(with: "ipod-library://") {
            isUsingEngine = false
            let asset = AVURLAsset(url: URL(string: track.filename)!)
            if currentExternalArtworkURL == nil { extractArtwork(from: asset) } else { setExternalArtwork(from: currentExternalArtworkURL) }
            setupAVPlayer(with: AVPlayerItem(asset: asset))
        } else if track.filename.starts(with: "http") {
            isUsingEngine = false
            if let ext = currentExternalArtworkURL { setExternalArtwork(from: ext) } else { self.artwork = nil }
            setupAVPlayer(with: AVPlayerItem(url: URL(string: track.filename)!))
        } else {
            loadLocalFile(track: track)
        }
        updateNowPlayingInfo()
    }
    
    private func loadLocalFile(track: Track) {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(track.filename)
        if currentExternalArtworkURL == nil { extractArtwork(from: AVURLAsset(url: path)) } else { setExternalArtwork(from: currentExternalArtworkURL) }
        
        do {
            isUsingEngine = true
            audioFile = try AVAudioFile(forReading: path)
            audioSampleRate = audioFile!.processingFormat.sampleRate
            engine.reset()
            scheduleFileSegment(from: 0)
            try engine.start()
            updateAudioEffects()
            restoreSavedPosition()
        } catch { print("Engine load error: \(error)") }
    }
    
    private func loadTrackAndPlay(at index: Int) { loadTrack(at: index); if isUsingEngine { play() } }
    
    private func stopCurrentPlayback() {
        saveCurrentPosition()
        if engine.isRunning { playerNode.stop(); engine.stop() }
        avPlayer?.pause()
        if let observer = timeObserver { avPlayer?.removeTimeObserver(observer); timeObserver = nil }
        playerItemObserver?.invalidate()
        avPlayer = nil
        audioFile = nil
        seekOffset = 0
        updateNowPlayingInfo()
    }
    
    private func setupAVPlayer(with item: AVPlayerItem) {
        avPlayer = AVPlayer(playerItem: item)
        updatePlayerVolume()
        playerItemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                DispatchQueue.main.async { self?.restoreSavedPosition(); if self?.currentTrack?.filename.starts(with: "http") == true { self?.play() } }
            }
        }
        timeObserver = avPlayer?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] _ in self?.updateNowPlayingInfo() }
    }
    
    private func scheduleFileSegment(from startTime: Double) {
        guard let file = audioFile else { return }
        let startFrame = AVAudioFramePosition(startTime * file.processingFormat.sampleRate)
        let remainingFrames = AVAudioFrameCount(file.length - startFrame)
        guard remainingFrames > 0 else { return }
        playerNode.stop()
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: remainingFrames, at: nil)
        seekOffset = startTime
        timePitchNode.rate = playbackSpeed
    }
    
    func play() {
        try? AVAudioSession.sharedInstance().setActive(true)
        if isUsingEngine { if !engine.isRunning { try? engine.start() }; playerNode.play() }
        else { avPlayer?.play(); avPlayer?.rate = playbackSpeed }
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    func pause() {
        saveCurrentPosition()
        if isUsingEngine { playerNode.pause(); engine.pause() } else { avPlayer?.pause() }
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    func togglePlayPause() { isPlaying ? pause() : play() }
    
    func next() {
        guard !queue.isEmpty else { return }
        loadTrackAndPlay(at: (currentIndex + 1) % queue.count)
    }
    
    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 { seek(to: 0) }
        else { loadTrackAndPlay(at: currentIndex == 0 ? queue.count - 1 : currentIndex - 1) }
    }
    
    func seek(to time: Double) {
        if isUsingEngine { scheduleFileSegment(from: time); if isPlaying { playerNode.play() } }
        else { avPlayer?.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: 600)) }
        updateNowPlayingInfo()
    }
    
    func skipForward(seconds: Double = 30) { seek(to: min(duration, currentTime + seconds)) }
    func skipBackward(seconds: Double = 30) { seek(to: max(0, currentTime - seconds)) }
    
    func cycleSpeed() {
        let speeds: [Float] = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0]
        if let idx = speeds.firstIndex(where: { abs($0 - playbackSpeed) < 0.01 }) { playbackSpeed = speeds[(idx + 1) % speeds.count] }
        else { playbackSpeed = 1.0 }
    }
    
    func shuffle() {
        guard queue.count > 1 else { return }
        isShuffled.toggle()
        if isShuffled { let current = currentTrack; queue.shuffle(); if let t = current, let idx = queue.firstIndex(where: { $0.id == t.id }) { currentIndex = idx } }
    }
    
    func clearQueue() { saveCurrentPosition(); stopCurrentPlayback(); queue.removeAll(); currentTrack = nil; currentIndex = 0; isPlaying = false; artwork = nil; updateNowPlayingInfo() }
    
    func addTrack(from url: URL) {
        let filename = url.lastPathComponent
        let title = filename.replacingOccurrences(of: "_", with: " ").components(separatedBy: ".").first ?? filename
        addTrackToQueue(Track(title: title, artist: "Unknown", filename: filename))
    }
    
    func addTrackToQueue(_ track: Track) {
        queue.append(track)
        if queue.count == 1 { loadTrack(at: 0) }
    }
    
    func addRadioStream(name: String, streamURL: String, artworkURL: String? = nil) {
        let url = artworkURL != nil ? URL(string: artworkURL!) : nil
        playNow(Track(title: name, artist: "Radio", filename: streamURL), artworkURL: url)
    }
    
    func playFromQueue(at index: Int) { loadTrackAndPlay(at: index) }
    
    static func clearArtworkCache() { cacheQueue.async(flags: .barrier) { artworkCache.removeAll() } }
    
    deinit { NotificationCenter.default.removeObserver(self); playerItemObserver?.invalidate(); if let observer = timeObserver { avPlayer?.removeTimeObserver(observer) }; engine.stop() }
}
