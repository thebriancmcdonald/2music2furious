# 2 Music 2 Furious: Technical Specification

---

# Ã¢â€ºâ€ STOP Ã¢â‚¬â€ READ BEFORE WRITING ANY CODE Ã¢â€ºâ€

This app has **dual audio players** (music + speech) that play simultaneously. The lock screen, AirPods, and interruption handling are fragile and interconnected. Changes that seem safe can break background playback, resume behavior, or cause crashes.

**Ã°Å¸â€â€ž AFTER CONTEXT COMPACTION:** Re-read this entire document. Compaction loses details.

---

## SUMMARY: THE RULES

> âš ï¸ **THIS SUMMARY STAYS AT THE TOP.** Don't move it to the bottomâ€”Claude needs to see this first, not last.

1. **Read this entire document after context compaction**
2. **Read the "8 things" before touching any playback code**
3. **Follow the patterns exactly** when adding new features
4. **Don't modify working code** unless fixing a specific bug
5. **When in doubt, ask** â€” especially for lock screen / audio session / interruptions
6. **Test the checklist** after every change
7. **Simple is better** â€” the boolean flags in LockScreenManager work; don't add complexity
8. **Don't reinvent wheels** â€” use SwiftSoup for HTML parsing, Readability.js for article extraction

If something seems like it needs a change to the core audio system, **tell the user and discuss options** rather than making the change directly.

---

## THE 8 THINGS THAT WILL BREAK THE APP

### 1. LockScreenManager.update() Ã¢â‚¬â€ THE MOST FRAGILE CODE

**Location:** `AudioPlayer.swift`, class `LockScreenManager`

This method determines what shows on the lock screen and Control Center. It uses `musicWasPlaying` and `speechWasPlaying` boolean flags to track state across pause/resume cycles. The logic handles 7+ different combinations of "what's playing" and "what was playing."

```
Ã°Å¸â€Â´ DO NOT MODIFY the state-to-display mapping logic
Ã°Å¸â€Â´ DO NOT MODIFY the "bothWerePlaying" detection logic
Ã°Å¸â€Â´ DO NOT CHANGE the order of if/else conditions
Ã°Å¸â€Â´ DO NOT add new state tracking variables (the existing flags work)
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
Ã°Å¸â€Â´ DO NOT REMOVE these didSet triggers
Ã°Å¸â€Â´ DO NOT ADD async operations inside didSet
Ã°Å¸â€Â´ DO NOT CHANGE what triggers updates
```

---

### 3. InterruptionManager Observer Setup

**Location:** `AudioPlayer.swift`, class `InterruptionManager`

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleInterruption),
    name: AVAudioSession.interruptionNotification,
    object: nil  // Ã¢â€ Â MUST BE nil, NOT session
)
```

```
Ã°Å¸â€Â´ object: nil is REQUIRED to catch Siri announcements
Ã°Å¸â€Â´ DO NOT "fix" this to use AVAudioSession.sharedInstance()
```

---

### 4. Initialization Order in ContentView.onAppear

**Location:** `ContentView.swift`, lines ~97-116

This order is required:
1. `setupAudioSession()` Ã¢â‚¬â€ configures audio category
2. Wire `LockScreenManager.shared` to both players
3. Call `setupRemoteCommands()`
4. Wire `InterruptionManager.shared` to both players
5. Restore saved state

```
Ã°Å¸â€Â´ DO NOT reorder these operations
Ã°Å¸â€Â´ DO NOT move player wiring to a later point
Ã°Å¸â€Â´ DO NOT make wiring conditional
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
Ã°Å¸â€Â´ DO NOT REMOVE these guards
Ã°Å¸â€Â´ DO NOT simplify "for performance"
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
Ã°Å¸â€Â´ DO NOT REMOVE the generation counter
Ã°Å¸â€Â´ DO NOT simplify to a boolean flag (timing issues)
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

**Critical:** The flag is cleared **inside the observer callback**, not on a timer. HTTP streams can take seconds to bufferâ€”a timer-based approach will fail.

```
ðŸ”´ DO NOT clear isRestoringState on a timer
ðŸ”´ DO NOT move the flag clearing before the auto-play check
ðŸ”´ DO NOT remove the flag from the AVAudioEngine path in loadLocalFile()
```

---

### 8. Saved Position Restoration Guard (isRestoringState for restoreSavedPosition)

**Location:** `AudioPlayer.swift`, `setupAVPlayer()` and `loadLocalFile()`

The `restoreSavedPosition()` function seeks to where the user last left off in a track. This must ONLY be called when `isRestoringState` is true (during app startup), NOT when the user manually selects a chapter. 

**Why this matters:** When playing through an audiobook, each chapter's end position gets saved. If `restoreSavedPosition()` is called unconditionally when selecting a chapter, it will seek to that saved position (usually the chapter's END), triggering immediate auto-advance to the next chapter. This creates a cascade where selecting chapter 12 instantly skips through 13, 14, 15... until reaching an unplayed chapter.

