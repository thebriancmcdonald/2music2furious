# 2 Music 2 Furious: Technical Specification

---

# â›” STOP â€” READ BEFORE WRITING ANY CODE â›”

This app has **dual audio players** (music + speech) that play simultaneously. The lock screen, AirPods, and interruption handling are fragile and interconnected. Changes that seem safe can break background playback, resume behavior, or cause crashes.

**ðŸ”„ AFTER CONTEXT COMPACTION:** Re-read this entire document. Compaction loses details.

---

## SUMMARY: THE RULES

> ⚠️ **THIS SUMMARY STAYS AT THE TOP.** Don't move it to the bottom—Claude needs to see this first, not last.

1. **Read this entire document after context compaction**
2. **Read the "7 things" before touching any playback code**
3. **Follow the patterns exactly** when adding new features
4. **Don't modify working code** unless fixing a specific bug
5. **When in doubt, ask** — especially for lock screen / audio session / interruptions
6. **Test the checklist** after every change
7. **Simple is better** — the boolean flags in LockScreenManager work; don't add complexity
8. **Don't reinvent wheels** — use SwiftSoup for HTML parsing, Readability.js for article extraction

If something seems like it needs a change to the core audio system, **tell the user and discuss options** rather than making the change directly.

---

## THE 7 THINGS THAT WILL BREAK THE APP

### 1. LockScreenManager.update() â€” THE MOST FRAGILE CODE

**Location:** `AudioPlayer.swift`, class `LockScreenManager`

This method determines what shows on the lock screen and Control Center. It uses `musicWasPlaying` and `speechWasPlaying` boolean flags to track state across pause/resume cycles. The logic handles 7+ different combinations of "what's playing" and "what was playing."

```
ðŸ”´ DO NOT MODIFY the state-to-display mapping logic
ðŸ”´ DO NOT MODIFY the "bothWerePlaying" detection logic
ðŸ”´ DO NOT CHANGE the order of if/else conditions
ðŸ”´ DO NOT add new state tracking variables (the existing flags work)
```

**If you think you need to change it:** STOP. Tell the user. Discuss alternatives.

**Recent lesson learned:** Adding a `lastActivePlayer` string variable to "improve" pause state tracking broke the entire lock screen display. The original boolean flags (`musicWasPlaying`, `speechWasPlaying`) are simple and correct. Don't overcomplicate.

---

### 2. AudioPlayer @Published didSet Triggers

**Location:** `AudioPlayer.swift`, lines ~33-90

These trigger `LockScreenManager.shared.update()` automatically:

```swift
@Published var isPlaying       // triggers update()
@Published var currentTrack    // triggers update()
@Published var artwork         // triggers update()
@Published var playbackSpeed   // triggers update()
```

```
ðŸ”´ DO NOT REMOVE these didSet triggers
ðŸ”´ DO NOT ADD async operations inside didSet
ðŸ”´ DO NOT CHANGE what triggers updates
```

---

### 3. InterruptionManager Observer Setup

**Location:** `AudioPlayer.swift`, class `InterruptionManager`

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleInterruption),
    name: AVAudioSession.interruptionNotification,
    object: nil  // â† MUST BE nil, NOT session
)
```

```
ðŸ”´ object: nil is REQUIRED to catch Siri announcements
ðŸ”´ DO NOT "fix" this to use AVAudioSession.sharedInstance()
```

---

### 4. Initialization Order in ContentView.onAppear

**Location:** `ContentView.swift`, lines ~97-116

This order is required:
1. `setupAudioSession()` â€” configures audio category
2. Wire `LockScreenManager.shared` to both players
3. Call `setupRemoteCommands()`
4. Wire `InterruptionManager.shared` to both players
5. Restore saved state

```
ðŸ”´ DO NOT reorder these operations
ðŸ”´ DO NOT move player wiring to a later point
ðŸ”´ DO NOT make wiring conditional
```

---

### 5. AudioPlayer Safety Guards

**Location:** `AudioPlayer.swift`, scattered

These prevent crashes with corrupted files and edge cases:

```swift
// In duration/currentTime:
guard result.isFinite && result >= 0 else { return 0 }

