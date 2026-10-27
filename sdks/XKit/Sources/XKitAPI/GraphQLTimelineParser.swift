//
//  GraphQLTimelineParser.swift
//  XKit
//
//  Robust parser for internal Twitter/X GraphQL timeline responses.
//  Extracts posts, nested longform note tweets, author metadata, and pagination cursors.
//  100% Swift 6 strict concurrency compliance.
//

import Foundation
import XKitModels

public struct GraphQLTimelineParser: Sendable {
    public struct ParsedTimeline: Sendable {
        public let posts: [XPost]
        public let users: [String: XUser]
        public let nextCursor: String?

        public init(posts: [XPost], users: [String: XUser], nextCursor: String?) {
            self.posts = posts
            self.users = users
            self.nextCursor = nextCursor
        }

        public var asPaginatedResponse: PaginatedResponse<XPost> {
            PaginatedResponse(data: posts, resultCount: posts.count, nextToken: nextCursor)
        }
    }

    public static func parseDate(_ string: String) -> Date? {
        let twitterDateFormatter = DateFormatter()
        twitterDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        twitterDateFormatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        if let d = twitterDateFormatter.date(from: string) {
            return d
        }

        let isoDateFormatter = ISO8601DateFormatter()
        isoDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoDateFormatter.date(from: string) {
            return d
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: string)
    }

    /// Parses raw response Data from GraphQL endpoints (SearchTimeline, UserTweets, HomeTimeline, TweetDetail)
    public static func parseTimeline(from data: Data) -> ParsedTimeline {
        // 1. Direct standard PaginatedResponse fallback (e.g. from unit tests or mocks)
        if let decoded = try? JSONDecoder().decode(PaginatedResponse<XPost>.self, from: data), !decoded.data.isEmpty {
            return ParsedTimeline(posts: decoded.data, users: [:], nextCursor: decoded.nextToken)
        }

        // 2. Direct single resource fallback
        if let decodedSingle = try? JSONDecoder().decode(SingleResourceResponse<XPost>.self, from: data) {
            return ParsedTimeline(posts: [decodedSingle.data], users: [:], nextCursor: nil)
        }

        // 3. REST v1.1 status array fallback (e.g. from /1.1/statuses/home_timeline.json)
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var posts: [XPost] = []
            var users: [String: XUser] = [:]
            for item in array {
                guard let id = item["id_str"] as? String ?? (item["id"] as? Int64).map(String.init) else { continue }
                let text = item["full_text"] as? String ?? item["text"] as? String ?? ""
                let createdAtStr = item["created_at"] as? String
                let createdAt = createdAtStr.flatMap(parseDate)
                var authorId: String? = nil

                if let userDict = item["user"] as? [String: Any],
                   let userId = userDict["id_str"] as? String ?? (userDict["id"] as? Int64).map(String.init) {
                    authorId = userId
                    let screenName = userDict["screen_name"] as? String ?? ""
                    let name = userDict["name"] as? String ?? screenName
                    let avatar = userDict["profile_image_url_https"] as? String
                    let bio = userDict["description"] as? String
                    let verified = (userDict["verified"] as? Bool) ?? false

                    let user = XUser(
                        id: userId,
                        name: name,
                        username: screenName,
                        description: bio,
                        verified: verified,
                        profileImageUrl: avatar
                    )
                    users[userId] = user
                }

                posts.append(XPost(
                    id: id,
                    text: text,
                    authorId: authorId,
                    createdAt: createdAt,
                    conversationId: item["in_reply_to_status_id_str"] as? String
                ))
            }
            if !posts.isEmpty {
                return ParsedTimeline(posts: posts, users: users, nextCursor: nil)
            }
        }

