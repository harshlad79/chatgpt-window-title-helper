import Foundation

// Research-stage identity parser, NOT connected to Restore All.
// Accept only a private, exact ChatGPT conversation route. Never log raw
// conversation IDs, use titles as IDs, or navigate on parsing alone.
struct ConversationRouteIdentity: Hashable {
    let conversationID: UUID
    let gptSlug: String?

    var canonicalURL: URL {
        let prefix = gptSlug.map { "/g/\($0)" } ?? ""
        return URL(string: "https://chatgpt.com\(prefix)/c/\(conversationID.uuidString.lowercased())")!
    }

    static func parse(_ raw: String) -> Self? {
        guard raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host == "chatgpt.com" || host == "www.chatgpt.com",
              components.user == nil, components.password == nil,
              components.port == nil, components.query == nil,
              components.fragment == nil,
              !components.percentEncodedPath.contains("%") else { return nil }

        let segments = components.path.split(
            separator: "/", omittingEmptySubsequences: false).map(String.init)
        let idText: String
        let slug: String?
        if segments.count == 3 && segments[0] == "" && segments[1] == "c" {
            idText = segments[2]
            slug = nil
        } else if segments.count == 5 && segments[0] == "" &&
                  segments[1] == "g" && segments[3] == "c" {
            guard segments[2].range(
                of: "^[A-Za-z0-9_-]{1,160}$", options: .regularExpression) != nil
            else { return nil }
            slug = segments[2]
            idText = segments[4]
        } else {
            return nil
        }
        guard idText.range(
            of: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$",
            options: .regularExpression) != nil,
              let uuid = UUID(uuidString: idText) else { return nil }
        return Self(conversationID: uuid, gptSlug: slug)
    }
}
