//
//  AudioPlayer.swift
//  2 Music 2 Furious
//
//  UPDATED: Uses ImageCache for reliable Audiobook covers
//  FIXED: Artwork logic now uses caching layer instead of raw URLSession
//  UPDATED: Chapter boundary support for M4B audiobooks (virtual chapters)
//  FIXED: No longer auto-plays on app startup - starts paused with state restored
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
import SwiftUI

// MARK: - Playback State for Persistence

struct PlaybackState: Codable {
    let currentTrack: Track?
    let queue: [Track]
    let currentIndex: Int
    let currentPosition: Double
    let volume: Float
    let playbackSpeed: Float
    let isBoostEnabled: Bool
    let artworkURLString: String?
    let lastSaveTime: Date
}

class AudioPlayer: NSObject, ObservableObject {
    
    // MARK: - Published State
    @Published var isPlaying = false {
        didSet { LockScreenManager.shared.update() }
    }
    @Published var currentTrack: Track? {
        didSet { LockScreenManager.shared.update() }
    }
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var isShuffled = false
    @Published var artwork: UIImage? = nil {
        didSet { LockScreenManager.shared.update() }
    }
    @Published var volume: Float = 0.5 {
        didSet { updatePlayerVolume() }
    }
    @Published var isDucking = false {
        didSet { updatePlayerVolume() }
    }
    
    // Audio Engine Mode: .quality uses AVPlayer (better speed), .boost uses AVAudioEngine (has boost)
    enum AudioMode: String, CaseIterable {
        case quality = "Quality"
        case boost = "Boost"
    }
    
