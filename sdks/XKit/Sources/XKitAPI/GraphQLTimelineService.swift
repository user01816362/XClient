//
//  GraphQLTimelineService.swift
//  XKit
//
//  Reverse-engineered internal GraphQL and guest API service for X.
//  Extracted from X iOS App snapshot and verified web signatures.
//  100% Swift 6 strict concurrency compliance.
//

import Foundation
import XKitModels
import XKitTransport

public struct GraphQLTimelineService: Sendable {
    private let transport: HTTPTransport

    public static let searchTimelinePath = "/graphql/nK1dw4oV3k4w5TdtcAdSww/SearchTimeline"
    public static let tweetDetailPath = "/graphql/3XDB26fBve-MmjHaWTUZxA/TweetDetail"
    public static let userTweetsPath = "/graphql/WmvfySbQ0FeY1zk4HU_5ow/UserTweets"
    public static let userByScreenNamePath = "/i/api/graphql/oUZZZ8Oddwxs8Cd3iW3UEA/UserByScreenName"
    public static let favoriteTweetPath = "/graphql/lI07N6Otwv1PhnEgXILMlh/FavoriteTweet"
    public static let unfavoriteTweetPath = "/graphql/ZYKfl-CLN6lAwQUMrxDqng/UnfavoriteTweet"
    public static let createRetweetPath = "/graphql/ojPdsfoiqIQdmvId3qWblo/CreateRetweet"
    public static let guestActivatePath = "/1.1/guest/activate.json"

    /// Canonical standard features payload sent by Twitter web and mobile clients
    public static var standardFeatures: [String: Bool] {
        [
            "responsive_web_graphql_exclude_directive_enabled": true,
            "verified_phone_label_enabled": false,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "tweetypie_unmention_optimization_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "rweb_video_timestamps_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": true,
            "responsive_web_media_download_video_enabled": false,
            "responsive_web_enhance_cards_enabled": false
        ]
    }

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    /// Activates an anonymous guest session token using the public web bearer token.
    public func activateGuestToken() async throws -> String {
        guard let url = URL(string: "https://api.x.com\(Self.guestActivatePath)") else {
            throw XKitError.invalidURL
        }

        let headers = ClientTransactionSigner.defaultHeaders(
            path: Self.guestActivatePath,
            method: "POST"
        )

        let request = HTTPRequest(url: url, method: .post, headers: headers, body: nil)
        let response = try await transport.send(request: request)

        guard response.statusCode == 200, let data = response.data else {
            throw XKitError.httpError(statusCode: response.statusCode, data: response.data)
        }

        struct GuestResponse: Codable {
            let guest_token: String
        }

        let decoded = try JSONDecoder().decode(GuestResponse.self, from: data)
        return decoded.guest_token
    }

    /// Queries the search timeline and unwraps both posts and author profiles.
    public func fetchSearchTimelineParsed(
        query: String,
        guestToken: String? = nil,
        authToken: String? = nil,
        csrfToken: String? = nil,
        count: Int = 20,
        cursor: String? = nil
    ) async throws -> GraphQLTimelineParser.ParsedTimeline {
        var components = URLComponents(string: "https://api.x.com\(Self.searchTimelinePath)")

        var variables: [String: Any] = [
            "rawQuery": query,
            "count": count,
            "querySource": "typed_query",
            "product": "Latest"
        ]
        if let cursor = cursor, !cursor.isEmpty {
            variables["cursor"] = cursor
        }

        let variablesData = try JSONSerialization.data(withJSONObject: variables)
        let featuresData = try JSONSerialization.data(withJSONObject: Self.standardFeatures)

        guard let variablesString = String(data: variablesData, encoding: .utf8),
              let featuresString = String(data: featuresData, encoding: .utf8) else {
            throw XKitError.invalidURL
        }

        components?.queryItems = [
            URLQueryItem(name: "variables", value: variablesString),
            URLQueryItem(name: "features", value: featuresString)
        ]

        guard let url = components?.url else {
            throw XKitError.invalidURL
        }

        let headers = ClientTransactionSigner.defaultWebSessionHeaders(
            path: Self.searchTimelinePath,
            method: "GET",
            authToken: authToken,
            csrfToken: csrfToken,
            guestToken: guestToken
        )

        let request = HTTPRequest(url: url, method: .get, headers: headers)
        let response = try await transport.send(request: request)

        guard (200..<300).contains(response.statusCode) else {
            throw XKitError.httpError(statusCode: response.statusCode, data: response.data)
        }

        guard let data = response.data else {
            return GraphQLTimelineParser.ParsedTimeline(posts: [], users: [:], nextCursor: nil)
        }

        return GraphQLTimelineParser.parseTimeline(from: data)
    }

