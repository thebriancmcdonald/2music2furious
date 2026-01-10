# 2 Music 2 Furious: Technical Specification

**For Claude, by Claude** - to prevent regressions or errors when creating or editing features. When writing this be clear but concise with only needed information in here, no fluff.

---

# STOP - READ BEFORE WRITING ANY CODE

Dual audio players (music + speech) play simultaneously. Lock screen, AirPods, and interruption handling are fragile and interconnected. Changes that seem safe can break background playback, resume behavior, or cause crashes.

**AFTER CONTEXT COMPACTION:** Re-read this entire document. Compaction loses details.

---

## THE RULES

1. Read this entire document after context compaction
2. Read the "10 critical systems" before touching playback code
3. Follow patterns exactly when adding features
4. Don't modify working code unless fixing a specific bug
5. When in doubt, ask - especially for lock screen / audio session / interruptions
6. Test the checklist after every change
7. Simple is better - boolean flags in LockScreenManager work; don't add complexity
8. Don't reinvent wheels - use SwiftSoup for HTML, Readability.js for articles

If something needs a change to core audio, **tell the user and discuss options first**.

---

## 10 CRITICAL SYSTEMS - DO NOT MODIFY WITHOUT DISCUSSION

### 1. LockScreenManager.update()

Location: `AudioPlayer.swift`, class `LockScreenManager`

Determines lock screen and Control Center display. Uses `musicWasPlaying` and `speechWasPlaying` boolean flags. Handles 7+ state combinations.

DO NOT:
- Modify state-to-display mapping logic
- Modify "bothWerePlaying" detection
- Change if/else condition order
- Add new state tracking variables

Lesson learned: Adding `lastActivePlayer` string broke everything. The boolean flags are correct. Don't overcomplicate.

---

### 2. AudioPlayer @Published didSet Triggers

Location: `AudioPlayer.swift`, lines ~33-90

These trigger `LockScreenManager.shared.update()` automatically:
- `isPlaying`
- `currentTrack`
- `artwork`
- `playbackSpeed`

DO NOT:
- Remove these didSet triggers
- Add async operations inside didSet
- Change what triggers updates

---

### 3. InterruptionManager Observer Setup

Location: `AudioPlayer.swift`, class `InterruptionManager`

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleInterruption),
    name: AVAudioSession.interruptionNotification,
    object: nil  // MUST BE nil, NOT session
)
```

DO NOT:
- Change `object: nil` - required for Siri announcements
- "Fix" this to use `AVAudioSession.sharedInstance()`

---

### 4. Initialization Order in ContentView.onAppear

Location: `ContentView.swift`

Required order:
1. `setupAudioSession()` - configures audio category
2. Wire `LockScreenManager.shared` to both players
3. Call `setupRemoteCommands()`
4. Wire `InterruptionManager.shared` to both players
5. Restore saved state

DO NOT:
- Reorder these operations
- Move player wiring to a later point
- Make wiring conditional

---

### 5. AudioPlayer Safety Guards

Location: `AudioPlayer.swift`, scattered

Prevent crashes with corrupted files:
```swift
// In duration/currentTime:
guard result.isFinite && result >= 0 else { return 0 }

// In scheduleFileSegment:
let remainingFrames = AVAudioFrameCount(min(remainingFramesInt64, Int64(UInt32.max)))

// In play():
if engine.isRunning { playerNode.play() }
```

DO NOT:
- Remove these guards
- Simplify "for performance"

---

### 6. Chapter End Detection (playbackGeneration + cooldown)

Location: `AudioPlayer.swift`, `scheduleFileSegment()` and `handleChapterEnd()`

M4B audiobooks use virtual chapters (same file, different time ranges). `scheduleSegment` completion fires on finish AND on stop/seek. The generation counter prevents cascade bugs:

```swift
private var playbackGeneration: Int = 0
private var lastChapterTransitionTime: Date = .distantPast

private func scheduleFileSegment(...) {
    playbackGeneration += 1
    let capturedGeneration = playbackGeneration
    
    playerNode.scheduleSegment(...) {
        guard self?.playbackGeneration == capturedGeneration else { return }
        self?.handleChapterEnd()
    }
}
```

Cooldown: When seeking to chapter end, boundary observer fires, then time observer fires again (position still "hot"). Cooldown prevents double-advance:

```swift
func loadTrack(at index: Int) {
    lastChapterTransitionTime = Date()
}