// In scheduleFileSegment:
let remainingFrames = AVAudioFrameCount(min(remainingFramesInt64, Int64(UInt32.max)))

// In play():
if engine.isRunning { playerNode.play() }  // Guard against "player did not see an IO cycle"
```

```
ðŸ”´ DO NOT REMOVE these guards
ðŸ”´ DO NOT simplify "for performance"
```

---

### 6. Chapter End Detection (playbackGeneration counter)

**Location:** `AudioPlayer.swift`, `scheduleFileSegment()`

M4B audiobooks use virtual chapters (same file, different time ranges). The `scheduleSegment` completion handler fires when audio finishes, but ALSO fires when you manually stop/seek. The `playbackGeneration` counter prevents cascade bugs:

```swift
private var playbackGeneration: Int = 0

private func scheduleFileSegment(from startTime: Double, track: Track? = nil) {
    playbackGeneration += 1  // Increment on every schedule
    let capturedGeneration = playbackGeneration
    
    playerNode.scheduleSegment(...) { [weak self] in
        // Only advance chapter if generation matches (not interrupted by seek/stop)
        guard self?.playbackGeneration == capturedGeneration else { return }
        self?.handleChapterEnd()
    }
}
```

```
ðŸ”´ DO NOT REMOVE the generation counter
ðŸ”´ DO NOT simplify to a boolean flag (timing issues)
```

---

### 7. Startup Auto-Play Suppression (isRestoringState flag)

**Location:** `AudioPlayer.swift`, `restoreState()` and `setupAVPlayer()`

The app restores saved playback state on launch but must NOT auto-play. HTTP streams and chapter files normally auto-play when ready, but this must be suppressed during state restoration.

```swift
private var isRestoringState = false

func restoreState(...) {
    isRestoringState = true  // Set BEFORE loading track
    // ... load track ...
    // Flag is cleared inside setupAVPlayer/loadLocalFile AFTER the auto-play check
}