    @Published var audioMode: AudioMode = .quality {
        didSet {
            // When switching to Boost mode, enable the boost effect
            // When switching to Quality mode, disable it (and use better engine)
            if audioMode == .boost {
                isBoostEnabled = true
            } else {
                isBoostEnabled = false
            }
            
            // If currently playing, reload track with new engine
            if let track = currentTrack, isPlaying {
                let currentPos = currentTime
                let wasPlaying = isPlaying
                loadTrack(at: currentIndex)
                seek(to: currentPos)
                if wasPlaying { play() }
            }
            // Save preference
            UserDefaults.standard.set(audioMode.rawValue, forKey: "audioMode_\(playerType)")
        }
    }
    @Published var isBoostEnabled = false {
        didSet { updateAudioEffects() }
    }
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            if isUsingEngine { timePitchNode.rate = playbackSpeed }
            else { avPlayer?.rate = isPlaying ? playbackSpeed : 0 }
            LockScreenManager.shared.update()
        }
    }
    
    // MARK: - Internal Properties
    private static var artworkCache: [String: UIImage] = [:]
    private static let cacheQueue = DispatchQueue(label: "artworkCache", attributes: .concurrent)
    private static func getCachedArtwork(for key: String) -> UIImage? { cacheQueue.sync { artworkCache[key] } }
    private static func setCachedArtwork(_ image: UIImage, for key: String) { cacheQueue.async(flags: .barrier) { artworkCache[key] = image } }
    
    // MARK: - Duration (Chapter-Aware)
    // Returns chapter duration if track has boundaries, otherwise full file duration
    var duration: Double {
        // If track has chapter boundaries, return chapter duration
        if let track = currentTrack, let chapterDuration = track.chapterDuration {
            return chapterDuration
        }
        
        // Otherwise return full file duration
        var result: Double = 0
        if isUsingEngine {
            guard let file = audioFile else { return 0 }
            let sampleRate = file.processingFormat.sampleRate
            guard sampleRate > 0 else { return 0 }
            result = Double(file.length) / sampleRate
        } else {
            result = avPlayer?.currentItem?.duration.seconds ?? 0
        }
        // Safety: Return 0 for invalid durations
        guard result.isFinite && result >= 0 else { return 0 }
        return result
    }
    
    // MARK: - Current Time (Chapter-Aware)
    // Returns position relative to chapter start if track has boundaries
    var currentTime: Double {
        var absoluteTime: Double = 0
        if isUsingEngine {
            guard isPlaying, let nodeTime = playerNode.lastRenderTime, let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return max(0, seekOffset - (currentTrack?.startTime ?? 0)) }
            absoluteTime = seekOffset + (Double(playerTime.sampleTime) / audioSampleRate)
        } else {
            absoluteTime = avPlayer?.currentTime().seconds ?? 0
        }
        
        // Safety: Return 0 for invalid times
        guard absoluteTime.isFinite && absoluteTime >= 0 else { return 0 }
        
        // If track has chapter boundaries, return time relative to chapter start
        if let track = currentTrack, let startTime = track.startTime {
            let relativeTime = absoluteTime - startTime
            return max(0, relativeTime)
        }
        
        return absoluteTime
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
    
    // Chapter boundary monitoring
    private var chapterEndObserver: Any?
    private var isHandlingChapterEnd = false  // Guard against multiple triggers
    private var playbackGeneration: Int = 0   // Increments each time we load a new track
    private var isRestoringState = false      // Suppress auto-play during state restoration
    
    private var currentExternalArtworkURL: URL? = nil
    
    let playerType: String
    private let positionKey = "playbackPositions"
    
    // MARK: - Persistence Properties
    private var stateKey: String { "playbackState_\(playerType)" }
    private var periodicSaveTimer: Timer?
    
    init(type: String) {
        self.playerType = type
        super.init()
        setupEngine()
        startPeriodicSaveTimer()
        
        // Restore audio mode preference
        if let savedMode = UserDefaults.standard.string(forKey: "audioMode_\(type)"),
           let mode = AudioMode(rawValue: savedMode) {
            self.audioMode = mode
        }
    }
    
    private func startPeriodicSaveTimer() {
        periodicSaveTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying, self.currentTrack != nil else { return }
            self.saveFullState()
        }
    }
    
    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(timePitchNode)
        engine.attach(boosterNode)
        engine.connect(playerNode, to: timePitchNode, format: nil)
        engine.connect(timePitchNode, to: boosterNode, format: nil)
        engine.connect(boosterNode, to: engine.mainMixerNode, format: nil)
        boosterNode.outputVolume = 1.0
        
        // Improve time-stretch quality for speech (default is 8, max is 32)
        // Using 16 as compromise between quality and stability
        timePitchNode.pitch = 0
        timePitchNode.overlap = 16
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
    
    // UPDATED: Use ImageCache here
    func setExternalArtwork(from url: URL?) {
        self.currentExternalArtworkURL = url
        guard let url = url else {
            self.artwork = nil
            return
        }
        
        // Try ImageCache first (fast/cached)
        ImageCache.shared.image(for: url) { [weak self] image in
            DispatchQueue.main.async {
                self?.artwork = image
            }
        }
    }
    
    private func extractArtwork(from asset: AVURLAsset) {
        if let externalURL = currentExternalArtworkURL {
            setExternalArtwork(from: externalURL)
            return
        }
        let urlKey = asset.url.absoluteString
        if let cached = Self.getCachedArtwork(for: urlKey) {
            DispatchQueue.main.async { withAnimation(.easeIn(duration: 0.3)) { self.artwork = cached } }
            return
        }
        DispatchQueue.main.async { self.artwork = nil }
        
        if asset.url.absoluteString.contains("ipod-library") {
            if let libraryArt = extractLibraryArtwork(url: asset.url) {
                Self.setCachedArtwork(libraryArt, for: urlKey)
                DispatchQueue.main.async { withAnimation(.easeIn(duration: 0.3)) { self.artwork = libraryArt } }
            }
            return
        }
        Task {
            if let image = await extractCommonArtwork(from: asset) {
                Self.setCachedArtwork(image, for: urlKey)
                await MainActor.run { withAnimation(.easeIn(duration: 0.3)) { self.artwork = image } }
                return
            }
            if let image = await extractAllMetadata(from: asset) {
                Self.setCachedArtwork(image, for: urlKey)
                await MainActor.run { withAnimation(.easeIn(duration: 0.3)) { self.artwork = image } }
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
        // For chapter tracks, save absolute position (not chapter-relative)
        let absolutePosition: Double
        if track.hasChapterBoundaries, let startTime = track.startTime {
            absolutePosition = startTime + self.currentTime
        } else {
            absolutePosition = self.currentTime
        }
        
        if absolutePosition > 5 {
            var positions = UserDefaults.standard.dictionary(forKey: positionKey) as? [String: Double] ?? [:]
            // Use track ID for chaptered tracks to save per-chapter position
            let key = track.hasChapterBoundaries ? track.id.uuidString : track.filename
            positions[key] = absolutePosition
            UserDefaults.standard.set(positions, forKey: positionKey)
        }
        // Also save full state
        saveFullState()
    }
    
    private func restoreSavedPosition() {
        guard playerType != "Music", let track = currentTrack else { return }
        let positions = UserDefaults.standard.dictionary(forKey: positionKey) as? [String: Double] ?? [:]
        let key = track.hasChapterBoundaries ? track.id.uuidString : track.filename
        print("ðŸŽµ restoreSavedPosition: key=\(key), saved=\(positions[key] ?? -1)")
        if let saved = positions[key], saved > 5 {
            // For chapter tracks, seek to saved absolute position
            if track.hasChapterBoundaries, let startTime = track.startTime {
                let relativePosition = saved - startTime
                print("ðŸŽµ restoreSavedPosition: seeking to relative \(relativePosition)")
                if relativePosition > 0 {
                    seek(to: relativePosition)
                }
            } else {
                print("ðŸŽµ restoreSavedPosition: seeking to \(saved)")
                seek(to: saved)
            }
        } else {
            print("ðŸŽµ restoreSavedPosition: no saved position or < 5 sec")
        }
    }
    
    // MARK: - Full State Persistence
    
    func saveFullState() {
        guard currentTrack != nil else { return }
        
        let state = PlaybackState(
            currentTrack: currentTrack,
            queue: queue,
            currentIndex: currentIndex,
            currentPosition: currentTime,
            volume: volume,
            playbackSpeed: playbackSpeed,
            isBoostEnabled: isBoostEnabled,
            artworkURLString: currentExternalArtworkURL?.absoluteString,
            lastSaveTime: Date()
        )
        
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
    
    func restoreState(completion: (() -> Void)? = nil) {
        isRestoringState = true  // Suppress auto-play during restoration
        
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(PlaybackState.self, from: data) else {
            isRestoringState = false
            completion?()
            return
        }
        
        // Check if state is too old (7 days)
        if Date().timeIntervalSince(state.lastSaveTime) > 7 * 24 * 60 * 60 {
            isRestoringState = false
            completion?()
            return
        }
        
        // Restore settings
        volume = state.volume
        playbackSpeed = state.playbackSpeed
        isBoostEnabled = state.isBoostEnabled
        
        // Restore queue and track
        queue = state.queue
        currentIndex = state.currentIndex
        
        // Restore artwork URL
        if let urlString = state.artworkURLString, let url = URL(string: urlString) {
            currentExternalArtworkURL = url
        }
        
        // Load the track if present
        if state.currentTrack != nil && !queue.isEmpty {
            loadTrack(at: state.currentIndex)
            
            // Restore position after a short delay (let track load)
            // Note: isRestoringState is cleared inside setupAVPlayer/loadLocalFile after the
            // auto-play check, so it stays true until that check has been made regardless
            // of how long network buffering takes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if state.currentPosition > 5 {
                    self.seek(to: state.currentPosition)
                }
                completion?()
            }
        } else {
            isRestoringState = false
            completion?()
        }
    }
    
    func clearSavedState() {
        UserDefaults.standard.removeObject(forKey: stateKey)
    }
    
    func playNow(_ track: Track, artworkURL: URL? = nil) {
        saveCurrentPosition()
        pause()
        setExternalArtwork(from: artworkURL)
        queue.insert(track, at: 0)
        currentIndex = 0
        loadTrackAndPlay(at: 0)
    }
    
    func loadTrack(at index: Int) {
        print("ðŸŽµ loadTrack called: index=\(index), queue.count=\(queue.count)")
        guard index >= 0 && index < queue.count else { 
            print("ðŸŽµ loadTrack: index out of bounds!")
            return 
        }
        isHandlingChapterEnd = false  // Reset chapter end guard for new track
        stopCurrentPlayback()
        let track = queue[index]
        currentIndex = index
        currentTrack = track
        
        print("ðŸŽµ Loading track: \(track.title), startTime=\(track.startTime ?? -1), endTime=\(track.endTime ?? -1)")
        
        if track.filename.starts(with: "ipod-library://") {
            print("ðŸŽµ Using iPod library path")
            isUsingEngine = false
            let asset = AVURLAsset(url: URL(string: track.filename)!)
            if currentExternalArtworkURL == nil { extractArtwork(from: asset) } else { setExternalArtwork(from: currentExternalArtworkURL) }
            setupAVPlayer(with: AVPlayerItem(asset: asset), track: track)
        } else if track.filename.starts(with: "http") {
            print("ðŸŽµ Using HTTP streaming path")
            isUsingEngine = false
            if let ext = currentExternalArtworkURL { setExternalArtwork(from: ext) } else { self.artwork = nil }
            setupAVPlayer(with: AVPlayerItem(url: URL(string: track.filename)!), track: track)
        } else {
            print("ðŸŽµ Using local file path")
            loadLocalFile(track: track)
        }
        LockScreenManager.shared.update()
    }
    
    private func loadLocalFile(track: Track) {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(track.filename)
        print("ðŸŽµ loadLocalFile: \(path.lastPathComponent), mode: \(audioMode.rawValue)")
        if currentExternalArtworkURL == nil { extractArtwork(from: AVURLAsset(url: path)) } else { setExternalArtwork(from: currentExternalArtworkURL) }
        
        // Quality mode: Use AVPlayer for better speed algorithm
        if audioMode == .quality {
            print("ðŸŽµ Using AVPlayer (Quality mode)")
            isUsingEngine = false
            let asset = AVURLAsset(url: path)
            setupAVPlayer(with: AVPlayerItem(asset: asset), track: track)
            return
        }
        
        // Boost mode: Use AVAudioEngine for audio processing
        print("ðŸŽµ Using AVAudioEngine (Boost mode)")
        do {
            isUsingEngine = true
            audioFile = try AVAudioFile(forReading: path)
            audioSampleRate = audioFile!.processingFormat.sampleRate
            engine.reset()
            
            // For chapter tracks, start at chapter beginning
            let startPosition = track.startTime ?? 0
            print("ðŸŽµ Scheduling from startPosition: \(startPosition)")
            scheduleFileSegment(from: startPosition, track: track)
            
            try engine.start()
            updateAudioEffects()
            // FIX: Only restore saved position during actual state restoration
            // Not when user explicitly selects a chapter (prevents skipping to chapter end)
            if isRestoringState {
                restoreSavedPosition()
            }
            isRestoringState = false  // Clear flag after setup complete
        } catch { 
            isRestoringState = false  // Clear flag even on error
            print("Engine load error: \(error)") 
        }
    }
    
    private func loadTrackAndPlay(at index: Int) { 
        loadTrack(at: index)
        // Always call play() - for AVPlayer it will start when ready via observer
        // For AVAudioEngine it will start immediately
        play()
    }
    
    private func stopCurrentPlayback() {
        saveCurrentPosition()
        if engine.isRunning { playerNode.stop(); engine.stop() }
        avPlayer?.pause()
        
        // Remove chapter end observer
        if let observer = chapterEndObserver {
            avPlayer?.removeTimeObserver(observer)
            chapterEndObserver = nil
        }
        
        if let observer = timeObserver { avPlayer?.removeTimeObserver(observer); timeObserver = nil }
        playerItemObserver?.invalidate()
        avPlayer = nil
        audioFile = nil
        seekOffset = 0
        LockScreenManager.shared.update()
    }
    
    // MARK: - AVPlayer Setup (Chapter-Aware)
    private func setupAVPlayer(with item: AVPlayerItem, track: Track) {
        print("ðŸŽµ setupAVPlayer for: \(track.title), isRestoringState: \(isRestoringState)")
        avPlayer = AVPlayer(playerItem: item)
        updatePlayerVolume()
        
        // Track if this is a local file that should auto-play when ready
        let isLocalChapterFile = track.hasChapterBoundaries && !track.filename.starts(with: "http")
        
        playerItemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    print("ðŸŽµ AVPlayer ready, track has boundaries: \(track.hasChapterBoundaries), isRestoringState: \(self.isRestoringState)")
                    
                    // For chapter tracks, seek to chapter start first
                    if track.hasChapterBoundaries, let startTime = track.startTime {
                        print("ðŸŽµ Seeking to chapter start: \(startTime)")
                        self.avPlayer?.seek(to: CMTimeMakeWithSeconds(startTime, preferredTimescale: 600)) { finished in
                            print("ðŸŽµ Seek to start completed: \(finished)")
                            // FIX: Only restore saved position during actual state restoration
                            // Not when user explicitly selects a chapter (prevents skipping to chapter end)
                            if self.isRestoringState {
                                self.restoreSavedPosition()
                            }
                            // Auto-play for HTTP streams OR local chapter files (but NOT during state restoration)
                            let shouldAutoPlay = !self.isRestoringState && (track.filename.starts(with: "http") || isLocalChapterFile)
                            self.isRestoringState = false  // Clear flag after check
                            if shouldAutoPlay {
                                print("ðŸŽµ Auto-playing after seek")
                                self.play()
                            }
                        }
                    } else {
                        // FIX: Only restore saved position during actual state restoration
                        if self.isRestoringState {
                            self.restoreSavedPosition()
                        }
                        // Auto-play for HTTP streams (but NOT during state restoration)
                        let shouldAutoPlay = !self.isRestoringState && track.filename.starts(with: "http")
                        self.isRestoringState = false  // Clear flag after check
                        if shouldAutoPlay {
                            print("ðŸŽµ Auto-playing HTTP stream")
                            self.play()
                        }
                    }
                }
            }
        }
        
        // Standard time observer for lock screen updates
        timeObserver = avPlayer?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            guard let self = self else { return }
            LockScreenManager.shared.update()
            
            // Check for chapter end (for AVPlayer path)
            if let track = self.currentTrack,
               let endTime = track.endTime {
                let currentSecs = time.seconds
                if currentSecs >= endTime - 0.5 {
                    print("ðŸŽµ Time observer: currentTime=\(currentSecs), endTime=\(endTime) - TRIGGERING CHAPTER END")
                    self.handleChapterEnd()
                }
            }
        }
        
        // Add boundary time observer for precise chapter end detection
        if track.hasChapterBoundaries, let endTime = track.endTime {
            print("ðŸŽµ Adding boundary observer at: \(endTime)")
            let boundaryTime = CMTimeMakeWithSeconds(endTime, preferredTimescale: 600)
            chapterEndObserver = avPlayer?.addBoundaryTimeObserver(forTimes: [NSValue(time: boundaryTime)], queue: .main) { [weak self] in
                print("ðŸŽµ Boundary observer triggered!")
                self?.handleChapterEnd()
            }
        }
    }
    
    // MARK: - Chapter End Handling
    private func handleChapterEnd() {
        // Guard against multiple triggers from periodic observer
        guard !isHandlingChapterEnd else { 
            print("ðŸŽµ handleChapterEnd: already handling, skipping")
            return 
        }
        guard currentTrack?.hasChapterBoundaries == true else { 
            print("ðŸŽµ handleChapterEnd: track has no chapter boundaries, skipping")
            return 
        }
        
        print("ðŸŽµ handleChapterEnd: advancing from index \(currentIndex) to \(currentIndex + 1)")
        isHandlingChapterEnd = true  // Prevent re-entry until next track loads
        
        // Auto-advance to next track in queue
        if currentIndex + 1 < queue.count {
            next()
        } else {
            // End of queue - pause at chapter end
            print("ðŸŽµ handleChapterEnd: end of queue, pausing")
            pause()
            isHandlingChapterEnd = false  // Reset since we're not loading a new track
        }
    }
    
    // MARK: - Schedule File Segment (Chapter-Aware for AVAudioEngine)
    private func scheduleFileSegment(from startTime: Double, track: Track? = nil) {
        guard let file = audioFile else { return }
        
        // Increment generation to invalidate any pending completion handlers
        playbackGeneration += 1
        print("ðŸŽµ scheduleFileSegment: generation now \(playbackGeneration)")
        
        let trackToUse = track ?? currentTrack
        
        // Safety: Ensure startTime is non-negative
        let safeStartTime = max(0, startTime)
        
        // Calculate start frame with bounds checking
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return }
        
        let calculatedStartFrame = Int64(safeStartTime * sampleRate)
        let fileLength = file.length
        
        // Safety: Ensure startFrame doesn't exceed file length
        let startFrame = min(calculatedStartFrame, fileLength)
        guard startFrame >= 0 else { return }
        
        // Calculate end frame (either chapter end or file end)
        let endFrame: Int64
        if let trackEndTime = trackToUse?.endTime {
            let calculatedEndFrame = Int64(trackEndTime * sampleRate)
            endFrame = min(calculatedEndFrame, fileLength)
        } else {
            endFrame = fileLength
        }
        
        // Safety: Calculate remaining frames, ensuring non-negative
        let remainingFramesInt64 = endFrame - startFrame
        guard remainingFramesInt64 > 0 else { return }
        
        // Safe conversion to AVAudioFrameCount (UInt32)
        let remainingFrames = AVAudioFrameCount(min(remainingFramesInt64, Int64(UInt32.max)))
        
        playerNode.stop()
        
        // Capture current generation - completion handler will only fire if generation matches
        let capturedGeneration = playbackGeneration
        
        // Schedule with completion handler for chapter end detection
        playerNode.scheduleSegment(file, startingFrame: AVAudioFramePosition(startFrame), frameCount: remainingFrames, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Ignore if this is from an old track (generation changed)
                guard self.playbackGeneration == capturedGeneration else {
                    print("ðŸŽµ Completion handler: ignoring - generation mismatch (\(capturedGeneration) vs \(self.playbackGeneration))")
                    return
                }
                
                guard let currentTrack = self.currentTrack,
                      currentTrack.hasChapterBoundaries,
                      self.isPlaying else { 
                    print("ðŸŽµ Completion handler: ignoring - not playing or no boundaries")
                    return 
                }
                
                print("ðŸŽµ Completion handler: chapter naturally ended, advancing...")
                // Chapter ended - advance to next
                self.handleChapterEnd()
            }
        }
        
        seekOffset = safeStartTime
        timePitchNode.rate = playbackSpeed
    }
    
    func play() {
        try? AVAudioSession.sharedInstance().setActive(true)
        if isUsingEngine {
            do {
                if !engine.isRunning {
                    try engine.start()
                }
                // Only play if engine is actually running now
                if engine.isRunning {
                    playerNode.play()
                } else {
                    print("âš ï¸ Engine failed to start, cannot play")
                }
            } catch {
                print("âš ï¸ Engine start error: \(error)")
            }
        } else {
            avPlayer?.play()
            avPlayer?.rate = playbackSpeed
        }
        isPlaying = true
        LockScreenManager.shared.update()
    }
    
    func pause() {
        saveCurrentPosition()
        if isUsingEngine {
            // Only pause if actually playing to avoid audio glitches
            if playerNode.isPlaying {
                playerNode.pause()
            }
            if engine.isRunning {
                engine.pause()
            }
        } else {
            avPlayer?.pause()
        }
        isPlaying = false
        LockScreenManager.shared.update()
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
    
    // MARK: - Seek (Chapter-Aware)
    // Time parameter is relative to chapter start for chaptered tracks
    func seek(to time: Double) {
        let absoluteTime: Double
        
        // For chapter tracks, convert relative time to absolute file time
        if let track = currentTrack, let startTime = track.startTime {
            absoluteTime = startTime + time
            
            // Clamp to chapter boundaries
            let effectiveEndTime = track.endTime ?? duration
            let clampedTime = max(startTime, min(absoluteTime, effectiveEndTime))
            
            if isUsingEngine {
                scheduleFileSegment(from: clampedTime, track: track)
                if isPlaying && engine.isRunning { playerNode.play() }
            } else {
                avPlayer?.seek(to: CMTimeMakeWithSeconds(clampedTime, preferredTimescale: 600))
            }
        } else {
            // Regular track - no conversion needed
            if isUsingEngine {
                scheduleFileSegment(from: time)
                if isPlaying && engine.isRunning { playerNode.play() }
            } else {
                avPlayer?.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: 600))
            }
        }
        
        LockScreenManager.shared.update()
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
    
    func clearQueue() { saveCurrentPosition(); stopCurrentPlayback(); queue.removeAll(); currentTrack = nil; currentIndex = 0; isPlaying = false; artwork = nil; clearSavedState(); LockScreenManager.shared.update() }
    
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
    
    deinit {
        periodicSaveTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        playerItemObserver?.invalidate()
        if let observer = timeObserver { avPlayer?.removeTimeObserver(observer) }
        if let observer = chapterEndObserver { avPlayer?.removeTimeObserver(observer) }
        engine.stop()
    }
}

