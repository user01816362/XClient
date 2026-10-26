//
//  MediaDownloadManager.swift
//  XClient
//
//  Centralized media downloading, SHA-256 disk caching, streaming progress tracking,
//  and dual-platform device export (macOS Downloads / iOS Photos).
//  100% Swift 6 strict concurrency compliance.
//

import Foundation
import SwiftUI
import CryptoKit

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
import Photos
public typealias PlatformImage = UIImage
#endif

/// Specific errors thrown by MediaDownloadManager operations.
public enum MediaDownloadError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case networkError(String)
    case downloadCancelled
    case fileSystemError(String)
    case photosAccessDenied
    case unsupportedMediaType

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "The media URL is malformed."
        case .networkError(let msg): return "Network download failed: \(msg)"
        case .downloadCancelled: return "Download task was cancelled."
        case .fileSystemError(let msg): return "File storage error: \(msg)"
        case .photosAccessDenied: return "Photos library permission was denied."
        case .unsupportedMediaType: return "Unsupported media format for saving."
        }
    }
}

/// Centralized media downloading, caching, and platform export manager.
/// Conforms to Swift 6 strict concurrency and @MainActor isolation.
@MainActor
public final class MediaDownloadManager: ObservableObject, Sendable {
    public static let shared = MediaDownloadManager()

    // MARK: - Published Reactive State
    @Published public private(set) var activeProgress: [URL: Double] = [:]
    @Published public private(set) var completedDownloads: Set<URL> = []
    @Published public private(set) var activeErrors: [URL: String] = [:]

    // MARK: - In-Flight Task Coalescing
    private var inFlightTasks: [URL: Task<URL, Error>] = [:]

    // MARK: - Dedicated Cache Directory
    public let cacheDirectory: URL
    private let urlSession: URLSession

    public init(session: URLSession = .shared, customCacheDirectory: URL? = nil) {
        self.urlSession = session
        if let custom = customCacheDirectory {
            self.cacheDirectory = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.cacheDirectory = appSupport.appendingPathComponent("XClient/MediaCache", isDirectory: true)
        }
        createCacheDirectoryIfNeeded()
    }

    private func createCacheDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Extension & Key Helpers

    /// Extracts reliable file extension even from query parameters (e.g. ?format=jpg).
    public static func fileExtension(for url: URL, fallback: String = "jpg") -> String {
        let directExt = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !directExt.isEmpty {
            return directExt
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            if let formatItem = queryItems.first(where: { $0.name.lowercased() == "format" }),
               let val = formatItem.value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !val.isEmpty {
                return val
            }
            if let extItem = queryItems.first(where: { $0.name.lowercased() == "ext" }),
               let val = extItem.value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !val.isEmpty {
                return val
            }
        }
        return fallback
    }

