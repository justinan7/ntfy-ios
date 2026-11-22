import Foundation

/// Builds the strings and predicates that let iOS filter ntfy notifications per Focus.
///
/// iOS 16+ lets an app attach a `filterCriteria` string to every notification, and lets the user configure a
/// Focus filter for the app (Settings -> Focus -> [Focus] -> Focus Filters). The Focus filter hands the system an
/// `NSPredicate` (see `NotificationFocusFilter`). While that Focus is on, the system evaluates the predicate against
/// each notification's `filterCriteria`, and silences the notifications that do not match.
///
/// The system does the filtering, so the app does not need to know which Focus is active, and it does not
/// need the notification filtering entitlement.
///
/// The criteria has the format `<topic URL>|<priority>`, e.g. `https://ntfy.example.com/alerts|3`. Topic names
/// can only contain `[-_A-Za-z0-9]`, so "|" cannot appear in a topic and is safe to use as a separator.
///
/// This file is shared between the app and the notification service extension, so it must not import AppIntents.
enum FocusFilterCriteria {
    static let separator = "|"
    static let defaultPriority = 3
    static let maxPriority = 5

    /// The `filterCriteria` value for a notification
    static func criteria(baseUrl: String, topic: String, priority: Int16?) -> String {
        return "\(topicUrl(baseUrl: baseUrl, topic: topic))\(separator)\(normalizedPriority(priority))"
    }

    /// Prefix that matches the criteria of every topic on a server, e.g. `https://ntfy.example.com/`
    static func serverPrefix(baseUrl: String) -> String {
        return "\(normalizeBaseUrl(baseUrl))/"
    }

    /// Prefix that matches the criteria of exactly one topic, e.g. `https://ntfy.example.com/alerts|`. The trailing
    /// separator makes sure that "alerts" does not also match "alerts2".
    static func topicPrefix(topicUrl: String) -> String {
        return "\(topicUrl)\(separator)"
    }

    /// Suffix that matches the criteria of every notification with the given priority, e.g. `|5`
    static func prioritySuffix(priority: Int) -> String {
        return "\(separator)\(priority)"
    }

    /// Returns the predicate that the system evaluates against the `filterCriteria` of each notification. A notification
    /// alerts as usual if it is from one of the allowed servers or topics, or if its priority is at least `alwaysAllowMinPriority`.
    /// Everything else is silenced by the system for as long as the Focus is on.
    ///
    /// Returns nil if no servers or topics are selected, which means that nothing is filtered.
    static func predicate(allowedBaseUrls: [String], allowedTopicUrls: [String], alwaysAllowMinPriority: Int?) -> NSPredicate? {
        guard !allowedBaseUrls.isEmpty || !allowedTopicUrls.isEmpty else {
            return nil
        }
        var subpredicates: [NSPredicate] = []
        for baseUrl in allowedBaseUrls {
            subpredicates.append(NSPredicate(format: "SELF BEGINSWITH %@", serverPrefix(baseUrl: baseUrl)))
        }
        for allowedTopicUrl in allowedTopicUrls {
            subpredicates.append(NSPredicate(format: "SELF BEGINSWITH %@", topicPrefix(topicUrl: allowedTopicUrl)))
        }
        if let minPriority = alwaysAllowMinPriority, minPriority <= maxPriority {
            for priority in max(minPriority, 1)...maxPriority {
                subpredicates.append(NSPredicate(format: "SELF ENDSWITH %@", prioritySuffix(priority: priority)))
            }
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
    }

    /// The server may omit the priority (or send 0) for default priority messages
    private static func normalizedPriority(_ priority: Int16?) -> Int {
        guard let priority = priority, (1...maxPriority).contains(Int(priority)) else {
            return defaultPriority
        }
        return Int(priority)
    }
}
