import Foundation

actor CodexAppServerClient {
    func fetch() async throws -> CodexUsageSnapshot {
        guard let executableURL = executableURL() else { throw CodexUsageError.unsupported }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        defer {
            input.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        try write([
            "id": 1,
            "method": "initialize",
            "params": ["clientInfo": ["name": "OnlySwitch", "version": "1.0"]]
        ], to: input)
        try write(["method": "initialized", "params": [:]], to: input)
        try write(["id": 2, "method": "account/read", "params": [:]], to: input)
        try write(["id": 3, "method": "account/rateLimits/read", "params": [:]], to: input)

        var messages: [Int: [String: Any]] = [:]
        for try await line in output.fileHandleForReading.bytes.lines {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? Int else { continue }
            messages[id] = object
            if messages[2] != nil && messages[3] != nil { break }
        }

        guard let account = messages[2], let rateLimits = messages[3] else {
            throw CodexUsageError.signedOut
        }
        return Self.snapshot(account: account, rateLimits: rateLimits)
    }

    private func executableURL() -> URL? {
        let fileManager = FileManager.default
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        let paths = pathEntries.map { URL(fileURLWithPath: String($0)).appending(path: "codex") } + [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
        ]
        return paths.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    private func write(_ object: [String: Any], to input: Pipe) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private static func snapshot(account: [String: Any], rateLimits: [String: Any]) -> CodexUsageSnapshot {
        let accountResult = account["result"] as? [String: Any] ?? [:]
        let limitsResult = rateLimits["result"] as? [String: Any] ?? [:]
        let email = firstString(named: "email", in: accountResult)
        let plan = firstString(named: "planType", in: limitsResult)
            ?? firstString(named: "plan_type", in: limitsResult)
            ?? firstString(named: "plan", in: accountResult)
        let primary = window(named: "primary", in: limitsResult) ?? window(named: "primary_window", in: limitsResult)
        let secondary = window(named: "secondary", in: limitsResult) ?? window(named: "secondary_window", in: limitsResult)

        return CodexUsageSnapshot(
            account: .init(email: email, plan: plan?.capitalized),
            session: primary,
            weekly: secondary,
            resetCredits: .unavailable,
            creditBalance: creditBalance(in: limitsResult),
            source: .cli,
            fetchedAt: .now
        )
    }

    private static func window(named name: String, in object: [String: Any]) -> CodexQuotaWindow? {
        guard let values = dictionary(named: name, in: object) else { return nil }
        let used = number(named: "usedPercent", in: values)
            ?? number(named: "used_percent", in: values)
            ?? 100
        let resetSeconds = number(named: "resetsAt", in: values)
            ?? number(named: "reset_at", in: values)
            ?? number(named: "resets_at", in: values)
        return CodexQuotaWindow(
            remainingPercent: CodexQuotaWindow.remainingPercent(fromUsedPercent: used),
            resetAt: resetSeconds.map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func firstString(named name: String, in object: [String: Any]) -> String? {
        if let value = object[name] as? String { return value }
        for value in object.values {
            if let nested = value as? [String: Any], let found = firstString(named: name, in: nested) { return found }
        }
        return nil
    }

    private static func number(named name: String, in object: [String: Any]) -> Double? {
        if let value = object[name] as? Double { return value }
        if let value = object[name] as? Int { return Double(value) }
        if let value = object[name] as? String { return Double(value) }
        for value in object.values {
            if let nested = value as? [String: Any], let found = number(named: name, in: nested) { return found }
        }
        return nil
    }

    private static func bool(named name: String, in object: [String: Any]) -> Bool? {
        if let value = object[name] as? Bool { return value }
        for value in object.values {
            if let nested = value as? [String: Any], let found = bool(named: name, in: nested) { return found }
        }
        return nil
    }

    private static func dictionary(named name: String, in object: [String: Any]) -> [String: Any]? {
        if let value = object[name] as? [String: Any] { return value }
        for value in object.values {
            if let nested = value as? [String: Any], let found = dictionary(named: name, in: nested) { return found }
        }
        return nil
    }

    private static func creditBalance(in object: [String: Any]) -> CodexCreditBalance {
        if bool(named: "unlimited", in: object) == true { return .unlimited }
        let values = dictionary(named: "credits", in: object) ?? object
        let remaining = number(named: "balance", in: values) ?? number(named: "remaining_balance", in: values)
        let limit = number(named: "monthlyLimit", in: values)
            ?? number(named: "monthly_limit", in: values)
            ?? number(named: "credit_limit", in: values)
        guard let remaining else { return .unavailable }
        return .available(remaining: remaining, limit: limit, unit: "credits")
    }
}