private func handleChapterEnd() {
    guard Date().timeIntervalSince(lastChapterTransitionTime) > 1.0 else { return }
}
```

DO NOT:
- Remove generation counter
- Remove cooldown timestamp check
- Simplify to boolean flag (timing issues)

---

### 7. Startup Auto-Play Suppression (isRestoringState)

Location: `AudioPlayer.swift`, `restoreState()` and `setupAVPlayer()`

App restores saved state on launch but must NOT auto-play. HTTP streams and chapter files normally auto-play when ready - suppress during restoration.

```swift
private var isRestoringState = false

func restoreState(...) {
    isRestoringState = true  // Set BEFORE loading track
}

private func setupAVPlayer(...) {
    playerItemObserver = item.observe(\.status) { 
        if item.status == .readyToPlay {
            let shouldAutoPlay = !self.isRestoringState && (isHTTP || isLocalChapter)
            self.isRestoringState = false  // Clear AFTER check
            if shouldAutoPlay { self.play() }
        }
    }
}
```

Flag cleared inside observer callback, not on timer. HTTP streams can buffer for seconds.

DO NOT:
- Clear isRestoringState on a timer
- Move flag clearing before auto-play check
- Remove flag from AVAudioEngine path

---

### 8. Saved Position Restoration Guard

Location: `AudioPlayer.swift`, `setupAVPlayer()` and `loadLocalFile()`

`restoreSavedPosition()` seeks to last position. ONLY call when `isRestoringState` is true (app startup), NOT when user selects chapter.

Why: Each chapter's end position gets saved. Unconditional restore seeks to chapter END, triggering auto-advance cascade (selecting chapter 12 skips through 13, 14, 15...).

```swift
// CORRECT:
if self.isRestoringState {
    self.restoreSavedPosition()
}
self.isRestoringState = false

// WRONG:
self.restoreSavedPosition()  // Will skip to saved chapter end!
```

Pattern in THREE places:
1. `setupAVPlayer()` - chapter tracks path (inside seek completion)
2. `setupAVPlayer()` - non-chapter tracks path
3. `loadLocalFile()` - AVAudioEngine/Boost mode path

DO NOT:
- Call restoreSavedPosition() without checking isRestoringState
- Use playNow() when track already in queue (inserts duplicates)

---

### 9. BookManager Chapter Tracking (Combine observation)

Location: `BookManager.swift`, `connectToSpeechPlayer()` and `handleChapterIndexChange()`

Observes speech player via Combine publishers (NOT timers) to avoid UI conflicts.

Key behaviors:
- Auto-detects active book from restored queue on launch
- Marks chapter played on natural advance (N to N+1 only)
- Saves position on pause
- Persists `activeBookId` to UserDefaults

```swift
// Connection in ContentView
bookManager.connectToSpeechPlayer(speechPlayer)

// Observation
player.$currentIndex
    .dropFirst()
    .removeDuplicates()
    .sink { newIndex in
        self?.handleChapterIndexChange(to: newIndex)
    }
```

Played detection:
```swift
if newIndex == oldIndex + 1 {
    // Natural completion - mark played
    playedChapterIDs.insert(oldChapterId)
}
// Manual skip does NOT mark played
```

DO NOT:
- Use Timer.publish - conflicts with SeekBarView's timer
- Track percentage-based completion - requires timer, causes bugs

REQUIRED: `activeBookId` must be set (by startPlayingBook or auto-detect)

---

### 10. SeekBarView Track Change Reset

Location: `ContentView.swift`, SeekBarView usage

When chapters advance, SeekBarView `@State` variables can get stuck. SwiftUI `.onChange` has timing issues with rapid changes.

Solution: Use `.id()` to force view recreation:

```swift
SeekBarView(player: speechPlayer)
    .id("\(speechPlayer.currentIndex)-\(speechPlayer.currentTrack?.id.uuidString ?? "none")")