// MARK: - Lock Screen & Remote Command Manager

class LockScreenManager {
    static let shared = LockScreenManager()
    
    weak var musicPlayer: AudioPlayer?
    weak var speechPlayer: AudioPlayer?
    
    // Track what was playing BEFORE the last pause
    // Only modified in pause/toggle handlers
    private var musicWasPlaying: Bool = false
    private var speechWasPlaying: Bool = false
    
    private init() {}
    
    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        
        // Clear to avoid duplicates
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        
        // Toggle (AirPods tap, lock screen play/pause)
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleGlobalToggle()
            return .success
        }
        
        // Explicit Play
        center.playCommand.addTarget { [weak self] _ in
            self?.handleResume()
            return .success
        }
        
        // Explicit Pause
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handlePause()
            return .success
        }
        
        // Next/Previous
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if let m = self.musicPlayer, m.isPlaying { m.next(); return .success }
            if let s = self.speechPlayer, s.isPlaying { s.next(); return .success }
            if self.musicWasPlaying, let m = self.musicPlayer, m.currentTrack != nil { m.next(); return .success }
            if self.speechWasPlaying, let s = self.speechPlayer, s.currentTrack != nil { s.next(); return .success }
            return .commandFailed
        }
        
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if let m = self.musicPlayer, m.isPlaying { m.previous(); return .success }
            if let s = self.speechPlayer, s.isPlaying { s.previous(); return .success }
            if self.musicWasPlaying, let m = self.musicPlayer, m.currentTrack != nil { m.previous(); return .success }
            if self.speechWasPlaying, let s = self.speechPlayer, s.currentTrack != nil { s.previous(); return .success }
            return .commandFailed
        }
    }
    
    /// Master Toggle: Pause all if any playing, Resume last active if none playing
    func handleGlobalToggle() {
        guard let music = musicPlayer, let speech = speechPlayer else { return }
        
        let musicPlaying = music.isPlaying
        let speechPlaying = speech.isPlaying
        
        if musicPlaying || speechPlaying {
            // PAUSE: Save what's currently playing, then pause
            musicWasPlaying = musicPlaying
            speechWasPlaying = speechPlaying
            
            if musicPlaying { music.pause() }
            if speechPlaying { speech.pause() }
        } else {
            // RESUME
            handleResume()
        }
    }
    
    /// Resume whatever was last playing
    private func handleResume() {
        guard let music = musicPlayer, let speech = speechPlayer else { return }
        
        let canResumeMusic = musicWasPlaying && music.currentTrack != nil
        let canResumeSpeech = speechWasPlaying && speech.currentTrack != nil
        
        if canResumeMusic || canResumeSpeech {
            // Resume what was playing before
            if canResumeMusic { music.play() }
            if canResumeSpeech { speech.play() }
        } else {
            // Fallback: Nothing tracked, play whatever is loaded
            // IMPORTANT: Use separate if statements so BOTH can play!
            if music.currentTrack != nil {
                musicWasPlaying = true
                music.play()
            }
            if speech.currentTrack != nil {
                speechWasPlaying = true
                speech.play()
            }
        }
    }
    
    /// Pause everything and save state
    private func handlePause() {
        guard let music = musicPlayer, let speech = speechPlayer else { return }
        
        // Save what's playing before we pause
        musicWasPlaying = music.isPlaying
        speechWasPlaying = speech.isPlaying
        
        music.pause()
        speech.pause()
    }
    
    /// Called when playback state changes - updates Now Playing display
    func update() {
        guard let music = musicPlayer, let speech = speechPlayer else { return }
        
        let musicPlaying = music.isPlaying
        let speechPlaying = speech.isPlaying
        let musicLoaded = music.currentTrack != nil
        let speechLoaded = speech.currentTrack != nil
        
        // Track when something STARTS playing (for in-app controls)
        // Only SET flags, never clear them - clearing happens implicitly when
        // handleGlobalToggle captures the current state before pausing
        if musicPlaying { musicWasPlaying = true }
        if speechPlaying { speechWasPlaying = true }
        
        // Build Now Playing info
        var info = [String: Any]()
        
        if musicPlaying && speechPlaying {
            // BOTH PLAYING: Combined display + App Logo
            info[MPMediaItemPropertyTitle] = "\(music.currentTrack?.title ?? "Music") + \(speech.currentTrack?.title ?? "Speech")"
            info[MPMediaItemPropertyArtist] = "\(music.currentTrack?.artist ?? "") + \(speech.currentTrack?.artist ?? "")"
            setAppLogoArtwork(&info)
            
        } else if musicPlaying {
            // ONLY MUSIC PLAYING
            info[MPMediaItemPropertyTitle] = music.currentTrack?.title ?? "Music"
            info[MPMediaItemPropertyArtist] = music.currentTrack?.artist ?? ""
            if let art = music.artwork {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
            } else {
                setAppLogoArtwork(&info) // Fallback for radio/uploads without art
            }
            
        } else if speechPlaying {
            // ONLY SPEECH PLAYING
            info[MPMediaItemPropertyTitle] = speech.currentTrack?.title ?? "Speech"
            info[MPMediaItemPropertyArtist] = speech.currentTrack?.artist ?? ""
            if let art = speech.artwork {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
            } else {
                setAppLogoArtwork(&info) // Fallback for audiobooks without art
            }
            
        } else {
            // PAUSED - Show what was last playing
            let bothWerePlaying = musicWasPlaying && speechWasPlaying && musicLoaded && speechLoaded
            
            if bothWerePlaying {
                info[MPMediaItemPropertyTitle] = "\(music.currentTrack?.title ?? "Music") + \(speech.currentTrack?.title ?? "Speech")"
                info[MPMediaItemPropertyArtist] = "Paused"
                setAppLogoArtwork(&info)
                
            } else if musicWasPlaying && musicLoaded {
                info[MPMediaItemPropertyTitle] = music.currentTrack?.title ?? "Music"
                info[MPMediaItemPropertyArtist] = music.currentTrack?.artist ?? "Paused"
                if let art = music.artwork {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
                } else {
                    setAppLogoArtwork(&info)
                }
                
            } else if speechWasPlaying && speechLoaded {
                info[MPMediaItemPropertyTitle] = speech.currentTrack?.title ?? "Speech"
                info[MPMediaItemPropertyArtist] = speech.currentTrack?.artist ?? "Paused"
                if let art = speech.artwork {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
                } else {
                    setAppLogoArtwork(&info)
                }
                
            } else if musicLoaded {
                info[MPMediaItemPropertyTitle] = music.currentTrack?.title ?? "Music"
                info[MPMediaItemPropertyArtist] = music.currentTrack?.artist ?? ""
                if let art = music.artwork {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
                } else {
                    setAppLogoArtwork(&info)
                }
                
            } else if speechLoaded {
                info[MPMediaItemPropertyTitle] = speech.currentTrack?.title ?? "Speech"
                info[MPMediaItemPropertyArtist] = speech.currentTrack?.artist ?? ""
                if let art = speech.artwork {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
                } else {
                    setAppLogoArtwork(&info)
                }
                
            } else {
                info[MPMediaItemPropertyTitle] = "2 Music 2 Furious"
                info[MPMediaItemPropertyArtist] = "Ready to Play"
                setAppLogoArtwork(&info)
            }
        }
        
        // Time/Duration from appropriate player
        let primaryPlayer: AudioPlayer
        if musicPlaying {
            primaryPlayer = music
        } else if speechPlaying {
            primaryPlayer = speech
        } else if musicWasPlaying && musicLoaded {
            primaryPlayer = music
        } else if speechWasPlaying && speechLoaded {
            primaryPlayer = speech
        } else if musicLoaded {
            primaryPlayer = music
        } else {
            primaryPlayer = speech
        }
        
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = primaryPlayer.currentTime
        info[MPMediaItemPropertyPlaybackDuration] = primaryPlayer.duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = primaryPlayer.isPlaying ? Double(primaryPlayer.playbackSpeed) : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    /// Helper to set app logo artwork with fallback
    private func setAppLogoArtwork(_ info: inout [String: Any]) {
        // Try different possible asset names
        let possibleNames = ["AppLogo", "AppIcon", "logo", "Logo", "app_logo"]
        
        for name in possibleNames {
            if let image = UIImage(named: name) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                return
            }
        }
        
        // Final fallback: Create a simple purple gradient image
        let size = CGSize(width: 300, height: 300)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        if let context = UIGraphicsGetCurrentContext() {
            let colors = [
                UIColor(red: 0.9, green: 0.2, blue: 0.6, alpha: 1.0).cgColor,
                UIColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 1.0).cgColor
            ]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            
            // Draw "2â™ª" text
            let text = "2â™ª"
            let font = UIFont.systemFont(ofSize: 120, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
        if let fallbackImage = UIGraphicsGetImageFromCurrentImageContext() {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: fallbackImage.size) { _ in fallbackImage }
        }
        UIGraphicsEndImageContext()
    }
}

