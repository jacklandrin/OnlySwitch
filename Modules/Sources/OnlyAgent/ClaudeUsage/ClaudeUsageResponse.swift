import Foundation
import CoreFoundation

enum ClaudeUsageResponse {
    static func decode(_ data: Data, account: ClaudeUsageAccount, fetchedAt: Date) throws -> ClaudeUsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeUsageError.invalidResponse }
        var models: [String: ClaudeModelUsage] = [:]
        for key in root.keys.sorted() where key.hasPrefix("seven_day_") {
            guard let quota = window(root[key]) else { continue }
            let suffix = String(key.dropFirst("seven_day_".count))
            models[suffix] = .init(id: key, name: suffix.replacingOccurrences(of: "_", with: " ").capitalized, quota: quota)
        }
        for entry in root["limits"] as? [[String: Any]] ?? [] {
            guard entry["kind"] as? String == "weekly_scoped", entry["group"] as? String == "weekly",
                  let scope = entry["scope"] as? [String: Any], let model = scope["model"] as? [String: Any],
                  let id = model["id"] as? String, !id.isEmpty, let quota = window(entry, percentKey: "percent") else { continue }
            let suffix = id.hasPrefix("seven_day_") ? String(id.dropFirst("seven_day_".count)) : id
            models[suffix] = .init(id: "seven_day_" + suffix, name: model["display_name"] as? String ?? suffix.capitalized, quota: quota)
        }
        let extra = (root["extra_usage"] as? [String: Any]).flatMap { value -> ClaudeExtraUsage? in
            guard let enabled = value["is_enabled"] as? Bool else { return nil }
            // The OAuth endpoint reports spending in cents, including Enterprise plans.
            return .init(isEnabled: enabled, used: nonnegativeNumber(value["used_credits"]).map { $0 / 100 }, limit: nonnegativeNumber(value["monthly_limit"]).map { $0 / 100 }, currency: value["currency"] as? String, utilization: nonnegativeNumber(value["utilization"]).map { min($0, 100) })
        }
        return .init(account: account, session: window(root["five_hour"]), weekly: window(root["seven_day"]), models: models.values.sorted { $0.id < $1.id }, extraUsage: extra, fetchedAt: fetchedAt)
    }

    private static func window(_ raw: Any?, percentKey: String = "utilization") -> ClaudeQuotaWindow? {
        guard let value = raw as? [String: Any], let used = number(value[percentKey]), let remaining = ClaudeQuotaWindow.remainingPercent(fromUsedPercent: used) else { return nil }
        return .init(remainingPercent: remaining, resetAt: date(value["resets_at"] as? String))
    }

    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func nonnegativeNumber(_ value: Any?) -> Double? {
        guard let value = number(value), value >= 0 else { return nil }
        return value
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