    /// Sanitizes filename against directory traversal sequences.
    public static func sanitizeFilename(_ raw: String) -> String {
        let lastComponent = (raw as NSString).lastPathComponent
        var cleaned = lastComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "..", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". \t\n\r"))
        if cleaned.isEmpty {
            cleaned = "media_\(Int(Date().timeIntervalSince1970))"
        }
        return cleaned
    }

    /// Generates a deterministic, collision-free SHA-256 filename for any URL with its extension preserved.
    public func cacheKey(for url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        let pathExt = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = pathExt.isEmpty ? Self.fileExtension(for: url, fallback: "media") : pathExt.lowercased()
        return "\(hex).\(ext)"
    }

    /// Returns the local cached URL if the file exists on disk, nil otherwise.
    public func cachedFileURL(for url: URL) -> URL? {
        let fileUrl = cacheDirectory.appendingPathComponent(cacheKey(for: url))
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            return fileUrl
        }
        return nil
    }

    /// Returns true if the media asset is currently cached locally on disk.
    public func isCached(url: URL) -> Bool {
        cachedFileURL(for: url) != nil
    }

    // MARK: - Streaming Download

    /// Downloads media from remote URL with progressive byte streaming, disk caching, and sibling task coalescing.
    @discardableResult
    public func downloadMedia(from url: URL, filename: String? = nil) async throws -> URL {
        try Task.checkCancellation()

        // 1. Check local cache first
        if let existing = cachedFileURL(for: url) {
            activeProgress[url] = 1.0
            completedDownloads.insert(url)
            return existing
        }

        // 2. Coalesce concurrent sibling tasks
        if let existingTask = inFlightTasks[url] {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let result = try await existingTask.value
                try Task.checkCancellation()
                return result
            } onCancel: {
                // Sibling caller cancelled
            }
        }

        let downloadTask = Task<URL, Error> { @MainActor [weak self] in
            guard let self = self else { throw MediaDownloadError.downloadCancelled }
            defer {
                self.inFlightTasks.removeValue(forKey: url)
            }

            self.activeProgress[url] = 0.0
            self.activeErrors.removeValue(forKey: url)

            let targetDestination = self.cacheDirectory.appendingPathComponent(self.cacheKey(for: url))
            let tempDestination = self.cacheDirectory.appendingPathComponent("\(UUID().uuidString).tmp")

            do {
                let (asyncBytes, response) = try await self.urlSession.bytes(from: url)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw MediaDownloadError.networkError("HTTP status \(code)")
                }

                let expectedLength = response.expectedContentLength
                var accumulatedData = Data()
                var lastReportedProgress: Double = 0.0

                if FileManager.default.fileExists(atPath: tempDestination.path) {
                    try? FileManager.default.removeItem(at: tempDestination)
                }
                FileManager.default.createFile(atPath: tempDestination.path, contents: nil)
                guard let fileHandle = try? FileHandle(forWritingTo: tempDestination) else {
                    throw MediaDownloadError.fileSystemError("Cannot open file handle for writing.")
                }

                for try await byte in asyncBytes {
                    if Task.isCancelled {
                        try? fileHandle.close()
                        try? FileManager.default.removeItem(at: tempDestination)
                        throw MediaDownloadError.downloadCancelled
                    }

                    accumulatedData.append(byte)

                    // Flush in 64KB chunks to optimize disk I/O
                    if accumulatedData.count >= 65536 {
                        try fileHandle.write(contentsOf: accumulatedData)
                        accumulatedData.removeAll(keepingCapacity: true)

                        if expectedLength > 0 {
                            let current = Double(try fileHandle.offset()) / Double(expectedLength)
                            if current - lastReportedProgress > 0.02 {
                                lastReportedProgress = current
                                self.activeProgress[url] = min(0.99, current)
                            }
                        }
                    }
                }

                if !accumulatedData.isEmpty {
                    try fileHandle.write(contentsOf: accumulatedData)
                }
                try fileHandle.close()

                // Atomic move to final cache location
                if FileManager.default.fileExists(atPath: targetDestination.path) {
                    try? FileManager.default.removeItem(at: targetDestination)
                }
                try FileManager.default.moveItem(at: tempDestination, to: targetDestination)

                self.activeProgress[url] = 1.0
                self.completedDownloads.insert(url)
                return targetDestination

            } catch {
                try? FileManager.default.removeItem(at: tempDestination)
                self.activeProgress.removeValue(forKey: url)

                let isCancelled = (error is CancellationError) || (error as? MediaDownloadError) == .downloadCancelled
                if !isCancelled {
                    self.activeErrors[url] = error.localizedDescription
                }
                throw error
            }
        }

        inFlightTasks[url] = downloadTask
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result = try await downloadTask.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            downloadTask.cancel()
        }
    }

    // MARK: - Platform-Conditional Save
    #if os(macOS)
    /// macOS: Saves media file directly to user's ~/Downloads directory with collision avoidance.
    @discardableResult
    public func saveMediaToLocalDevice(
        from url: URL,
        customFilename: String? = nil,
        destinationDirectory: URL? = nil
    ) async throws -> URL {
        // 1. Path traversal defense
        if let custom = customFilename {
            if custom.contains("/") || custom.contains("\\") || custom.contains("..") {
                throw MediaDownloadError.fileSystemError("Invalid filename: directory traversal detected")
            }
        }

        let cachedURL = try await downloadMedia(from: url)
        var downloadsDir = destinationDirectory
            ?? (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))

        do {
            if !FileManager.default.fileExists(atPath: downloadsDir.path) {
                try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            }
        } catch {
            downloadsDir = FileManager.default.temporaryDirectory.appendingPathComponent("Downloads")
            if !FileManager.default.fileExists(atPath: downloadsDir.path) {
                try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            }
        }

        var baseName: String
        let ext = Self.fileExtension(for: url, fallback: "jpg")
        if let custom = customFilename {
            let sanitized = Self.sanitizeFilename(custom)
            let pathExt = (sanitized as NSString).pathExtension
            baseName = pathExt.isEmpty ? "\(sanitized).\(ext)" : sanitized
        } else {
            let rawLast = (url.lastPathComponent as NSString).deletingPathExtension
            let namePart = rawLast.isEmpty ? "media_\(Int(Date().timeIntervalSince1970))" : Self.sanitizeFilename(rawLast)
            baseName = "\(namePart).\(ext)"
        }

        var targetURL = downloadsDir.appendingPathComponent(baseName)

        // Strict Path Traversal Assertion
        let standardTarget = targetURL.standardizedFileURL.path
        let standardDir = downloadsDir.standardizedFileURL.path
        guard standardTarget.hasPrefix(standardDir) else {
            throw MediaDownloadError.fileSystemError("Destination URL escapes target directory")
        }

        // Collision avoidance with atomic TOCTOU resilience:
        var counter = 1
        let nameWithoutExt = (baseName as NSString).deletingPathExtension
        let finalExt = (baseName as NSString).pathExtension
        while true {
            while FileManager.default.fileExists(atPath: targetURL.path) {
                let numberedName = finalExt.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(finalExt)"
                targetURL = downloadsDir.appendingPathComponent(numberedName)
                counter += 1
            }

            do {
                try FileManager.default.copyItem(at: cachedURL, to: targetURL)
                break
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileWriteFileExistsError || error.code == 516) {
                let numberedName = finalExt.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(finalExt)"
                targetURL = downloadsDir.appendingPathComponent(numberedName)
                counter += 1
            }
        }
        return targetURL
    }

    public func saveToPhotos(image: PlatformImage) async throws {
        // macOS does not provide a standard Photos album direct write API without PhotoKit authorization;
        // writes image to ~/Downloads/ as high-res PNG.
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let fileURL = downloadsDir.appendingPathComponent("Saved_Image_\(Int(Date().timeIntervalSince1970)).png")
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: fileURL)
        }
    }

    #else
    /// iOS: Saves media file to Photos library via PhotoKit.
    @discardableResult
    public func saveMediaToLocalDevice(
        from url: URL,
        customFilename: String? = nil,
        destinationDirectory: URL? = nil
    ) async throws -> URL {
        let cachedURL = try await downloadMedia(from: url)
        let ext = cachedURL.pathExtension.lowercased()

        let isVideo = ["mp4", "mov", "m4v"].contains(ext)
        let isImage = ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext)

        guard isVideo || isImage else {
            throw MediaDownloadError.unsupportedMediaType
        }

        // Check PhotoKit authorization
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let requested = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard requested == .authorized || requested == .limited else {
                throw MediaDownloadError.photosAccessDenied
            }
        } else if status == .denied || status == .restricted {
            throw MediaDownloadError.photosAccessDenied
        }

        // Perform asset creation request
        try await PHPhotoLibrary.shared().performChanges {
            if isVideo {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: cachedURL)
            } else {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: cachedURL)
            }
        }

        return cachedURL
    }

    public func saveToPhotos(image: PlatformImage) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let requested = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard requested == .authorized || requested == .limited else {
                throw MediaDownloadError.photosAccessDenied
            }
        } else if status == .denied || status == .restricted {
            throw MediaDownloadError.photosAccessDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
    #endif

    // MARK: - Cache Metrics & Purging

    /// Computes total size in bytes of all cached media files.
    public func cacheSizeInBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Purges all cached files from disk and resets reactive download progress and error states.
    @discardableResult
    public func clearCache() async throws -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return 0
        }
        var count = 0
        for file in files {
            try FileManager.default.removeItem(at: file)
            count += 1
        }
        activeProgress.removeAll()
        completedDownloads.removeAll()
        activeErrors.removeAll()
        return count
    }
}