        // 4. Dynamic GraphQL JSON tree exploration
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedTimeline(posts: [], users: [:], nextCursor: nil)
        }

        var posts: [XPost] = []
        var users: [String: XUser] = [:]
        var nextCursor: String? = nil

        let instructions = extractInstructions(from: json)
        for instruction in instructions {
            guard let instructionDict = instruction as? [String: Any] else { continue }
            let type = instructionDict["type"] as? String ?? ""

            if type == "TimelineAddEntries" || type == "TimelinePinEntry" {
                if let entries = instructionDict["entries"] as? [[String: Any]] {
                    for entry in entries {
                        processEntry(entry, posts: &posts, users: &users, nextCursor: &nextCursor)
                    }
                }
                if let singleEntry = instructionDict["entry"] as? [String: Any] {
                    processEntry(singleEntry, posts: &posts, users: &users, nextCursor: &nextCursor)
                }
            }
        }

        // Also check if this is a direct TweetDetail or single TweetResultByRestId
        if posts.isEmpty {
            if let dataDict = json["data"] as? [String: Any],
               let tweetResult = (dataDict["tweetResult"] as? [String: Any])?["result"] as? [String: Any] {
                if let post = extractPost(from: tweetResult, users: &users) {
                    posts.append(post)
                }
            }
        }

        return ParsedTimeline(posts: posts, users: users, nextCursor: nextCursor)
    }

    private static func extractInstructions(from json: [String: Any]) -> [Any] {
        guard let data = json["data"] as? [String: Any] else { return [] }

        // Search Timeline: data.search_by_raw_query.search_timeline.timeline.instructions
        if let search = data["search_by_raw_query"] as? [String: Any],
           let timeline = (search["search_timeline"] as? [String: Any])?["timeline"] as? [String: Any],
           let instructions = timeline["instructions"] as? [Any] {
            return instructions
        }

        // Tweet Detail: data.threaded_conversation_with_injections_v2.instructions
        if let conversation = data["threaded_conversation_with_injections_v2"] as? [String: Any],
           let instructions = conversation["instructions"] as? [Any] {
            return instructions
        }

        // User Tweets: data.user.result.timeline_v2.timeline.instructions
        if let user = data["user"] as? [String: Any],
           let result = user["result"] as? [String: Any],
           let timelineV2 = result["timeline_v2"] as? [String: Any],
           let timeline = timelineV2["timeline"] as? [String: Any],
           let instructions = timeline["instructions"] as? [Any] {
            return instructions
        }

        // Home Timeline: data.home.home_timeline_urt.instructions
        if let home = data["home"] as? [String: Any],
           let timelineUrt = home["home_timeline_urt"] as? [String: Any],
           let instructions = timelineUrt["instructions"] as? [Any] {
            return instructions
        }

        return []
    }

    private static func processEntry(
        _ entry: [String: Any],
        posts: inout [XPost],
        users: inout [String: XUser],
        nextCursor: inout String?
    ) {
        let entryId = entry["entryId"] as? String ?? ""

        // Cursor extraction
        if entryId.starts(with: "cursor-bottom") || entryId.starts(with: "sq-cursor-bottom") {
            if let content = entry["content"] as? [String: Any],
               let value = content["value"] as? String {
                nextCursor = value
            }
            return
        }

        guard let content = entry["content"] as? [String: Any] else { return }
        let entryType = content["entryType"] as? String ?? ""

        if entryType == "TimelineTimelineItem" {
            if let itemContent = content["itemContent"] as? [String: Any],
               let tweetResults = itemContent["tweet_results"] as? [String: Any],
               let result = tweetResults["result"] as? [String: Any] {
                if let post = extractPost(from: result, users: &users) {
                    posts.append(post)
                }
            }
        } else if entryType == "TimelineTimelineModule" {
            if let items = content["items"] as? [[String: Any]] {
                for item in items {
                    if let itemDict = item["item"] as? [String: Any],
                       let itemContent = itemDict["itemContent"] as? [String: Any],
                       let tweetResults = itemContent["tweet_results"] as? [String: Any],
                       let result = tweetResults["result"] as? [String: Any] {
                        if let post = extractPost(from: result, users: &users) {
                            posts.append(post)
                        }
                    }
                }
            }
        }
    }

    private static func extractPost(
        from rawResult: [String: Any],
        users: inout [String: XUser]
    ) -> XPost? {
        var result = rawResult
        let typeName = result["__typename"] as? String ?? ""

        if typeName == "TweetWithVisibilityResults", let tweet = result["tweet"] as? [String: Any] {
            result = tweet
        }

        guard let restId = result["rest_id"] as? String ?? result["id"] as? String else {
            return nil
        }

        guard let legacy = result["legacy"] as? [String: Any] else {
            return nil
        }

        // Longform note tweet text if available, else legacy full_text
        var text = legacy["full_text"] as? String ?? ""
        if let noteTweet = result["note_tweet"] as? [String: Any],
           let noteResults = noteTweet["note_tweet_results"] as? [String: Any],
           let noteRes = noteResults["result"] as? [String: Any],
           let longText = noteRes["text"] as? String, !longText.isEmpty {
            text = longText
        }

        var authorId: String? = legacy["user_id_str"] as? String
        let createdAtStr = legacy["created_at"] as? String
        let createdAt = createdAtStr.flatMap(parseDate)
        let conversationId = legacy["conversation_id_str"] as? String

        // Extract user metadata from core.user_results.result
        if let core = result["core"] as? [String: Any],
           let userResults = core["user_results"] as? [String: Any],
           let userRes = userResults["result"] as? [String: Any] {
            let userId = userRes["rest_id"] as? String ?? authorId ?? "usr_\(restId)"
            authorId = userId

            if let userLegacy = userRes["legacy"] as? [String: Any] {
                let name = userLegacy["name"] as? String ?? "User"
                let screenName = userLegacy["screen_name"] as? String ?? "user"
                let bio = userLegacy["description"] as? String
                let verified = (userRes["is_blue_verified"] as? Bool) ?? (userLegacy["verified"] as? Bool) ?? false
                let avatarUrl = userLegacy["profile_image_url_https"] as? String

                let user = XUser(
                    id: userId,
                    name: name,
                    username: screenName,
                    description: bio,
                    verified: verified,
                    profileImageUrl: avatarUrl
                )
                users[userId] = user
            }
        }

        return XPost(
            id: restId,
            text: text,
            authorId: authorId,
            createdAt: createdAt,
            conversationId: conversationId
        )
    }

    /// Parses a single user lookup from GraphQL `UserByScreenName` or `UserByRestId`
    public static func parseUser(from data: Data) -> XUser? {
        if let direct = try? JSONDecoder().decode(SingleResourceResponse<XUser>.self, from: data) {
            return direct.data
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let userDict = dataDict["user"] as? [String: Any],
              let result = userDict["result"] as? [String: Any] else {
            return nil
        }

        let id = result["rest_id"] as? String ?? ""
        guard let legacy = result["legacy"] as? [String: Any] else { return nil }

        let name = legacy["name"] as? String ?? ""
        let screenName = legacy["screen_name"] as? String ?? ""
        let bio = legacy["description"] as? String
        let verified = (result["is_blue_verified"] as? Bool) ?? (legacy["verified"] as? Bool) ?? false
        let avatarUrl = legacy["profile_image_url_https"] as? String

        return XUser(
            id: id,
            name: name,
            username: screenName,
            description: bio,
            verified: verified,
            profileImageUrl: avatarUrl
        )
    }
}