```

When ID changes, SwiftUI destroys old view, creates fresh one with reset state.

DO NOT:
- Rely only on .onChange(of: player.currentTrack)
- Omit currentIndex from .id() (needed for M4B chapter changes)

---

## ARTICLE EXTRACTION SYSTEM

Two-stage pipeline:
1. **Readability.js** (via WKWebView) - extracts clean HTML from messy pages
2. **SwiftSoup** - parses HTML into plain text + formatting spans

Produces TTS-synced rich text: plain text for TTSManager, spans overlay styling without changing indices.

### Dependencies
- SwiftSoup: Swift Package (github.com/scinfu/SwiftSoup)
- Readability.js: Bundle resource (github.com/mozilla/readability)

### Key Files
| File | Purpose |
|------|---------|
| ArticleExtractor.swift | WKWebView + Readability.js, SwiftSoup parsing |
| ArticleManager.swift | Models, FormattingSpan, persistence |
| ArticleReaderView.swift | Rich text display with TTS highlighting |
| DocumentImporter.swift | Local file imports (ePub, PDF, HTML, TXT) |

### Data Models
```swift
struct FormattingSpan: Codable {
    let location: Int      // Character index in plain text
    let length: Int
    let style: FormattingStyle
    let url: String?       // For links only
}
```

### Critical: Index Alignment

FormattingSpan indices are CHARACTER positions in content string. When applying to NSAttributedString:
```swift
let startIdx = content.index(content.startIndex, offsetBy: span.location)
let endIdx = content.index(startIdx, offsetBy: span.length)
let range = NSRange(startIdx..<endIdx, in: content)
```

DO NOT:
- Use span.location directly as NSRange (UTF-16 vs Character mismatch)
- Modify content after spans created (indices will be wrong)
- Skip Readability.js for web URLs (raw HTML has nav/ads/junk)
- Write custom regex HTML parsers (use SwiftSoup)

---

## ADDING NEW FEATURES - DECISION TREE

**Adding NEW CONTENT SOURCE?**
- Safe: Create new manager, new view, wire to existing AudioPlayer
- DANGER: Don't modify AudioPlayer.loadTrack()

**Adding UI to EXISTING VIEW?**
- Safe: Buttons, lists, styling, sheets, navigation
- DANGER: Don't add playback logic in views

**Adding PLAYBACK FEATURE?**
- Check: Needs lock screen display? Talk to user first
- Safe: Add to AudioPlayer methods
- DANGER: Don't modify @Published didSet triggers

**Adding PERSISTENCE?**
- Safe: New UserDefaults keys
- DANGER: Don't change existing key names

**Fixing a BUG?**
- Check: In the "10 critical systems"? Talk to user first
- Safe: Add guards, nil checks, fallbacks
- DANGER: Don't "simplify" working code

**Touching LOCK SCREEN?**
- STOP. Tell the user. This is the #1 regression source.

**Modifying ARTICLE EXTRACTION?**
- Safe: Add FormattingStyle cases, improve SwiftSoup handling
- DANGER: Don't modify content after spans, don't skip Readability.js

---

## PATTERN A: Adding New Content Source

### 1. Create manager class
```swift
class NewSourceManager: ObservableObject {
    static let shared = NewSourceManager()
    @Published var items: [NewItem] = []
    private let storageKey = "newSourceItems"
    // Load, save, fetch methods
}
```

### 2. Create view
```swift
struct NewSourceView: View {
    @ObservedObject var manager = NewSourceManager.shared
    let player: AudioPlayer
    // UI that calls player.playNow() or player.addTrackToQueue()
}
```

### 3. Wire in ContentView
Add sheet presentation, tab, or navigation link.

### 4. Convert to Track
```swift
let track = Track(
    title: item.title,
    artist: item.source,
    filename: item.streamURL  // or local filename
)
player.playNow(track, artworkURL: item.imageURL)
```

---

## PATTERN B: Adding Persisted Data

### 1. Add UserDefaults key (unique, not reusing existing)
```swift
private let newFeatureKey = "newFeatureData"
```

### 2. Add load method
```swift
func loadNewFeatureData() {
    if let data = UserDefaults.standard.data(forKey: newFeatureKey),
       let decoded = try? JSONDecoder().decode([NewFeature].self, from: data) {
        newFeatureData = decoded
    }
}
```

### 3. Add save method, call after mutations
```swift
func updateNewFeature(_ value: String) {
    newFeatureData.append(value)
    saveNewFeatureData()
}
```

---

## MANAGERS REFERENCE

| Manager | Type | Player | Purpose |
|---------|------|--------|---------|
| AudioPlayer | @StateObject (x2) | - | Playback engine |
| MusicLibraryManager | @StateObject | music | Apple Music library |
| BookManager.shared | Singleton | speech | Audiobooks (LibriVox + M4B) |
| PodcastSearchManager | @StateObject | speech | Podcast search + RSS |
| DownloadManager.shared | Singleton | - | Podcast downloads |
| ArticleManager.shared | Singleton | TTS | Articles + documents |
| ArticleExtractor | Static | - | Web extraction |
| RadioBrowserAPI | @StateObject | music | Radio search |
| TTSManager.shared | Singleton | - | Text-to-speech |
| ImageCache.shared | Singleton | - | Artwork caching |

---

## AUDIO SESSION

Location: `ContentView.swift`, `setupAudioSession()`

```swift
try session.setCategory(.playback, mode: .spokenAudio, 
    options: [.allowBluetooth, .allowBluetoothA2DP])
