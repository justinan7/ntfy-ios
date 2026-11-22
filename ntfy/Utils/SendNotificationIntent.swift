import AppIntents
import Foundation

/// "Send Notification" action for the Shortcuts app and Siri. It publishes a message to one of the topics
/// the user is subscribed to, using the credentials stored for that topic's server.
///
/// The action shows up in the Shortcuts app automatically (search for "ntfy"), so it can be used in shortcuts
/// and in personal automations, e.g. "when I arrive at work, send 'Arrived' to my family topic".
@available(iOS 16.0, *)
struct SendNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Notification"
    static var description: IntentDescription? = IntentDescription(
        "Publishes a message to one of the ntfy topics you are subscribed to."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Topic")
    var topic: SubscribedTopic

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Title")
    var messageTitle: String?

    @Parameter(title: "Priority", default: .normal)
    var priority: SendNotificationPriority

    @Parameter(title: "Tags", description: "Comma-separated list of tags, e.g. warning,skull")
    var tags: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) to \(\.$topic)") {
            \.$messageTitle
            \.$priority
            \.$tags
        }
    }

    func perform() async throws -> some IntentResult {
        guard let target = topic.target else {
            throw PublishError.invalidTopic
        }
        let user = await SendNotificationStore.user(baseUrl: target.baseUrl)
        let tagList = (tags ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        try await ApiService.shared.publish(
            baseUrl: target.baseUrl,
            topic: target.topic,
            user: user,
            message: message,
            title: messageTitle,
            priority: priority.value,
            tags: tagList
        )
        return .result()
    }
}

/// Shortcuts shows this message when the action fails
@available(iOS 16.0, *)
extension PublishError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        let text = errorDescription ?? "The message could not be published."
        return "\(text)"
    }
}

@available(iOS 16.0, *)
enum SendNotificationPriority: String, AppEnum {
    case min
    case low
    case normal
    case high
    case max

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Priority"
    static var caseDisplayRepresentations: [SendNotificationPriority: DisplayRepresentation] = [
        .min: "Min",
        .low: "Low",
        .normal: "Default",
        .high: "High",
        .max: "Max"
    ]

    var value: Int {
        switch self {
        case .min: return 1
        case .low: return 2
        case .normal: return 3
        case .high: return 4
        case .max: return 5
        }
    }
}

/// A topic that the user is subscribed to. The identifier is the topic URL, e.g. https://ntfy.sh/mytopic.
@available(iOS 16.0, *)
struct SubscribedTopic: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Topic"
    static var defaultQuery = SubscribedTopicQuery()

    let id: String

    var displayRepresentation: DisplayRepresentation {
        let name = shortUrl(url: id)
        return DisplayRepresentation(title: "\(name)")
    }

    /// Splits the topic URL into base URL and topic. Topic names cannot contain "/", so the last one is the separator.
    var target: (baseUrl: String, topic: String)? {
        guard let slash = id.lastIndex(of: "/") else {
            return nil
        }
        let baseUrl = String(id[..<slash])
        let topic = String(id[id.index(after: slash)...])
        guard baseUrl.contains("://"), !topic.isEmpty else {
            return nil
        }
        return (baseUrl: baseUrl, topic: topic)
    }
}

@available(iOS 16.0, *)
struct SubscribedTopicQuery: EntityQuery {
    /// Entities are re-created from their identifiers, so that a saved shortcut keeps working without a database lookup
    func entities(for identifiers: [String]) async throws -> [SubscribedTopic] {
        return identifiers.map { SubscribedTopic(id: $0) }
    }

    func suggestedEntities() async throws -> [SubscribedTopic] {
        return await SendNotificationStore.topicUrls().map { SubscribedTopic(id: $0) }
    }
}

/// The store uses the Core Data view context, so it must be accessed on the main thread
@available(iOS 16.0, *)
enum SendNotificationStore {
    @MainActor
    static func topicUrls() -> [String] {
        let topicUrls = (Store.shared.getSubscriptions() ?? []).compactMap { subscription -> String? in
            guard let baseUrl = subscription.baseUrl, let topic = subscription.topic else {
                return nil
            }
            return topicUrl(baseUrl: baseUrl, topic: topic)
        }
        return Set(topicUrls).sorted()
    }

    @MainActor
    static func user(baseUrl: String) -> BasicUser? {
        return Store.shared.getUser(baseUrl: baseUrl)?.toBasicUser()
    }
}