    /// Queries the search timeline using reverse-engineered GraphQL query parameters.
    public func fetchSearchTimeline(
        query: String,
        guestToken: String? = nil,
        authToken: String? = nil,
        csrfToken: String? = nil,
        count: Int = 20,
        cursor: String? = nil
    ) async throws -> PaginatedResponse<XPost> {
        let parsed = try await fetchSearchTimelineParsed(
            query: query,
            guestToken: guestToken,
            authToken: authToken,
            csrfToken: csrfToken,
            count: count,
            cursor: cursor
        )
        return parsed.asPaginatedResponse
    }

    /// Fetches single tweet details with rich media, conversation threads, and replies.
    public func fetchTweetDetail(
        tweetId: String,
        guestToken: String? = nil,
        authToken: String? = nil,
        csrfToken: String? = nil
    ) async throws -> SingleResourceResponse<XPost> {
        var components = URLComponents(string: "https://api.x.com\(Self.tweetDetailPath)")

        let variables: [String: Any] = [
            "focalTweetId": tweetId,
            "with_rux_injections": false,
            "includePromotedContent": false,
            "withCommunity": true
        ]

        let variablesData = try JSONSerialization.data(withJSONObject: variables)
        let featuresData = try JSONSerialization.data(withJSONObject: Self.standardFeatures)

        guard let variablesString = String(data: variablesData, encoding: .utf8),
              let featuresString = String(data: featuresData, encoding: .utf8) else {
            throw XKitError.invalidURL
        }

        components?.queryItems = [
            URLQueryItem(name: "variables", value: variablesString),
            URLQueryItem(name: "features", value: featuresString)
        ]

        guard let url = components?.url else {
            throw XKitError.invalidURL
        }

        let headers = ClientTransactionSigner.defaultWebSessionHeaders(
            path: Self.tweetDetailPath,
            method: "GET",
            authToken: authToken,
            csrfToken: csrfToken,
            guestToken: guestToken
        )

        let request = HTTPRequest(url: url, method: .get, headers: headers)
        let response = try await transport.send(request: request)

        guard (200..<300).contains(response.statusCode) else {
            throw XKitError.httpError(statusCode: response.statusCode, data: response.data)
        }

        if let data = response.data {
            let parsed = GraphQLTimelineParser.parseTimeline(from: data)
            if let post = parsed.posts.first(where: { $0.id == tweetId }) ?? parsed.posts.first {
                return SingleResourceResponse(data: post)
            }
        }

        throw XKitError.httpError(statusCode: response.statusCode, data: response.data)
    }

    /// Fetches a user's recent tweets via GraphQL UserTweets endpoint.
    public func fetchUserTweets(
        userId: String,
        guestToken: String? = nil,
        authToken: String? = nil,
        csrfToken: String? = nil,
        count: Int = 20,
        cursor: String? = nil
    ) async throws -> GraphQLTimelineParser.ParsedTimeline {
        var components = URLComponents(string: "https://api.x.com\(Self.userTweetsPath)")

        var variables: [String: Any] = [
            "userId": userId,
            "count": count,
            "includePromotedContent": false,
            "withQuickPromoteEligibilityTweetFields": true,
            "withVoice": true,
            "withV2Timeline": true
        ]
        if let cursor = cursor, !cursor.isEmpty {
            variables["cursor"] = cursor
        }

        let variablesData = try JSONSerialization.data(withJSONObject: variables)
        let featuresData = try JSONSerialization.data(withJSONObject: Self.standardFeatures)

        guard let variablesString = String(data: variablesData, encoding: .utf8),
              let featuresString = String(data: featuresData, encoding: .utf8) else {
            throw XKitError.invalidURL
        }

        components?.queryItems = [
            URLQueryItem(name: "variables", value: variablesString),
            URLQueryItem(name: "features", value: featuresString)
        ]

        guard let url = components?.url else {
            throw XKitError.invalidURL
        }

        let headers = ClientTransactionSigner.defaultWebSessionHeaders(
            path: Self.userTweetsPath,
            method: "GET",
            authToken: authToken,
            csrfToken: csrfToken,
            guestToken: guestToken
        )

        let request = HTTPRequest(url: url, method: .get, headers: headers)
        let response = try await transport.send(request: request)

        guard (200..<300).contains(response.statusCode), let data = response.data else {
            throw XKitError.httpError(statusCode: response.statusCode, data: response.data)
        }

        return GraphQLTimelineParser.parseTimeline(from: data)
    }

