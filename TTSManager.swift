//
//  TTSManager.swift
//  2 Music 2 Furious
//
//  Text-to-Speech manager using AVSpeechSynthesizer
//  Provides word-by-word callbacks for highlighting
//  Chunks long text to ensure reliable word callbacks
//

import Foundation
import AVFoundation
import Combine

class TTSManager: NSObject, ObservableObject {
    static let shared = TTSManager()

    // MARK: - Published Properties

    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentWordRange: NSRange = NSRange(location: NSNotFound, length: 0)
    @Published var progress: Double = 0  // 0.0 to 1.0
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            // Speed changes require restarting from current position
            if isPlaying {
                let currentPos = currentCharacterPosition
                stop()
                speak(from: currentPos)
            }
        }
    }

    // Voice settings
    @Published var selectedVoiceIdentifier: String? = nil

    // MARK: - Current State

    private(set) var currentText: String = ""
    private(set) var currentCharacterPosition: Int = 0

    // Chunking support - break long text into smaller pieces for reliable callbacks
    private var chunks: [(text: String, startPosition: Int)] = []
    private var currentChunkIndex: Int = 0
    private var chunkStartPosition: Int = 0  // Global position where current chunk starts
    private var shouldContinueChunks = false  // Flag to prevent auto-advance after stop
    private var utteranceGeneration: Int = 0  // Track which utterance is current to ignore stale callbacks

    // Callbacks
    var onWordSpoken: ((NSRange) -> Void)?
    var onFinished: (() -> Void)?
    var onChapterFinished: (() -> Void)?

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?

    // Maximum characters per chunk (keep small for reliable callbacks)
    private let maxChunkSize = 1000

    // MARK: - Available Voices

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    static var defaultVoice: AVSpeechSynthesisVoice? {
        // Prefer enhanced/premium voices
        let voices = availableVoices
        return voices.first { $0.quality == .enhanced }
            ?? voices.first { $0.quality == .default }
            ?? voices.first
    }

    // MARK: - Initialization

    override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("TTSManager: Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Public API

    /// Load text for speaking
    func loadText(_ text: String) {
        stop()
        currentText = text
        currentCharacterPosition = 0
        progress = 0
        chunks = []
        currentChunkIndex = 0

        // Pre-chunk the text
        buildChunks(from: 0)
    }

    /// Start speaking from the beginning or current position
    func play() {
        if isPaused {
            resume()
        } else {
            speak(from: currentCharacterPosition)
        }
    }

    /// Pause speaking
    func pause() {
        if synthesizer.isSpeaking {
            shouldContinueChunks = false  // Prevent auto-advance to next chunk
            synthesizer.pauseSpeaking(at: .immediate)
            isPaused = true
            isPlaying = false
        }
    }

    /// Resume speaking after pause
    func resume() {
        if isPaused {
            shouldContinueChunks = true  // Allow auto-advance again
            synthesizer.continueSpeaking()
            isPaused = false
            isPlaying = true
        }
    }

    /// Stop speaking completely
    func stop() {
        shouldContinueChunks = false  // Prevent auto-advance to next chunk
        utteranceGeneration += 1  // Invalidate any pending callbacks from old utterances
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
    }

    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Seek to a specific character position
    func seek(to characterPosition: Int) {
        let nsLength = (currentText as NSString).length
        let wasPlaying = isPlaying || isPaused
        stop()
        currentCharacterPosition = max(0, min(characterPosition, nsLength))
        updateProgress()

        // Rebuild chunks from new position
        buildChunks(from: currentCharacterPosition)

        if wasPlaying {
            speak(from: currentCharacterPosition)
        }
    }

    /// Seek to position and always start playing (for tap-to-seek)
    func seekAndPlay(to characterPosition: Int) {
        let nsLength = (currentText as NSString).length
        let targetPosition = max(0, min(characterPosition, nsLength))

        // Stop any current speech and clean up
        shouldContinueChunks = false
        utteranceGeneration += 1
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false

        // Start immediately from new position
        currentCharacterPosition = targetPosition
        updateProgress()
        buildChunks(from: currentCharacterPosition)
        speak(from: currentCharacterPosition)
    }

    /// Seek to a percentage (0.0 to 1.0)
    func seekToPercent(_ percent: Double) {
        let nsLength = (currentText as NSString).length
        let position = Int(Double(nsLength) * percent)
        seek(to: position)
    }

    /// Skip forward by approximate word count
    func skipForward(words: Int = 10) {
        let newPosition = findWordBoundary(from: currentCharacterPosition, direction: .forward, count: words)
        seek(to: newPosition)
    }

    /// Skip backward by approximate word count
    func skipBackward(words: Int = 10) {
        let newPosition = findWordBoundary(from: currentCharacterPosition, direction: .backward, count: words)
        seek(to: newPosition)
    }

    /// Cycle through speed options
    func cycleSpeed() {
        let speeds: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0]
        if let currentIndex = speeds.firstIndex(of: playbackSpeed) {
            let nextIndex = (currentIndex + 1) % speeds.count
            playbackSpeed = speeds[nextIndex]
        } else {
            playbackSpeed = 1.0
        }
    }

    // MARK: - Chunking

    /// Build chunks starting from a given position
    private func buildChunks(from startPosition: Int) {
        chunks = []
        currentChunkIndex = 0

        let nsText = currentText as NSString
        let totalLength = nsText.length

        guard startPosition < totalLength else { return }

        var position = startPosition

        while position < totalLength {
            // Find a good break point (end of sentence or paragraph)
            var endPosition = min(position + maxChunkSize, totalLength)

            if endPosition < totalLength {
                // Look for paragraph break first
                let searchRange = NSRange(location: position, length: endPosition - position)
                let paragraphRange = nsText.range(of: "\n\n", options: .backwards, range: searchRange)

                if paragraphRange.location != NSNotFound && paragraphRange.location > position + 200 {
                    endPosition = paragraphRange.location + paragraphRange.length
                } else {
                    // Look for sentence break
                    let sentenceBreaks = [". ", "! ", "? ", ".\n", "!\n", "?\n"]
                    var bestBreak = NSNotFound

                    for breakStr in sentenceBreaks {
                        let range = nsText.range(of: breakStr, options: .backwards, range: searchRange)
                        if range.location != NSNotFound && range.location > position + 200 {
                            if bestBreak == NSNotFound || range.location > bestBreak {
                                bestBreak = range.location + range.length
                            }
                        }
                    }

                    if bestBreak != NSNotFound {
                        endPosition = bestBreak
                    } else {
                        // Fall back to word boundary
                        while endPosition > position + 200 && endPosition < totalLength {
                            let char = nsText.character(at: endPosition)
                            if CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(char)!) {
                                endPosition += 1
                                break
                            }
                            endPosition -= 1
                        }
                    }
                }
            }

            let chunkText = nsText.substring(with: NSRange(location: position, length: endPosition - position))
            chunks.append((text: chunkText, startPosition: position))
            position = endPosition
        }
    }

    // MARK: - Speaking

    private func speak(from position: Int) {
        guard !currentText.isEmpty else { return }

        // Rebuild chunks if needed
        if chunks.isEmpty || position != chunks.first?.startPosition {
            buildChunks(from: position)
        }

        guard !chunks.isEmpty else {
            onChapterFinished?()
            return
        }

        currentChunkIndex = 0
        speakCurrentChunk()
    }

    private func speakCurrentChunk() {
        guard currentChunkIndex < chunks.count else {
            // All chunks done
            DispatchQueue.main.async {
                self.isPlaying = false
                self.isPaused = false
                self.onChapterFinished?()
            }
            return
        }

        let chunk = chunks[currentChunkIndex]
        chunkStartPosition = chunk.startPosition
        currentCharacterPosition = chunk.startPosition

        // Set initial highlight to start of chunk (will be updated by callback)
        currentWordRange = NSRange(location: chunk.startPosition, length: 1)
        shouldContinueChunks = true  // Allow auto-advance to next chunk
        utteranceGeneration += 1  // New generation for this utterance

        // Create utterance for this chunk
        let newUtterance = AVSpeechUtterance(string: chunk.text)

        // Set voice
        if let voiceId = selectedVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            newUtterance.voice = voice
        } else if let defaultVoice = TTSManager.defaultVoice {
            newUtterance.voice = defaultVoice
        }

        // Set rate
        newUtterance.rate = mapSpeedToRate(playbackSpeed)
        newUtterance.pitchMultiplier = 1.0
        newUtterance.volume = 1.0

        utterance = newUtterance
        isPlaying = true
        isPaused = false

        synthesizer.speak(newUtterance)
    }

    private func mapSpeedToRate(_ speed: Float) -> Float {
        // AVSpeechUtterance rate: 0.0 (slowest) to 1.0 (fastest), 0.5 is default
        // Our speed: 1.0 (normal) to 2.0 (fast)
        // Map 1.0 -> 0.5, 2.0 -> 0.65 (not too fast to be unintelligible)
        let minRate: Float = 0.5
        let maxRate: Float = 0.65
        let normalizedSpeed = (speed - 1.0) / 1.0  // 0.0 to 1.0
        return minRate + (normalizedSpeed * (maxRate - minRate))
    }

    private func updateProgress() {
        let nsLength = (currentText as NSString).length
        guard nsLength > 0 else {
            progress = 0
            return
        }
        progress = Double(currentCharacterPosition) / Double(nsLength)
    }

    private enum Direction {
        case forward, backward
    }

    private func findWordBoundary(from position: Int, direction: Direction, count: Int) -> Int {
        let text = currentText as NSString
        var currentPos = position
        var wordsFound = 0

        switch direction {
        case .forward:
            while currentPos < text.length && wordsFound < count {
                // Skip current word
                while currentPos < text.length && !text.character(at: currentPos).isWhitespace {
                    currentPos += 1
                }
                // Skip whitespace
                while currentPos < text.length && text.character(at: currentPos).isWhitespace {
                    currentPos += 1
                }
                wordsFound += 1
            }
        case .backward:
            while currentPos > 0 && wordsFound < count {
                // Skip whitespace
                while currentPos > 0 && text.character(at: currentPos - 1).isWhitespace {
                    currentPos -= 1
                }
                // Skip word
                while currentPos > 0 && !text.character(at: currentPos - 1).isWhitespace {
                    currentPos -= 1
                }
                wordsFound += 1
            }
        }

        return currentPos
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSManager: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let generationAtStart = self.utteranceGeneration
        DispatchQueue.main.async {
            guard generationAtStart == self.utteranceGeneration else { return }
            self.isPlaying = true
            self.isPaused = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        // Don't check generation - pause is always intentional and current
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = true
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        // Don't check generation - continue is always intentional and current
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Capture generation to check if this callback is still relevant
        let generationAtFinish = self.utteranceGeneration

        DispatchQueue.main.async {
            // Ignore if generation changed (we've started a new utterance)
            guard generationAtFinish == self.utteranceGeneration else {
                return
            }

            // Only continue if not stopped/paused
            guard self.shouldContinueChunks else {
                return
            }

            // Move to next chunk
            self.currentChunkIndex += 1

            if self.currentChunkIndex < self.chunks.count {
                // More chunks to speak
                self.speakCurrentChunk()
            } else {
                // All done
                self.isPlaying = false
                self.isPaused = false
                self.shouldContinueChunks = false
                self.onChapterFinished?()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Don't modify state here - the caller (stop/seekAndPlay) handles state synchronously
        // This prevents async callback from overriding state set by new utterances
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        // Capture generation and chunk position to check if this callback is still relevant
        let generationAtCallback = self.utteranceGeneration
        let chunkStart = self.chunkStartPosition

        DispatchQueue.main.async {
            // Ignore if generation changed (we've started a new utterance)
            guard generationAtCallback == self.utteranceGeneration else {
                return
            }

            // Adjust range to account for chunk's position in full text
            let adjustedRange = NSRange(
                location: chunkStart + characterRange.location,
                length: characterRange.length
            )

            self.currentWordRange = adjustedRange
            self.currentCharacterPosition = adjustedRange.location
            self.updateProgress()
            self.onWordSpoken?(adjustedRange)
        }
    }
}

// MARK: - Helper Extension

private extension unichar {
    var isWhitespace: Bool {
        CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(self)!)
    }
}
