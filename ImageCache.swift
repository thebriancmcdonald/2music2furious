//
//  ImageCache.swift
//  2 Music 2 Furious
//
//  Persistent image caching with memory + disk layers and expiration
//  Used for podcast artwork, LibriVox covers, radio station icons
//

import SwiftUI
import UIKit
import CryptoKit

// MARK: - Image Cache Manager

class ImageCache {
    static let shared = ImageCache()
    
    // MARK: - Configuration
    
    /// How long cached images stay valid (7 days)
    private let cacheExpirationDays: Double = 7
    
    /// Maximum memory cache size (50 images)
    private let maxMemoryCacheCount = 50
    
    // MARK: - Storage
    
    /// Fast in-memory cache (cleared when app closes)
    private var memoryCache = NSCache<NSString, UIImage>()
    
    /// Track when images were cached (for expiration)
    private var cacheTimestamps: [String: Date] = [:]
    
    /// Serial queue for thread-safe disk operations
    private let diskQueue = DispatchQueue(label: "com.2music2furious.imagecache", qos: .utility)
    
    /// Directory for cached images
    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("ImageCache", isDirectory: true)
    }
    
    // MARK: - Initialization
    
    init() {
        memoryCache.countLimit = maxMemoryCacheCount
        createCacheDirectoryIfNeeded()
        loadTimestamps()
        
        // Clean expired images on launch (in background)
        diskQueue.async { [weak self] in
            self?.cleanExpiredImages()
        }
    }
    
    // MARK: - Public API
    
    /// Get an image from cache, or fetch from URL if not cached/expired
    /// - Parameters:
    ///   - url: The image URL
    ///   - completion: Called with the image (on main thread)
    func image(for url: URL, completion: @escaping (UIImage?) -> Void) {
        let key = cacheKey(for: url)
        
        // 1. Check memory cache (instant)
        if let cached = memoryCache.object(forKey: key as NSString) {
            completion(cached)
            
            // If expired, refresh in background (but still show cached version)
            if isExpired(key: key) {
                fetchAndCache(url: url, key: key, completion: nil)
            }
            return
        }
        
        // 2. Check disk cache (fast, but async)
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let diskImage = self.loadFromDisk(key: key) {
                // Found on disk - add to memory cache
                self.memoryCache.setObject(diskImage, forKey: key as NSString)
                
                DispatchQueue.main.async {
                    completion(diskImage)
                }
                
                // If expired, refresh in background
                if self.isExpired(key: key) {
                    self.fetchAndCache(url: url, key: key, completion: nil)
                }
                return
            }
            
            // 3. Not in cache - fetch from network
            self.fetchAndCache(url: url, key: key) { image in
                DispatchQueue.main.async {
                    completion(image)
                }
            }
        }
    }
    
    /// Preload an image into cache (fire and forget)
    func preload(url: URL) {
        let key = cacheKey(for: url)
        
        // Skip if already in memory cache and not expired
        if memoryCache.object(forKey: key as NSString) != nil && !isExpired(key: key) {
            return
        }
        
        image(for: url) { _ in }
    }
    
    /// Clear all cached images (memory + disk)
    func clearAll() {
        memoryCache.removeAllObjects()
        cacheTimestamps.removeAll()
        
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.cacheDirectory)
            self.createCacheDirectoryIfNeeded()
            self.saveTimestamps()
        }
    }
    
    /// Remove a specific cached image
    func remove(for url: URL) {
        let key = cacheKey(for: url)
        memoryCache.removeObject(forKey: key as NSString)
        cacheTimestamps.removeValue(forKey: key)
        
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            let fileURL = self.cacheDirectory.appendingPathComponent(key)
            try? FileManager.default.removeItem(at: fileURL)
            self.saveTimestamps()
        }
    }
    
    // MARK: - Private Helpers
    
    private func cacheKey(for url: URL) -> String {
        // Use SHA256 to create a unique, fixed-length hash of the URL
        let inputData = Data(url.absoluteString.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func isExpired(key: String) -> Bool {
        guard let timestamp = cacheTimestamps[key] else {
            return true
        }
        let expirationInterval = cacheExpirationDays * 24 * 60 * 60
        return Date().timeIntervalSince(timestamp) > expirationInterval
    }
    
    private func fetchAndCache(url: URL, key: String, completion: ((UIImage?) -> Void)?) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data),
                  error == nil else {
                completion?(nil)
                return
            }
            
            // Save to memory cache
            self.memoryCache.setObject(image, forKey: key as NSString)
            
            // Save to disk cache
            self.diskQueue.async {
                self.saveToDisk(image: image, key: key)
                self.cacheTimestamps[key] = Date()
                self.saveTimestamps()
            }
            
            completion?(image)
        }.resume()
    }
    
    // MARK: - Disk Operations
    
    private func createCacheDirectoryIfNeeded() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func saveToDisk(image: UIImage, key: String) {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        
        // Use JPEG for photos (smaller), PNG if transparency needed
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
    }
    
    private func loadFromDisk(key: String) -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: data)
    }
    
    private func cleanExpiredImages() {
        let fileManager = FileManager.default
        var keysToRemove: [String] = []
        
        for (key, timestamp) in cacheTimestamps {
            let expirationInterval = cacheExpirationDays * 24 * 60 * 60
            if Date().timeIntervalSince(timestamp) > expirationInterval {
                let fileURL = cacheDirectory.appendingPathComponent(key)
                try? fileManager.removeItem(at: fileURL)
                keysToRemove.append(key)
            }
        }
        
        for key in keysToRemove {
            cacheTimestamps.removeValue(forKey: key)
        }
        
        if !keysToRemove.isEmpty {
            saveTimestamps()
            print("ImageCache: Cleaned \(keysToRemove.count) expired images")
        }
    }
    
    // MARK: - Timestamp Persistence
    
    private var timestampsFileURL: URL {
        cacheDirectory.appendingPathComponent("timestamps.plist")
    }
    
    private func saveTimestamps() {
        if let data = try? PropertyListEncoder().encode(cacheTimestamps) {
            try? data.write(to: timestampsFileURL)
        }
    }
    
    private func loadTimestamps() {
        guard let data = try? Data(contentsOf: timestampsFileURL),
              let decoded = try? PropertyListDecoder().decode([String: Date].self, from: data) else {
            return
        }
        cacheTimestamps = decoded
    }
}

// MARK: - Cached Async Image View

/// Drop-in replacement for AsyncImage that uses persistent caching
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { oldValue, newValue in
            image = nil
            isLoading = true
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url else {
            isLoading = false
            return
        }
        
        ImageCache.shared.image(for: url) { loadedImage in
            withAnimation(.easeIn(duration: 0.2)) {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}

// MARK: - Convenience Extension

extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content) {
        self.init(url: url, content: content, placeholder: { ProgressView() })
    }
}