try session.setActive(true, options: .notifyOthersOnDeactivation)
```

DO NOT:
- Change .playback category (breaks background audio)
- Remove Bluetooth options (breaks AirPods)
- Remove .notifyOthersOnDeactivation (breaks other apps)

---

## DATA MODELS

### Track
```swift
struct Track: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let artist: String
    let filename: String      // Local, ipod-library://, or http(s)://
    let startTime: Double?    // M4B chapter start
    let endTime: Double?      // M4B chapter end
    
    var hasChapterBoundaries: Bool { startTime != nil && endTime != nil }
}
```

### Book
```swift
struct Book {
    var id: UUID
    let title: String
    var author: String?
    var chapters: [Track]
    var librivoxChapters: [LibriVoxChapter]?
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
    var chapters: [ArticleChapter]
    var lastReadChapter: Int
    var lastReadPosition: Int
}

struct ArticleChapter {
    let id: UUID
    var title: String
    var content: String                    // Plain text for TTS
    var formattingSpans: [FormattingSpan]?
}
```

---

## USERDEFAULTS KEYS (DO NOT REUSE)

```
playbackState_Music          - AudioPlayer
playbackState_Speech         - AudioPlayer
playbackPositions            - AudioPlayer
audioMode_Music              - AudioPlayer
audioMode_Speech             - AudioPlayer
savedBooks                   - BookManager
cachedDurations              - BookManager
playedChapters               - BookManager
activeBookId                 - BookManager
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

## TEST CHECKLIST

After ANY change, verify:

### Lock Screen / Controls
- [ ] Play music only - shows music info + artwork
- [ ] Play speech only - shows speech info + artwork
- [ ] Play BOTH - shows combined title + app logo
- [ ] Pause while both playing - still shows combined info
- [ ] Pause music only - shows music info
- [ ] Pause speech only - shows speech info

### AirPods / Interruptions
- [ ] Tap AirPods while both playing - both pause
- [ ] Tap again - both resume
- [ ] Phone call - pauses, resumes after
- [ ] Siri announcement - pauses, resumes after
- [ ] Unplug headphones - both pause

### Persistence
- [ ] Kill app, reopen - state restored (paused)
- [ ] Kill with radio playing, reopen - loaded but NOT auto-playing
- [ ] Kill with audiobook playing, reopen - loaded but NOT auto-playing
- [ ] After restore, tap station - auto-plays
- [ ] Background 5 min - still works when foregrounded
- [ ] Audio mode persists across restarts

### M4B Audiobooks
- [ ] Import M4B - chapters detected
- [ ] Play chapter - starts at correct time
- [ ] Chapter ends - auto-advances to next
- [ ] Seek within chapter - stays in bounds
- [ ] Quality/Boost toggle - reloads correctly
- [ ] Seek to chapter end - advances once (not multiple)
- [ ] Seek bar resets after chapter advance

### Audiobook Tracking
- [ ] Chapter naturally ends - marked played in list
- [ ] Tap "next" to skip - NOT marked played
- [ ] Pause mid-chapter, kill app, reopen - Resume shows correct position
- [ ] Swipe left on chapter - can toggle played status
- [ ] "Mark All Played" - all marked
- [ ] "Mark All Unplayed" - all unmarked, resume resets

### Articles
- [ ] Share URL from Safari - extracted with formatting
- [ ] Bold/italic displays correctly
- [ ] Links tappable, open Safari
- [ ] TTS highlighting syncs
- [ ] Tap word to seek - TTS jumps

---

## WHEN TO TALK TO USER FIRST

