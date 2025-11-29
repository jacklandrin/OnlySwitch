//
//  String++.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Defines
import Foundation
import OSAKit

public extension String {
    @MainActor
    func runAppleScript(isShellCMD: Bool = false, with administratorPrivilege:Bool = false) async throws -> String {
        var finalCommand = self
        if isShellCMD {
            finalCommand = "do shell script \"\(self)\""
        }
        if administratorPrivilege {
            finalCommand += " with prompt \"OnlySwitch\" with administrator privileges"
        }
        print("command: \(finalCommand)")
        return try await AppleScriptExecutor.shared.execute(source: finalCommand)
    }
}

fileprivate class AppleScriptExecutor {
    static let shared = AppleScriptExecutor()
    private let queue = DispatchQueue(label: "com.onlyswitch.applescript", qos: .utility)
    
    func execute(source: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                autoreleasepool {
                    var error: NSDictionary?
                    let osaScript = OSAScript(source: source)
                    if let descriptor = osaScript.executeAndReturnError(&error) {
                        if let outputString = descriptor.stringValue {
                            print(outputString)
                            continuation.resume(returning: outputString)
                        } else if let error = error {
                            print("error:\(String(describing: error))")
                            continuation.resume(throwing: SwitchError.ScriptFailed)
                        } else {
                            continuation.resume(returning: "")
                        }
                    } else {
                        continuation.resume(throwing: SwitchError.ScriptFailed)
                    }
                }
            }
        }
    }
}

public extension String {
    
    func appendingPathComponent(string:String...) -> String {
        var result = self
        for s in string {
            result += "/\(s)"
        }
        return result
    }
    
    func convertMacAdrress() -> String {
        let upperCase = self.uppercased()
        return upperCase.replacingOccurrences(of: "-", with: ":")
    }
    
}


public extension String {

    func groups(for regexPattern: String) -> [[String]] {
        do {
            let text = self
            let regex = try NSRegularExpression(pattern: regexPattern)
            let matches = regex.matches(in: text,
                                        range: NSRange(text.startIndex..., in: text))
            return matches.map { match in
                return (0..<match.numberOfRanges).map {
                    let rangeBounds = match.range(at: $0)
                    guard let range = Range(rangeBounds, in: text) else {
                        return ""
                    }
                    return String(text[range])
                }
            }
        } catch {
            return []
        }
    }
    
    func matches(for regex: String) -> [String] {
        
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let results = regex.matches(in: self,
                                        range: NSRange(self.startIndex..., in: self))
            return results.map {
                if let range = Range($0.range, in: self) {
                    return String(self[range])
                }
                return ""
            }
        } catch let error {
            print("invalid regex: \(error.localizedDescription)")
            return []
        }
    }
}


public extension String {
    func toInteger() -> Int {
        (self as NSString).integerValue
    }
}

public extension String {

    func condenseWhitespace() -> String {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
  
}

public extension String {
    var isValidURL: Bool {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let match = detector.firstMatch(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count)) {
            // it is a link, if the match covers the whole string
            return match.range.length == self.utf16.count
        } else {
            return false
        }
    }
}

///for file and folder
public extension URL {
    var isHidden:Bool {
        return (try? resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true
    }
    
    mutating func doHide(_ hide:Bool) -> Bool {
        var resourceValues = URLResourceValues()
        resourceValues.isHidden = hide
        do {
            try setResourceValues(resourceValues)
        } catch {
            return false
        }
        return true
    }
}