```swift
// CORRECT: Only restore position during state restoration
if self.isRestoringState {
    self.restoreSavedPosition()
}
self.isRestoringState = false  // Clear flag after check

// WRONG: Unconditionally restoring position
self.restoreSavedPosition()  // Will skip to saved chapter end!
self.isRestoringState = false
```

This pattern must be followed in THREE places:
1. `setupAVPlayer()` — chapter tracks path (inside seek completion handler)
2. `setupAVPlayer()` — non-chapter tracks path  
3. `loadLocalFile()` — AVAudioEngine/Boost mode path

```
🔴 DO NOT call restoreSavedPosition() without checking isRestoringState first
🔴 DO NOT use playNow() when track is already in queue (it inserts duplicates at index 0)
🔴 If chapters are skipping on re-selection, check this guard FIRST
```

---

## ARTICLE EXTRACTION SYSTEM

### Architecture Overview

Articles use a **two-stage extraction pipeline**:

1. **Readability.js** (via WKWebView) Ã¢â‚¬â€ Extracts clean article HTML from messy web pages
2. **SwiftSoup** Ã¢â‚¬â€ Parses clean HTML into plain text + formatting spans

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
Ã°Å¸â€Â´ FormattingSpan indices are CHARACTER positions in content string
Ã°Å¸â€Â´ When applying to NSAttributedString, convert properly:
   let startIdx = content.index(content.startIndex, offsetBy: span.location)
   let endIdx = content.index(startIdx, offsetBy: span.length)
   let range = NSRange(startIdx..<endIdx, in: content)
Ã°Å¸â€Â´ DO NOT use span.location directly as NSRange Ã¢â‚¬â€ UTF-16 vs Character mismatch
Ã°Å¸â€Â´ DO NOT modify content after spans are created Ã¢â‚¬â€ indices will be wrong
```

### Extraction Flow

```
URL Ã¢â€ â€™ WKWebView loads page
    Ã¢â€ â€™ Readability.js extracts article HTML
    Ã¢â€ â€™ SwiftSoup parses HTML
    Ã¢â€ â€™ processNode() walks DOM, builds:
        - plainText (appending text content)
        - spans (tracking tag positions)
    Ã¢â€ â€™ Article saved with content + formattingSpans
```

```
Ã°Å¸â€Â´ DO NOT try to "clean" content after extraction Ã¢â‚¬â€ breaks span alignment
Ã°Å¸â€Â´ DO NOT write custom regex HTML parsers Ã¢â‚¬â€ use SwiftSoup
Ã°Å¸â€Â´ DO NOT skip Readability.js for web URLs Ã¢â‚¬â€ raw HTML has nav/ads/junk
```

---

## BEFORE YOU CODE: DECISION TREE

### What are you trying to do?

```
Adding NEW CONTENT SOURCE (new API, new file type)?
  Ã¢â€ â€™ See: PATTERN A below
  Ã¢â€ â€™ Safe: Create new manager, new view
  Ã¢â€ â€™ Safe: Wire to existing AudioPlayer
  Ã¢â€ â€™ DANGER: Don't modify AudioPlayer.loadTrack()

Adding UI to EXISTING VIEW?
  Ã¢â€ â€™ Safe: Add buttons, lists, styling
  Ã¢â€ â€™ Safe: Add new sheets/navigation
  Ã¢â€ â€™ DANGER: Don't add playback logic in views

Adding PLAYBACK FEATURE (speed, effects, queue)?
  Ã¢â€ â€™ Check: Does it need lock screen display? Ã¢â€ â€™ Talk to user first
  Ã¢â€ â€™ Safe: Add to AudioPlayer methods
  Ã¢â€ â€™ DANGER: Don't modify @Published didSet triggers

Adding PERSISTENCE (new data to save)?
  Ã¢â€ â€™ See: PATTERN B below  
  Ã¢â€ â€™ Safe: New UserDefaults keys
  Ã¢â€ â€™ DANGER: Don't change existing key names

Fixing a BUG?
  Ã¢â€ â€™ Check: Is it in the "7 things" above? Ã¢â€ â€™ Talk to user first
  Ã¢â€ â€™ Safe: Add guards, nil checks, fallbacks
  Ã¢â€ â€™ DANGER: Don't "simplify" working code

Touching LOCK SCREEN behavior?
  Ã¢â€ â€™ Ã°Å¸â€ºâ€˜ STOP. Tell the user. This is the #1 regression source.

Modifying ARTICLE EXTRACTION?
  Ã¢â€ â€™ Safe: Add new FormattingStyle cases
  Ã¢â€ â€™ Safe: Improve SwiftSoup node handling
  Ã¢â€ â€™ DANGER: Don't modify content string after spans created
  Ã¢â€ â€™ DANGER: Don't skip Readability.js for web content
