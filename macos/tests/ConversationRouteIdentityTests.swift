import Foundation

@main
struct ConversationRouteIdentityTests {
    static func main() {
        let id = "12345678-1234-1234-1234-123456789abc"
        let good: [(String, String, String?)] = [
            ("https://chatgpt.com/c/\(id)", "https://chatgpt.com/c/\(id)", nil),
            ("https://www.chatgpt.com/c/\(id)", "https://chatgpt.com/c/\(id)", nil),
            ("HTTPS://CHATGPT.COM/c/\(id)", "https://chatgpt.com/c/\(id)", nil),
            ("https://chatgpt.com/g/g-p-abc_123/c/\(id)", "https://chatgpt.com/g/g-p-abc_123/c/\(id)", "g-p-abc_123")
        ]
        let bad = [
            "http://chatgpt.com/c/\(id)",
            "https://evil.example/c/\(id)",
            "https://chatgpt.com.evil.example/c/\(id)",
            "https://user@chatgpt.com/c/\(id)",
            "https://chatgpt.com:443/c/\(id)",
            "https://chatgpt.com/c/\(id)?token=secret",
            "https://chatgpt.com/c/\(id)#fragment",
            "https://chatgpt.com/c/\(id)/extra",
            "https://chatgpt.com/c/\(id)/",
            "https://chatgpt.com/c/not-an-id",
            "https://chatgpt.com/c/12345678123412341234123456789abc",
            "https://chatgpt.com/g/../c/\(id)",
            "https://chatgpt.com/g/a%2Fb/c/\(id)",
            "https://chatgpt.com/g//c/\(id)",
            "https://chatgpt.com/g/a/c/\(id)/extra",
            "https://chatgpt.com/g/a/c/not-an-id",
            "https://chatgpt.com/share/\(id)",
            " https://chatgpt.com/c/\(id)",
            "https://chatgpt.com/c/\(id) ",
            "codex://threads/\(id)"
        ]
        var passed = 0
        for (input, canonical, slug) in good {
            guard let identity = ConversationRouteIdentity.parse(input),
                  identity.canonicalURL.absoluteString == canonical,
                  identity.gptSlug == slug else {
                fatalError("valid route rejected or canonicalized incorrectly")
            }
            passed += 1
        }
        for input in bad {
            guard ConversationRouteIdentity.parse(input) == nil else {
                fatalError("invalid route accepted")
            }
            passed += 1
        }
        let first = ConversationRouteIdentity.parse(good[0].0)!
        let duplicate = ConversationRouteIdentity.parse(good[1].0)!
        precondition(first == duplicate)
        passed += 1
        print("ConversationRouteIdentity: \(passed) assertions PASS")
    }
}
