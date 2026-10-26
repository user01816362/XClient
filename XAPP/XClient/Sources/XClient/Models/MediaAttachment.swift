import Foundation

/// Supported media attachment formats for post cards and media grid rendering.
public enum MediaType: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case photo
    case video
    case animatedGif
}

/// Represents an embedded media asset (photo or video) attached to a post.
public struct MediaAttachment: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let id: String
    public let url: URL
    public let previewUrl: URL?
    public let type: MediaType
    public let width: Double?
    public let height: Double?
    public let altText: String?
    public let durationSeconds: Double?

    public init(
        id: String,
        url: URL,
        previewUrl: URL? = nil,
        type: MediaType = .photo,
        width: Double? = nil,
        height: Double? = nil,
        altText: String? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.url = url
        self.previewUrl = previewUrl
        self.type = type
        self.width = width
        self.height = height
        self.altText = altText
        self.durationSeconds = durationSeconds
    }

    /// Calculated aspect ratio (width / height) for layout containers. Defaults to 16:9 if unspecified.
    public var aspectRatio: Double {
        guard let width, let height, height > 0 else { return 16.0 / 9.0 }
        return width / height
    }

    // MARK: - Preview Fixtures
    public static let samplePhoto = MediaAttachment(
        id: "media_photo_01",
        url: URL(string: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=1200&h=800&q=80")!,
        previewUrl: URL(string: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=400&h=267&q=80"),
        type: .photo,
        width: 1200,
        height: 800,
        altText: "Abstract fluid liquid glass background with iridescent lighting"
    )

    public static let sampleVideo = MediaAttachment(
        id: "media_video_01",
        url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
        previewUrl: URL(string: "https://images.unsplash.com/photo-1536240478700-b869070f9279?auto=format&fit=crop&w=1200&h=675&q=80"),
        type: .video,
        width: 1920,
        height: 1080,
        altText: "Video playback demonstration clip",
        durationSeconds: 42.5
    )
}
