import AppIntents
import Foundation

/// Focus filter for ntfy. This makes ntfy show up in Settings -> Focus -> [Focus] -> Focus Filters, where the user
/// can pick the servers and topics that are allowed to alert while that Focus is on, e.g. only the work server
/// during a "Work" Focus, and only the home server during a "Personal" Focus.
///
/// The filtering is done by the system: `appContext` returns a predicate, and the system evaluates it against the
/// `filterCriteria` that we set on every notification (see `FocusFilterCriteria` and `NotificationContent.swift`).
/// Notifications that do not match are silenced by the system while the Focus is on.
///
/// Note that the Focus itself must allow notifications from ntfy for this to be useful. If ntfy is not an allowed
/// app in a Focus, iOS silences everything except time-sensitive and critical notifications before the filter applies.
@available(iOS 16.0, *)
struct NotificationFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Filter Notifications"
    static var description: IntentDescription? = IntentDescription(
        "Only get alerted by the servers and topics you choose while this Focus is on. Other notifications are silenced."
    )

    @Parameter(title: "Servers", description: "All topics on these servers can alert you")
    var servers: [FocusFilterServer]?

    @Parameter(title: "Topics", description: "These topics can alert you")
    var topics: [FocusFilterTopic]?

    @Parameter(title: "Always Allow", description: "Notifications that can alert you no matter where they come from", default: .highAndMax)
    var alwaysAllow: FocusFilterAlwaysAllow

    var displayRepresentation: DisplayRepresentation {
        let names = (servers ?? []).map { $0.name } + (topics ?? []).map { $0.name }
        let allowed = names.joined(separator: ", ")
        let subtitle: LocalizedStringResource = names.isEmpty ? "All notifications" : "\(allowed)"
        return DisplayRepresentation(title: "Filter Notifications", subtitle: subtitle)
    }

    var appContext: FocusFilterAppContext {
        let predicate = FocusFilterCriteria.predicate(
            allowedBaseUrls: (servers ?? []).map { $0.id },
            allowedTopicUrls: (topics ?? []).map { $0.id },
            alwaysAllowMinPriority: alwaysAllow.minPriority
        )
        return FocusFilterAppContext(notificationFilterPredicate: predicate)
    }

    /// Called by the system when a Focus is turned on or off. There is nothing to do here, because the system
    /// applies the predicate from `appContext`. When no Focus filter is active, the parameters have their
    /// default values, so the predicate is nil and nothing is filtered.
    func perform() async throws -> some IntentResult {
        let serverIds = (servers ?? []).map { $0.id }
        let topicIds = (topics ?? []).map { $0.id }
        Log.d("NotificationFocusFilter", "Focus filter changed: servers=\(serverIds), topics=\(topicIds), alwaysAllow=\(alwaysAllow.rawValue)")
        return .result()
    }
}

/// Which notifications are allowed to alert regardless of the server/topic they were published to
@available(iOS 16.0, *)
enum FocusFilterAlwaysAllow: String, AppEnum {
    case highAndMax
    case maxOnly
    case nothing

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Priority"
    static var caseDisplayRepresentations: [FocusFilterAlwaysAllow: DisplayRepresentation] = [
        .highAndMax: "High and max priority",
        .maxOnly: "Max priority only",
        .nothing: "Nothing else"
    ]

    var minPriority: Int? {
        switch self {
        case .highAndMax: return 4
        case .maxOnly: return 5
        case .nothing: return nil
        }
    }
}

/// A server that the user is subscribed to at least one topic on. The identifier is the normalized base URL.
@available(iOS 16.0, *)
struct FocusFilterServer: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Server"
    static var defaultQuery = FocusFilterServerQuery()

    let id: String

    var name: String {
        return shortUrl(url: id)
    }

    var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 16.0, *)
struct FocusFilterServerQuery: EntityQuery {
    /// Entities are re-created from their identifiers without consulting the store, so that a configured Focus filter
    /// keeps working even if the system resolves it while the database is not readable.
    func entities(for identifiers: [String]) async throws -> [FocusFilterServer] {
        return identifiers.map { FocusFilterServer(id: $0) }
    }

    func suggestedEntities() async throws -> [FocusFilterServer] {
        let subscriptions = await FocusFilterSubscriptions.load()
        let baseUrls = Set(subscriptions.map { $0.baseUrl })
        return baseUrls.sorted().map { FocusFilterServer(id: $0) }
    }
}

/// A topic that the user is subscribed to. The identifier is the topic URL, e.g. https://ntfy.sh/mytopic.
@available(iOS 16.0, *)
struct FocusFilterTopic: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Topic"
    static var defaultQuery = FocusFilterTopicQuery()

    let id: String

    var name: String {
        return shortUrl(url: id)
    }

    var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 16.0, *)
struct FocusFilterTopicQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FocusFilterTopic] {
        return identifiers.map { FocusFilterTopic(id: $0) }
    }

    func suggestedEntities() async throws -> [FocusFilterTopic] {
        let subscriptions = await FocusFilterSubscriptions.load()
        let topicUrls = Set(subscriptions.map { topicUrl(baseUrl: $0.baseUrl, topic: $0.topic) })
        return topicUrls.sorted().map { FocusFilterTopic(id: $0) }
    }
}

@available(iOS 16.0, *)
enum FocusFilterSubscriptions {
    /// Loads the subscribed topics. The store uses the Core Data view context, so this must run on the main thread.
    @MainActor
    static func load() -> [(baseUrl: String, topic: String)] {
        return (Store.shared.getSubscriptions() ?? []).compactMap { subscription in
            guard let baseUrl = subscription.baseUrl, let topic = subscription.topic else {
                return nil
            }
            return (baseUrl: normalizeBaseUrl(baseUrl), topic: topic)
        }
    }
}
