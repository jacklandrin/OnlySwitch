//
//  String++.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation

extension String {
    func runAppleScript(isShellCMD:Bool = false) -> (Bool, Any) {
        var finalCommand = self
        if isShellCMD {
            finalCommand = "do shell script \"\(self)\""
        }
        print("command:\(finalCommand)")
        var error: NSDictionary?
        if let scroptObject = NSAppleScript(source: finalCommand) {
            let descriptor = scroptObject.executeAndReturnError(&error)
            if let outputString = descriptor.stringValue {
                print(outputString)
                return (true, outputString)
            } else if error != nil {
                print("error:\(String(describing: error!))")
                return (false, "failed")
            }
        }
        return (true, "")
    }
    
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


extension String {
    
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


extension String {
    func toInteger() -> Int {
        (self as NSString).integerValue
    }
}

extension String {
  
  func condenseWhitespace() -> String {
    components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
  }
  
}
