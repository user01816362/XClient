import Foundation
import XKit
import XKitTesting

@main
struct XKitCLI {
    static func main() async {
        let args = CommandLine.arguments

        if args.count < 2 || args.contains("--help") || args.contains("-h") {
            print("""
            ===========================================================
            XKit Command Line Tool & Verification Harness
            ===========================================================
            Usage:
              swift run XKitCLI auth-url --client-id <id> [--redirect-uri <uri>]
              swift run XKitCLI test-all
            """)
            return
        }

        let command = args[1]
        switch command {
        case "auth-url":
            do {
                guard let clientIdx = args.firstIndex(of: "--client-id"), clientIdx + 1 < args.count else {
                    print("Error: Missing --client-id <id>")
                    return
                }
                let clientId = args[clientIdx + 1]

                var redirectURI = "http://127.0.0.1:8080/callback"
                if let redirectIdx = args.firstIndex(of: "--redirect-uri"), redirectIdx + 1 < args.count {
                    redirectURI = args[redirectIdx + 1]
                }

                let pkce = try PKCE.generate()
                let scopes = "tweet.read tweet.write users.read bookmark.read bookmark.write like.read like.write offline.access"
                let url = try OAuthURLBuilder.build(
                    clientID: clientId,
                    redirectURI: redirectURI,
                    scope: scopes,
                    state: pkce.state,
                    codeChallenge: pkce.challenge
                )

                print("=== OAuth 2.0 PKCE Parameters Generated ===")
                print("Code Verifier:   \(pkce.verifier)")
                print("Code Challenge:  \(pkce.challenge)")
                print("State:           \(pkce.state)")
                print("\nAuthorize URL:")
                print(url.absoluteString)
            } catch {
                print("Failed to generate auth URL: \(error)")
            }

        case "test-all", "test-local":
            print("===========================================================")
            print("Running XKit Local Test Suite (Offline Verification)...")
            print("===========================================================")
            var passed = 0
            var failed = 0

            func runTest(_ name: String, _ block: () async throws -> Void) async {
                do {
                    try await block()
                    print("  ✓ PASS: \(name)")
                    passed += 1
                } catch {
                    print("  ✗ FAIL: \(name) — \(error)")
                    failed += 1
                }
            }

            // 1. PKCE Generation & RFC Vector
            await runTest("PKCE generation produces valid length verifier (43-128 chars)") {
                let params = try PKCE.generate()
                assert(params.verifier.count >= 43 && params.verifier.count <= 128)
                assert(!params.challenge.isEmpty)
                assert(!params.state.isEmpty)
            }

            await runTest("PKCE RFC 7636 Appendix B test vector matches expected SHA256 challenge") {
                let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
                let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
                let challenge = PKCE.makeChallenge(for: verifier)
                assert(challenge == expectedChallenge, "Challenge \(challenge) != expected \(expectedChallenge)")
            }

            // 2. OAuth URL Builder
            await runTest("OAuthURLBuilder constructs correct query components and S256 method") {
                let url = try OAuthURLBuilder.build(
                    clientID: "client_abc",
                    redirectURI: "https://app.example.com/callback",
                    scope: "tweet.read",
                    state: "state_xyz",
                    codeChallenge: "challenge_xyz"
                )
                let comp = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                assert(comp.host == "x.com")
                assert(comp.path == "/i/oauth2/authorize")
                assert(comp.queryItems?.contains(URLQueryItem(name: "client_id", value: "client_abc")) == true)
                assert(comp.queryItems?.contains(URLQueryItem(name: "code_challenge_method", value: "S256")) == true)
            }

            // 3. Transport & Mock
            await runTest("MockTransport records requests and delivers queued responses") {
                let mock = MockTransport()
                mock.enqueue(statusCode: 200, jsonString: "{\"status\": \"ok\"}")
                let response = try await mock.send(request: HTTPRequest(url: URL(string: "https://api.x.com/2/test")!))
                assert(response.statusCode == 200)
                assert(mock.recordedRequests.count == 1)
            }

            // 4. Rate Limit Parsing
            await runTest("RateLimitInfo calculates remaining limits and seconds to reset") {
                let reset = Date().addingTimeInterval(300)
                let info = RateLimitInfo(limit: 900, remaining: 150, resetDate: reset)
                assert(info.limit == 900)
                assert(info.remaining == 150)
                assert(!info.isExhausted)
                assert(info.secondsUntilReset > 0)
            }

            // 5. Users Service
            await runTest("UsersService.me parses user fixture") {
                let mock = MockTransport()
                let json = """
                {"data": {"id": "12345", "name": "Developer", "username": "dev_account", "verified": true}}
                """
                mock.enqueue(statusCode: 200, jsonString: json)
                let client = XClient(transport: mock)
                let user = try await client.users.me(token: "test_token")
                assert(user.id == "12345")
                assert(user.name == "Developer")
                assert(user.username == "dev_account")
                assert(user.verified == true)
            }

            // 6. Posts Service
            await runTest("PostsService.create creates post and decodes ID and text") {
                let mock = MockTransport()
                let json = """
                {"data": {"id": "999888", "text": "Hello world from XKit!"}}
                """
                mock.enqueue(statusCode: 201, jsonString: json)
                let client = XClient(transport: mock)
                let post = try await client.posts.create(text: "Hello world from XKit!", token: "test_token")
                assert(post.id == "999888")
                assert(post.text == "Hello world from XKit!")
            }

            // 7. Error Handling (RFC 7807 Problem Details)
            await runTest("RFC 7807 problem details decode to XKitError.apiError") {
                let mock = MockTransport()
                let json = """
                {"title": "Unauthorized", "type": "about:blank", "status": 401, "detail": "Invalid token"}
                """
                mock.enqueue(statusCode: 401, jsonString: json)
                let client = XClient(transport: mock)
                do {
                    _ = try await client.users.me(token: "bad_token")
                    assertionFailure("Should have thrown error")
                } catch let XKitError.apiError(title, detail, _) {
                    assert(title == "Unauthorized")
                    assert(detail == "Invalid token")
                }
            }

            // 8. ClientTransactionSigner & Internal Headers
            await runTest("ClientTransactionSigner generates transaction IDs and Web headers") {
                let headers = ClientTransactionSigner.defaultHeaders(
                    path: GraphQLTimelineService.searchTimelinePath,
                    guestToken: "guest_123456"
                )
                assert(headers["authorization"] == ClientTransactionSigner.publicWebBearerToken)
                assert(headers["x-guest-token"] == "guest_123456")
                assert(headers["x-client-transaction-id"] != nil)
                assert(!headers["x-client-transaction-id"]!.isEmpty)
            }

            // 9. GraphQLTimelineService Guest Token & Search
            await runTest("GraphQLTimelineService activates guest token and executes GraphQL timeline") {
                let mock = MockTransport()
                mock.enqueue(statusCode: 200, jsonString: "{\"guest_token\": \"987654321\"}")
                let client = XClient(transport: mock)
                let guestToken = try await client.graphql.activateGuestToken()
                assert(guestToken == "987654321")

                let timelineJSON = """
                {"data": [{"id": "post_1", "text": "Liquid Glass post from GraphQL"}]}
                """
                mock.enqueue(statusCode: 200, jsonString: timelineJSON)
                let timeline = try await client.graphql.fetchSearchTimeline(query: "swift", guestToken: guestToken)
                assert(timeline.data.count == 1)
                assert(timeline.data.first?.text == "Liquid Glass post from GraphQL")
            }

            // 10. GraphQLTimelineParser Nested Tree & NoteTweet Unwrapping
            await runTest("GraphQLTimelineParser unwraps real Twitter nested instructions, note_tweets, and cursors") {
                let nestedJSON = """
                {
                  "data": {
                    "search_by_raw_query": {
                      "search_timeline": {
                        "timeline": {
                          "instructions": [
                            {
                              "type": "TimelineAddEntries",
                              "entries": [
                                {
                                  "entryId": "tweet-1888888888",
                                  "content": {
                                    "entryType": "TimelineTimelineItem",
                                    "itemContent": {
                                      "itemType": "TimelineTweet",
                                      "tweet_results": {
                                        "result": {
                                          "__typename": "Tweet",
                                          "rest_id": "1888888888",
                                          "core": {
                                            "user_results": {
                                              "result": {
                                                "rest_id": "usr_real_777",
                                                "legacy": {
                                                  "name": "Swift Expert",
                                                  "screen_name": "swiftexpert",
                                                  "profile_image_url_https": "https://pbs.twimg.com/profile_images/777/avatar.jpg"
                                                }
                                              }
                                            }
                                          },
                                          "legacy": {
                                            "full_text": "Short truncated preview...",
                                            "created_at": "Mon Oct 26 12:00:00 +0000 2026",
                                            "conversation_id_str": "1888888888"
                                          },
                                          "note_tweet": {
                                            "note_tweet_results": {
                                              "result": {
                                                "text": "Full longform note tweet with liquid glass brilliance on iOS 17 and macOS!"
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                },
                                {
                                  "entryId": "cursor-bottom-nextpage-12345",
                                  "content": {
                                    "entryType": "TimelineTimelineCursor",
                                    "value": "cursor_token_page_2"
                                  }
                                }
                              ]
                            }
                          ]
                        }
                      }
                    }
                  }
                }
                """
                let parsed = GraphQLTimelineParser.parseTimeline(from: Data(nestedJSON.utf8))
                assert(parsed.posts.count == 1, "Expected 1 post, got \(parsed.posts.count)")
                assert(parsed.posts.first?.id == "1888888888")
                // Verify note_tweet longform text unwrap
                assert(parsed.posts.first?.text == "Full longform note tweet with liquid glass brilliance on iOS 17 and macOS!")
                assert(parsed.users["usr_real_777"]?.username == "swiftexpert")
                assert(parsed.users["usr_real_777"]?.name == "Swift Expert")
                assert(parsed.nextCursor == "cursor_token_page_2")
            }

            print("===========================================================")
            print("Test Summary: \(passed) passed, \(failed) failed")
            print("===========================================================")
            if failed > 0 {
                exit(1)
            }

        default:
            print("Unknown command: \(command). Use --help for usage.")
        }
    }
}