private func setupAVPlayer(...) {
    playerItemObserver = item.observe(\.status) { ... 
        if item.status == .readyToPlay {
            let shouldAutoPlay = !self.isRestoringState && (isHTTP || isLocalChapter)
            self.isRestoringState = false  // Clear AFTER check
            if shouldAutoPlay { self.play() }
        }
    }
}
```

**Critical:** The flag is cleared **inside the observer callback**, not on a timer. HTTP streams can take seconds to buffer—a timer-based approach will fail.

```
🔴 DO NOT clear isRestoringState on a timer
🔴 DO NOT move the flag clearing before the auto-play check
🔴 DO NOT remove the flag from the AVAudioEngine path in loadLocalFile()
```

---

## ARTICLE EXTRACTION SYSTEM

### Architecture Overview

Articles use a **two-stage extraction pipeline**:

1. **Readability.js** (via WKWebView) â€” Extracts clean article HTML from messy web pages
2. **SwiftSoup** â€” Parses clean HTML into plain text + formatting spans

This produces **TTS-synced rich text**: the plain text goes to TTSManager, formatting spans overlay visual styling without changing character indices.

### Dependencies

```
SwiftSoup - Swift Package (https://github.com/scinfu/SwiftSoup)
Readability.js - Bundle resource (from https://github.com/mozilla/readability)
```

### Key Files

| File | Purpose |
|------|---------|
| `ArticleExtractor.swift` | WKWebView + Readability.js extraction, SwiftSoup parsing |
| `ArticleManager.swift` | Article/ArticleChapter models, FormattingSpan, persistence |
| `ArticleReaderView.swift` | Rich text display with TTS highlighting |
| `DocumentImporter.swift` | Local file imports (ePub, PDF, HTML, TXT) |

### Data Models

```swift
struct FormattingSpan: Codable {
    let location: Int      // Character index in plain text
    let length: Int
    let style: FormattingStyle  // .bold, .italic, .link, .header1, etc.
    let url: String?       // For links only
}

struct ArticleChapter: Codable {
    let id: UUID
    var title: String
    var content: String                    // Plain text (TTS uses this)
    var formattingSpans: [FormattingSpan]? // Visual formatting overlay
}
```

### Critical: Index Alignment

```
ðŸ”´ FormattingSpan indices are CHARACTER positions in content string
ðŸ”´ When applying to NSAttributedString, convert properly:
   let startIdx = content.index(content.startIndex, offsetBy: span.location)
   let endIdx = content.index(startIdx, offsetBy: span.length)
   let range = NSRange(startIdx..<endIdx, in: content)
ðŸ”´ DO NOT use span.location directly as NSRange â€” UTF-16 vs Character mismatch
ðŸ”´ DO NOT modify content after spans are created â€” indices will be wrong
```

### Extraction Flow

```
URL â†’ WKWebView loads page
    â†’ Readability.js extracts article HTML
    â†’ SwiftSoup parses HTML
    â†’ processNode() walks DOM, builds:
        - plainText (appending text content)
        - spans (tracking tag positions)
    â†’ Article saved with content + formattingSpans
```

```
ðŸ”´ DO NOT try to "clean" content after extraction â€” breaks span alignment
ðŸ”´ DO NOT write custom regex HTML parsers â€” use SwiftSoup
ðŸ”´ DO NOT skip Readability.js for web URLs â€” raw HTML has nav/ads/junk
```

---

## BEFORE YOU CODE: DECISION TREE

### What are you trying to do?

```
Adding NEW CONTENT SOURCE (new API, new file type)?
  â†’ See: PATTERN A below
  â†’ Safe: Create new manager, new view
  â†’ Safe: Wire to existing AudioPlayer
  â†’ DANGER: Don't modify AudioPlayer.loadTrack()

Adding UI to EXISTING VIEW?
  â†’ Safe: Add buttons, lists, styling
  â†’ Safe: Add new sheets/navigation
  â†’ DANGER: Don't add playback logic in views

Adding PLAYBACK FEATURE (speed, effects, queue)?
  â†’ Check: Does it need lock screen display? â†’ Talk to user first
  â†’ Safe: Add to AudioPlayer methods
  â†’ DANGER: Don't modify @Published didSet triggers

Adding PERSISTENCE (new data to save)?
  â†’ See: PATTERN B below  
  â†’ Safe: New UserDefaults keys
  â†’ DANGER: Don't change existing key names

Fixing a BUG?
  â†’ Check: Is it in the "7 things" above? â†’ Talk to user first
  â†’ Safe: Add guards, nil checks, fallbacks
  â†’ DANGER: Don't "simplify" working code

Touching LOCK SCREEN behavior?
  â†’ ðŸ›‘ STOP. Tell the user. This is the #1 regression source.

Modifying ARTICLE EXTRACTION?
  â†’ Safe: Add new FormattingStyle cases
  â†’ Safe: Improve SwiftSoup node handling
  â†’ DANGER: Don't modify content string after spans created
  â†’ DANGER: Don't skip Readability.js for web content
```

---

## AUDIO MODE: QUALITY vs BOOST

**Location:** `AudioPlayer.swift`, `audioMode` property

The speech player has a toggle between two audio engines:

| Mode | Engine | Speed Quality | Voice Boost | Use Case |
|------|--------|---------------|-------------|----------|
| **Quality** | AVPlayer | Excellent (Apple's algorithm) | âŒ Not available | Default. Sounds natural at 1.5x+ |
| **Boost** | AVAudioEngine | Robotic at high speeds | âœ… Works | Quiet audiobooks, noisy environments |

```swift
enum AudioMode: String, CaseIterable {
    case quality = "Quality"
    case boost = "Boost"
}

@Published var audioMode: AudioMode = .quality {
    didSet {
        // Automatically enables/disables boost
        isBoostEnabled = (audioMode == .boost)
        // Reloads current track with new engine
        // Persists to UserDefaults
    }
}
```

**UI:** Segmented toggle in ContentView speech panel header: `[Quality | Boost]`

```
ðŸ”´ DO NOT remove the mode toggle without discussing
ðŸ”´ DO NOT force one engine for all content types
```

---

## ENGINE SELECTION (AudioPlayer)

Engine selection depends on **content type** AND **audio mode**:

| Content Type | Quality Mode | Boost Mode |
|--------------|--------------|------------|
| `ipod-library://...` | AVPlayer | AVPlayer (Apple requires it) |
| `http://...` streams | AVPlayer | AVPlayer (streaming needs buffering) |
| Local files (.mp3, .m4b, etc.) | AVPlayer | AVAudioEngine |

**Location:** `AudioPlayer.swift`, `loadLocalFile()`

```swift
private func loadLocalFile(track: Track) {
    if audioMode == .quality {
        // Use AVPlayer for better speed algorithm
        isUsingEngine = false
        setupAVPlayer(with: AVPlayerItem(asset: asset), track: track)
    } else {
        // Use AVAudioEngine for boost capability
        isUsingEngine = true
        // ... engine setup ...
    }
}
```

```
ðŸ”´ DO NOT modify this logic without understanding both paths
ðŸ”´ DO NOT remove the audioMode check
```

---

## M4B AUDIOBOOK SUPPORT

### Virtual Chapters

M4B files are single audio files with embedded chapter markers. Each "chapter" is a Track with:

```swift
struct Track {
    let id: UUID
    let title: String
    let artist: String
    let filename: String      // Same file for all chapters
    let startTime: Double?    // Chapter start in seconds
    let endTime: Double?      // Chapter end in seconds
    
    var hasChapterBoundaries: Bool {
        startTime != nil && endTime != nil
    }
}
```

---

## PATTERN A: Adding New Content Source

### 1. Create a new Manager (singleton or @StateObject)

```swift
class MyNewManager: ObservableObject {
    static let shared = MyNewManager()  // If singleton
    @Published var items: [MyItem] = []
    // ... fetch, parse, persist ...
}
```

### 2. Create a new View

```swift
struct MyNewSearchView: View {
    @StateObject private var manager = MyNewManager()
    // OR for singleton:
    @ObservedObject private var manager = MyNewManager.shared
}
```

### 3. Wire playback to existing AudioPlayer

```swift
// In your view, receive the player from ContentView
let speechPlayer: AudioPlayer  // passed in

// Load a track
let track = Track(id: UUID(), title: "...", artist: "...", filename: localPath)
speechPlayer.loadTrack(track)
speechPlayer.play()
```

---

## PATTERN B: Adding New Persisted Data

### 1. Choose a unique key

```swift
private let myDataKey = "myFeature_dataName"  // Namespaced to avoid collision
```

### 2. Use standard encode/decode

```swift
func saveData() {
    if let encoded = try? JSONEncoder().encode(myData) {
        UserDefaults.standard.set(encoded, forKey: myDataKey)
    }
}

func loadData() {
    if let data = UserDefaults.standard.data(forKey: myDataKey),
       let decoded = try? JSONDecoder().decode(MyType.self, from: data) {
        myData = decoded
    }
}
```

### 3. Load lazily, save immediately

```swift
func loadIfNeeded() {
    guard !isLoaded else { return }
    loadData()
    isLoaded = true
}

// Call saveData() immediately after any mutation
```

---

## PATTERN C: Adding to Existing Manager

If you're adding a feature to BookManager, PodcastSearchManager, etc.:

### 1. Add @Published property if UI needs to react

```swift
@Published var newFeatureData: [String] = []
```

### 2. Add persistence in init or loadIfNeeded

```swift
func loadIfNeeded() {
    guard !isLoaded else { return }
    loadExistingStuff()
    loadNewFeatureData()  // â† Add here
    isLoaded = true
}
```

### 3. Add save method, call after mutations

```swift
func updateNewFeature(_ value: String) {
    newFeatureData.append(value)
    saveNewFeatureData()  // â† Immediate save
}
```

---

## EXISTING MANAGERS QUICK REFERENCE

| Manager | Type | Plays On | Key Responsibility |
|---------|------|----------|-------------------|
| `AudioPlayer` | @StateObject (x2) | - | Actual playback engine |
| `MusicLibraryManager` | @StateObject | musicPlayer | Apple Music library access |
| `BookManager.shared` | Singleton | speechPlayer | Audiobooks (LibriVox + M4B uploads) |
| `PodcastSearchManager` | @StateObject | speechPlayer | iTunes podcast search + RSS |
| `DownloadManager.shared` | Singleton | - | Podcast episode downloads |
| `ArticleManager.shared` | Singleton | TTSManager | Web articles + documents |
| `ArticleExtractor` | Static methods | - | Web article extraction (Readability + SwiftSoup) |
| `RadioBrowserAPI` | @StateObject | musicPlayer | Radio station search |
| `TTSManager.shared` | Singleton | - | Text-to-speech for articles |
| `ImageCache.shared` | Singleton | - | Artwork caching |

---

## AUDIO SESSION CONFIGURATION

**Location:** `ContentView.swift`, `setupAudioSession()`

```swift
try session.setCategory(.playback, mode: .spokenAudio, 
    options: [.allowBluetooth, .allowBluetoothA2DP])
try session.setActive(true, options: .notifyOthersOnDeactivation)
```

```
ðŸ”´ DO NOT change .playback category (breaks background audio)
ðŸ”´ DO NOT remove Bluetooth options (breaks AirPods)
ðŸ”´ DO NOT remove .notifyOthersOnDeactivation (breaks other apps)
```

---

## DATA MODELS

### Track (used everywhere)

```swift
struct Track: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let artist: String
    let filename: String      // Local filename, ipod-library://, or http(s)://
    let startTime: Double?    // For M4B chapters: start time in seconds
    let endTime: Double?      // For M4B chapters: end time in seconds
    
    var hasChapterBoundaries: Bool {
        startTime != nil && endTime != nil
    }
}
```

### Book

```swift
struct Book {
    var id: UUID
    let title: String
    var author: String?
    var chapters: [Track]              // Downloaded chapters OR M4B virtual chapters
    var librivoxChapters: [LibriVoxChapter]?  // All available (LibriVox only)
    var coverArtUrl: URL?
    var currentChapterIndex: Int
    var lastPlayedPosition: Double
    let dateAdded: Date
}
```

### Article

```swift
struct Article {
    let id: UUID
    var title: String
    var source: String
    var sourceURL: URL?
    var author: String?
    var chapters: [ArticleChapter]
    var lastReadChapter: Int
    var lastReadPosition: Int
}

struct ArticleChapter {
    let id: UUID
    var title: String
    var content: String                    // Plain text for TTS
    var formattingSpans: [FormattingSpan]? // Rich formatting overlay
}
```

---

## USERDEFAULTS KEYS (DO NOT REUSE)

```
playbackState_Music          - AudioPlayer
playbackState_Speech         - AudioPlayer
playbackPositions            - AudioPlayer
audioMode_Music              - AudioPlayer (Quality/Boost mode)
audioMode_Speech             - AudioPlayer (Quality/Boost mode)
savedBooks                   - BookManager
cachedDurations              - BookManager
playedChapters               - BookManager
favoritePodcasts             - PodcastSearchManager
playedEpisodeURLs            - PodcastSearchManager
downloadedEpisodes           - DownloadManager
downloadedEpisodeMetadata    - DownloadManager
savedArticles                - ArticleManager (App Group)
pendingArticles              - ArticleManager (App Group)
uploadedMusicTracks          - MusicLibraryManager
favoriteRadioStations        - RadioBrowserAPI
```

---

## TEST CHECKLIST (Manual Verification)

After ANY change, verify:

### Lock Screen / Controls
- [ ] Play music only â†’ lock screen shows music info + artwork
- [ ] Play speech only â†’ lock screen shows speech info + artwork
- [ ] Play BOTH â†’ lock screen shows combined title + app logo
- [ ] Pause while both playing â†’ still shows combined info + app logo
- [ ] Pause music only â†’ shows music info
- [ ] Pause speech only â†’ shows speech info

### AirPods / Interruptions
- [ ] Tap AirPods while both playing â†’ both pause
- [ ] Tap AirPods again â†’ both resume
- [ ] Phone call â†’ pauses, resumes after
- [ ] Siri announcement â†’ pauses, resumes after
- [ ] Unplug headphones â†’ both pause

### Persistence
- [ ] Kill app, reopen â†’ state restored (paused)
- [ ] Kill app with radio playing, reopen → radio loaded but NOT auto-playing
- [ ] Kill app with audiobook playing, reopen → audiobook loaded but NOT auto-playing
- [ ] After restore, tap radio station → auto-plays (user action works)
- [ ] Background for 5 min â†’ still works when foregrounded
- [ ] Audio mode persists across app restarts

### M4B Audiobooks
- [ ] Import M4B â†’ chapters detected
- [ ] Play chapter â†’ starts at correct time
- [ ] Chapter ends â†’ auto-advances to next
- [ ] Seek within chapter â†’ stays in chapter bounds
- [ ] Quality/Boost toggle â†’ reloads with correct engine

### Articles (Rich Text)
- [ ] Share URL from Safari â†’ article extracted with formatting
- [ ] Bold/italic text displays correctly
- [ ] Links are purple and tappable â†’ opens Safari
- [ ] TTS highlighting syncs with displayed text
- [ ] Tap word to seek â†’ TTS jumps to that position

---

## WHEN TO TALK TO THE USER INSTEAD OF CODING

1. **Any change to LockScreenManager.update()** â€” Always discuss first
2. **Any change to the "7 things that will break the app"** â€” Always discuss first
3. **Adding lock screen features** (scrubbing, per-player controls) â€” Discuss architecture
4. **Changing persistence keys** â€” Need migration strategy
5. **Changing audio session configuration** â€” High risk of breaking background audio
6. **"Simplifying" or "cleaning up" working code** â€” If it works, leave it alone
7. **Adding new state tracking to LockScreenManager** â€” The boolean flags are correct, don't add complexity
8. **Rewriting article extraction** â€” Current system uses battle-tested libraries (Readability.js, SwiftSoup)

---

## FILE LOCATIONS

| File | Contains |
|------|----------|
| `AudioPlayer.swift` | AudioPlayer, LockScreenManager, InterruptionManager |
| `ContentView.swift` | Main view, initialization, sheet presentations, mode toggles |
| `BookManager.swift` | Book, LibriVoxChapter, BookManager, LibriVoxDownloadManager |
| `BookLibraryView.swift` | M4BChapterReader, file import UI |
| `MP4ChapterParser.swift` | Direct MP4/M4B binary chapter parsing |
| `PodcastSearchManager.swift` | Podcast, Episode, PodcastSearchManager, RSSParser |
| `DownloadManager.swift` | DownloadManager, episode download logic |
| `ArticleManager.swift` | Article, ArticleChapter, FormattingSpan, FormattingStyle |
| `ArticleExtractor.swift` | Readability.js + SwiftSoup extraction pipeline |
| `ArticleReaderView.swift` | Rich text display, TTS sync, RichTextReaderView |
| `ArticleLibraryView.swift` | Article list, add URL/text UI |
| `DocumentImporter.swift` | ePub, PDF, HTML, TXT import (uses ArticleExtractor for HTML) |
| `MusicLibraryManager.swift` | Apple Music library access |
| `RadioBrowserAPI.swift` | RadioStation, RadioBrowserAPI |
| `TTSManager.swift` | Text-to-speech with word highlighting |
| `ImageCache.swift` | Two-tier image caching |
| `SharedComponents.swift` | Reusable UI components (Glass* views) |
| `Track.swift` | Track model with chapter boundary support |
| `Readability.js` | Mozilla's article extraction (bundle resource, not Swift) |