1. Any change to LockScreenManager.update()
2. Any change to the 10 critical systems
3. Adding lock screen features
4. Changing persistence keys
5. Changing audio session config
6. "Simplifying" working code
7. Adding state tracking to LockScreenManager
8. Rewriting article extraction

---

## SHARE EXTENSION (SaveToReader)

Location: `SaveToReader/ShareViewController.swift`

Modern iOS share extension for saving web articles to the app. Uses native sheet presentation with custom UI.

### Key Features
- **Standard iOS sheet** - Uses system presentation with grab bar
- **Drawing checkmark animation** - Purple checkmark animates on success
- **Read/Listen actions** - Deep links into main app
- **Error handling with retry** - Graceful failure with retry button
- **Haptic feedback** - Success and error haptics
- **Auto-dismiss** - 4s for success, 6s for errors (cancellable by user interaction)

### UI Hierarchy (Success State)
```
[Standard iOS Grab Bar - 36pt × 4pt, 6pt from top]

    [100×100 App Logo - rounded corners]
    [24×24 Checkmark] "Saved"  ← horizontal row
    "Article Title"

    [Read Button] [Listen Button]
```

### Visual Design Standards
- **Grab bar**: 36pt wide, 4pt tall, systemGray4, 2pt corner radius, 6pt from top
- **Logo**: 100×100pt, 22pt corner radius, fades in first
- **Checkmark**: 24×24pt, 2.5pt stroke, draws after logo (circle then check)
- **Spacing**: 24pt between main elements, 16pt spacer before buttons
- **Colors**: Brand purple (#AF52DE area), systemGray4 for grab bar
- **Buttons**: 54pt tall, purple primary (Listen), gray secondary (Read)

### Animation Timeline
1. **0.0s** - Logo fades in (0.3s duration)
2. **0.3s** - Checkmark circle draws (0.3s duration)
3. **0.55s** - Checkmark draws (0.25s duration)
4. **0.3s** - "Saved" row fades in (0.3s duration)
5. **0.5s** - Article title fades in (0.4s duration)
6. **0.7s** - Buttons scale in with spring (0.5s duration)

### Deep Linking
URL scheme: `2music2furious://article?action=[read|listen]&id=[UUID]`
- **read** - Opens article in reader view
- **listen** - Opens article and starts TTS playback

### DO NOT:
- Remove or modify the grab bar dimensions (standard iOS)
- Change animation timing without testing full sequence
- Remove haptic feedback
- Skip the drawing animation for checkmark
- Change the hierarchy order (logo → checkmark+saved → title → buttons)
- Modify auto-dismiss timers without user discussion

### Error State
Same sheet layout but:
- Red error icon (70×70pt) instead of logo+checkmark
- Red "Couldn't Save Article" title
- Gray error message (descriptive)
- Retry (purple) and Cancel (gray) buttons
- 6s auto-dismiss (longer than success)

---

## FILE LOCATIONS

| File | Contains |
|------|----------|
| AudioPlayer.swift | AudioPlayer, LockScreenManager, InterruptionManager |
| ContentView.swift | Main view, init, sheets, mode toggles |
| BookManager.swift | Book, LibriVoxChapter, BookManager, LibriVoxDownloadManager |
| BookLibraryView.swift | M4BChapterReader, file import UI |
| MP4ChapterParser.swift | MP4/M4B binary chapter parsing |
| PodcastSearchManager.swift | Podcast, Episode, PodcastSearchManager, RSSParser |
| DownloadManager.swift | Episode download logic |
| ArticleManager.swift | Article, ArticleChapter, FormattingSpan |
| ArticleExtractor.swift | Readability.js + SwiftSoup pipeline |
| ArticleReaderView.swift | Rich text display, TTS sync |
| ArticleLibraryView.swift | Article list, add URL/text UI |
| DocumentImporter.swift | ePub, PDF, HTML, TXT import |
| MusicLibraryManager.swift | Apple Music library access |
| RadioBrowserAPI.swift | RadioStation, RadioBrowserAPI |
| TTSManager.swift | Text-to-speech with highlighting |
| ImageCache.swift | Two-tier image caching |
| SharedComponents.swift | Reusable UI (Glass* views) |
| Track.swift | Track model with chapter support |
| Readability.js | Mozilla article extraction (bundle resource) |
| **SaveToReader/ShareViewController.swift** | **Share Extension - article saving UI** |