    /// Looks up user information by username / screen_name via GraphQL.
    public func fetchUserByScreenName(
        screenName: String,
        guestToken: String? = nil,
        authToken: String? = nil,
        csrfToken: String? = nil
    ) async throws -> XUser {
        var components = URLComponents(string: "https://x.com\(Self.userByScreenNamePath)")

        let variables: [String: Any] = [
            "screen_name": screenName,
            "withSafetyModeUserFields": true
        ]

        let variablesData = try JSONSerialization.data(withJSONObject: variables)
        let featuresData = try JSONSerialization.data(withJSONObject: Self.standardFeatures)

        guard let variablesString = String(data: variablesData, encoding: .utf8),
              let featuresString = String(data: featuresData, encoding: .utf8) else {
            throw XKitError.invalidURL
        }

        components?.queryItems = [
            URLQueryItem(name: "variables", value: variablesString),
            URLQueryItem(name: "features", value: featuresString)
        ]

        guard let url = components?.url else {
            throw XKitError.invalidURL
        }

        let headers = ClientTransactionSigner.defaultWebSessionHeaders(
            path: Self.userByScreenNamePath,
            method: "GET",
            authToken: authToken,
            csrfToken: csrfToken,
            guestToken: guestToken
        )

        let request = HTTPRequest(url: url, method: .get, headers: headers)
        let response = try await transport.send(request: request)

        guard (200..<300).contains(response.statusCode), let data = response.data else {
            throw XKitError.httpError(statusCode: response.statusCode, data: response.data)
        }

        if let user = GraphQLTimelineParser.parseUser(from: data) {
            return user
        }

        throw XKitError.apiError(title: "User Not Found", detail: "Could not parse user for @\(screenName)", type: nil)
    }

    /// Likes / favorites a tweet using an authenticated session.
    public func likeTweet(
        tweetId: String,
        authToken: String,
        csrfToken: String
    ) async throws -> Bool {
        guard let url = URL(string: "https://api.x.com\(Self.favoriteTweetPath)") else {
            throw XKitError.invalidURL
        }

        let body: [String: Any] = [
            "variables": ["tweet_id": tweetId]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let headers = ClientTransactionSigner.defaultWebSessionHeaders(
            path: Self.favoriteTweetPath,
            method: "POST",
            authToken: authToken,
            csrfToken: csrfToken
        )

        let request = HTTPRequest(url: url, method: .post, headers: headers, body: bodyData)
        let response = try await transport.send(request: request)
        return (200..<300).contains(response.statusCode)
    }

    /// Retweets a post using an authenticated session.
    public func retweet(
        tweetId: String,
        authToken: String,
        csrfToken: String
    ) async throws -> Bool {
        guard let url = URL(string: "https://api.x.com\(Self.createRetweetPath)") else {
            throw XKitError.invalidURL
        }

        let body: [String: Any] = [
            "variables": ["tweet_id": tweetId]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let headers = ClientTransactionSigner.defaultWebSessionHeaders(
            path: Self.createRetweetPath,
            method: "POST",
            authToken: authToken,
            csrfToken: csrfToken
        )

        let request = HTTPRequest(url: url, method: .post, headers: headers, body: bodyData)
        let response = try await transport.send(request: request)
        return (200..<300).contains(response.statusCode)
    }
}
