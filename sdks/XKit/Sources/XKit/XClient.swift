import Foundation
@_exported import XKitModels
@_exported import XKitTransport
@_exported import XKitAuth
@_exported import XKitAPI

/// Unified client façade for interacting with the official X API v2.
public final class XClient: Sendable {
    public let transport: HTTPTransport
    public let users: UsersService
    public let posts: PostsService
    public let timelines: TimelinesService
    public let bookmarks: BookmarksService
    public let graphql: GraphQLTimelineService

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
        self.users = UsersService(transport: transport)
        self.posts = PostsService(transport: transport)
        self.timelines = TimelinesService(transport: transport)
        self.bookmarks = BookmarksService(transport: transport)
        self.graphql = GraphQLTimelineService(transport: transport)
    }
}