// MARK: - Audio Interruption Manager (Message Announcements)

/// Handles system audio interruptions (Siri, message announcements, phone calls)
/// Pauses speech and ducks music when system needs to speak
class InterruptionManager {
    static let shared = InterruptionManager()
    
    weak var musicPlayer: AudioPlayer?
    weak var speechPlayer: AudioPlayer?
    
    // Track what was playing before interruption
    private var musicWasPlaying = false
    private var speechWasPlaying = false
    private var originalMusicDucking = false
    private var isCurrentlyInterrupted = false
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Use object: nil to catch notifications from any source
        // This is important for Siri announcements which may not come from our session
        
        // Standard interruption (phone calls, alarms, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil  // Changed from session to nil
        )
        
        // Secondary audio hint (Siri announcements, other apps' audio)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSecondaryAudio),
            name: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: nil  // Changed from session to nil
        )
        
        // Route changes (headphones unplugged, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil  // Changed from session to nil
        )
        
        print("ðŸŽ™ Audio interruption observers registered")
    }
    
    // MARK: - Standard Interruption (Phone Calls, Alarms)
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        print("ðŸ“± Interruption notification: \(type == .began ? "BEGAN" : "ENDED")")
        
        switch type {
        case .began:
            handleInterruptionBegan(reason: "interruption")
            
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    handleInterruptionEnded()
                }
            } else {
                handleInterruptionEnded()
            }
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Secondary Audio Hint (Siri Announcements)
    
    @objc private func handleSecondaryAudio(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue) else {
            return
        }
        
        print("ðŸ“ˆ Secondary audio hint: \(type == .begin ? "BEGIN" : "END")")
        
        switch type {
        case .begin:
            // Another app (Siri) is playing audio
            handleInterruptionBegan(reason: "siri")
            
        case .end:
            // Other app's audio ended
            handleInterruptionEnded()
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Route Change (Headphones Unplugged)
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // Pause when headphones are unplugged (standard behavior)
        if reason == .oldDeviceUnavailable {
            print("ðŸŽ§ Headphones unplugged - pausing")
            DispatchQueue.main.async {
                self.musicPlayer?.pause()
                self.speechPlayer?.pause()
            }
        }
    }
    
    // MARK: - Shared Handlers
    
    private func handleInterruptionBegan(reason: String) {
        guard !isCurrentlyInterrupted else { return } // Prevent double-handling
        isCurrentlyInterrupted = true
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let music = self.musicPlayer,
                  let speech = self.speechPlayer else { return }
            
            // Save state BEFORE pausing
            self.musicWasPlaying = music.isPlaying
            self.speechWasPlaying = speech.isPlaying
            self.originalMusicDucking = music.isDucking
            
            print("â¸ï¸ \(reason) began - music was: \(self.musicWasPlaying), speech was: \(self.speechWasPlaying)")
            
            // Pause speech
            if speech.isPlaying {
                speech.pause()
            }
            
            // Pause music (system may do this anyway, but be explicit)
            if music.isPlaying {
                music.pause()
            }
        }
    }
    
    private func handleInterruptionEnded() {
        guard isCurrentlyInterrupted else { return } // Only handle if we started an interruption
        isCurrentlyInterrupted = false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let music = self.musicPlayer,
                  let speech = self.speechPlayer else { return }
            
            print("â–¶ï¸ Interruption ended - resuming music: \(self.musicWasPlaying), speech: \(self.speechWasPlaying)")
            
            // Restore music ducking state
            music.isDucking = self.originalMusicDucking
            
            // Small delay to let system audio fully finish
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Resume music if it was playing
                if self.musicWasPlaying {
                    music.play()
                }
                
                // Resume speech if it was playing
                if self.speechWasPlaying {
                    speech.play()
                }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
