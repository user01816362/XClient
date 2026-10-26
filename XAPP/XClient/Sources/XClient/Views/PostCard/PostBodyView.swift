//
//  PostBodyView.swift
//  XClient
//
//  Rich post body rendering with entity parser detecting #hashtags, @mentions,
//  and web URLs, interactive link tap handling, and NoteTweet expansion.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI

// MARK: - Post Entity Models

public enum PostEntityType: Sendable, Equatable, Hashable {
    case mention(username: String)
    case hashtag(tag: String)
    case url(url: URL, displayString: String)
}

public struct PostEntitySpan: Sendable, Equatable, Hashable {
    public let type: PostEntityType
    public let range: Range<String.Index>
    public let text: String

    public init(type: PostEntityType, range: Range<String.Index>, text: String) {
        self.type = type
        self.range = range
        self.text = text
    }
}

/// Pure-Swift thread-safe entity parser.
public struct PostEntityParser: Sendable {
    public static func parse(text: String) -> [PostEntitySpan] {
        guard !text.isEmpty else { return [] }

        var spans: [PostEntitySpan] = []

        // 1. URLs with valid host detection
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = detector.matches(in: text, options: [], range: nsRange)
            for match in matches {
                guard let range = Range(match.range, in: text),
                      let url = match.url,
                      let host = url.host,
                      !host.isEmpty else { continue }
                let rawText = String(text[range])
                spans.append(PostEntitySpan(type: .url(url: url, displayString: rawText), range: range, text: rawText))
            }
        }

        // 2. Mentions (@username)
        let mentionPattern = #"(?<=^|[\s\(\[\{])@([a-zA-Z0-9_]{1,15})\b"#
        if let regex = try? NSRegularExpression(pattern: mentionPattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)
            for match in matches {
                guard let fullRange = Range(match.range, in: text),
                      let groupRange = Range(match.range(at: 1), in: text) else { continue }
                // Avoid overlap with existing URL spans
                if !spans.contains(where: { $0.range.overlaps(fullRange) }) {
                    let username = String(text[groupRange])
                    spans.append(PostEntitySpan(type: .mention(username: username), range: fullRange, text: String(text[fullRange])))
                }
            }
        }

        // 3. Hashtags (#tag)
        let hashtagPattern = #"(?<=^|[\s\(\[\{])#([\p{L}0-9_]+)"#
        if let regex = try? NSRegularExpression(pattern: hashtagPattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)
            for match in matches {
                guard let fullRange = Range(match.range, in: text),
                      let groupRange = Range(match.range(at: 1), in: text) else { continue }
                if !spans.contains(where: { $0.range.overlaps(fullRange) }) {
                    let tag = String(text[groupRange])
                    spans.append(PostEntitySpan(type: .hashtag(tag: tag), range: fullRange, text: String(text[fullRange])))
                }
            }
        }

        return spans.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Builds AttributedString with customized link attributes for SwiftUI Text rendering.
    public static func makeAttributedString(text: String, accentColor: Color) -> AttributedString {
        var attr = AttributedString(text)
        let spans = parse(text: text)

        for span in spans {
            guard let attrRange = Range(span.range, in: attr) else { continue }
            switch span.type {
            case .mention(let username):
                attr[attrRange].foregroundColor = accentColor
                attr[attrRange].font = Typography.postTag
                let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
                attr[attrRange].link = URL(string: "xclient://user/\(encoded)")
            case .hashtag(let tag):
                attr[attrRange].foregroundColor = accentColor
                attr[attrRange].font = Typography.postTag
                let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
                attr[attrRange].link = URL(string: "xclient://hashtag/\(encoded)")
            case .url(let url, _):
                attr[attrRange].foregroundColor = accentColor
                attr[attrRange].font = Typography.postBody
                attr[attrRange].link = url
                attr[attrRange].underlineStyle = .single
            }
        }
        return attr
    }
}

/// Dedicated observable state managing expansion for NoteTweets.
@MainActor
final class PostBodyExpansionState: ObservableObject {
    @Published var isExpanded: Bool = false
}

/// View rendering formatted body text, active entity links, and expandable NoteTweet content.
@MainActor
public struct PostBodyView: View {
    @Environment(\.colorPalette) private var palette

    public let text: String
    public let isNoteTweet: Bool
    public var onMentionTap: ((String) -> Void)?
    public var onHashtagTap: ((String) -> Void)?
    public var onURLTap: ((URL) -> Void)?

    @StateObject private var expansionState = PostBodyExpansionState()

    public init(
        text: String,
        isNoteTweet: Bool = false,
        onMentionTap: ((String) -> Void)? = nil,
        onHashtagTap: ((String) -> Void)? = nil,
        onURLTap: ((URL) -> Void)? = nil
    ) {
        self.text = text
        self.isNoteTweet = isNoteTweet
        self.onMentionTap = onMentionTap
        self.onHashtagTap = onHashtagTap
        self.onURLTap = onURLTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let isExpanded = expansionState.isExpanded
            let displayText = (!isExpanded && isNoteTweet) ? String(text.prefix(280)) + "…" : text
            let attributed = PostEntityParser.makeAttributedString(text: displayText, accentColor: palette.accent)

            Text(attributed)
                .postBodyStyle()
                .lineLimit(isExpanded ? nil : (isNoteTweet ? 6 : nil))
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "xclient" {
                        if url.host == "user" {
                            let username = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            onMentionTap?(username)
                            return .handled
                        } else if url.host == "hashtag" {
                            let tag = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            onHashtagTap?(tag)
                            return .handled
                        }
                    } else {
                        onURLTap?(url)
                        return .systemAction
                    }
                    return .handled
                })

            if isNoteTweet {
                Button(action: toggleExpansion) {
                    Text(isExpanded ? "Show less" : "Show more")
                        .font(Typography.actionButton)
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            expansionState.isExpanded.toggle()
        }
    }
}