```

---

## AUDIO MODE: QUALITY vs BOOST

**Location:** `AudioPlayer.swift`, `audioMode` property

The speech player has a toggle between two audio engines:

| Mode | Engine | Speed Quality | Voice Boost | Use Case |
|------|--------|---------------|-------------|----------|
| **Quality** | AVPlayer | Excellent (Apple's algorithm) | Ã¢ÂÅ’ Not available | Default. Sounds natural at 1.5x+ |
| **Boost** | AVAudioEngine | Robotic at high speeds | Ã¢Å“â€¦ Works | Quiet audiobooks, noisy environments |

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
Ã°Å¸â€Â´ DO NOT remove the mode toggle without discussing
Ã°Å¸â€Â´ DO NOT force one engine for all content types
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
Ã°Å¸â€Â´ DO NOT modify this logic without understanding both paths
Ã°Å¸â€Â´ DO NOT remove the audioMode check
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
    loadNewFeatureData()  // Ã¢â€ Â Add here
    isLoaded = true
}
```

### 3. Add save method, call after mutations

```swift
func updateNewFeature(_ value: String) {
    newFeatureData.append(value)
    saveNewFeatureData()  // Ã¢â€ Â Immediate save
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
Ã°Å¸â€Â´ DO NOT change .playback category (breaks background audio)
Ã°Å¸â€Â´ DO NOT remove Bluetooth options (breaks AirPods)
Ã°Å¸â€Â´ DO NOT remove .notifyOthersOnDeactivation (breaks other apps)
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
- [ ] Play music only Ã¢â€ â€™ lock screen shows music info + artwork
- [ ] Play speech only Ã¢â€ â€™ lock screen shows speech info + artwork
- [ ] Play BOTH Ã¢â€ â€™ lock screen shows combined title + app logo
- [ ] Pause while both playing Ã¢â€ â€™ still shows combined info + app logo
- [ ] Pause music only Ã¢â€ â€™ shows music info
- [ ] Pause speech only Ã¢â€ â€™ shows speech info

### AirPods / Interruptions
- [ ] Tap AirPods while both playing Ã¢â€ â€™ both pause
- [ ] Tap AirPods again Ã¢â€ â€™ both resume
- [ ] Phone call Ã¢â€ â€™ pauses, resumes after
- [ ] Siri announcement Ã¢â€ â€™ pauses, resumes after
- [ ] Unplug headphones Ã¢â€ â€™ both pause

### Persistence
- [ ] Kill app, reopen Ã¢â€ â€™ state restored (paused)
- [ ] Kill app with radio playing, reopen â†’ radio loaded but NOT auto-playing
- [ ] Kill app with audiobook playing, reopen â†’ audiobook loaded but NOT auto-playing
- [ ] After restore, tap radio station â†’ auto-plays (user action works)
- [ ] Background for 5 min Ã¢â€ â€™ still works when foregrounded
- [ ] Audio mode persists across app restarts

### M4B Audiobooks
- [ ] Import M4B Ã¢â€ â€™ chapters detected
- [ ] Play chapter Ã¢â€ â€™ starts at correct time
- [ ] Chapter ends Ã¢â€ â€™ auto-advances to next
- [ ] Seek within chapter Ã¢â€ â€™ stays in chapter bounds
- [ ] Quality/Boost toggle Ã¢â€ â€™ reloads with correct engine

### Articles (Rich Text)
- [ ] Share URL from Safari Ã¢â€ â€™ article extracted with formatting
- [ ] Bold/italic text displays correctly
- [ ] Links are purple and tappable Ã¢â€ â€™ opens Safari
- [ ] TTS highlighting syncs with displayed text
- [ ] Tap word to seek Ã¢â€ â€™ TTS jumps to that position

---

## WHEN TO TALK TO THE USER INSTEAD OF CODING

1. **Any change to LockScreenManager.update()** Ã¢â‚¬â€ Always discuss first
2. **Any change to the "7 things that will break the app"** Ã¢â‚¬â€ Always discuss first
3. **Adding lock screen features** (scrubbing, per-player controls) Ã¢â‚¬â€ Discuss architecture
4. **Changing persistence keys** Ã¢â‚¬â€ Need migration strategy
5. **Changing audio session configuration** Ã¢â‚¬â€ High risk of breaking background audio
6. **"Simplifying" or "cleaning up" working code** Ã¢â‚¬â€ If it works, leave it alone
7. **Adding new state tracking to LockScreenManager** Ã¢â‚¬â€ The boolean flags are correct, don't add complexity
8. **Rewriting article extraction** Ã¢â‚¬â€ Current system uses battle-tested libraries (Readability.js, SwiftSoup)

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
