import Foundation

/// Unified skill parsing and execution
protocol SkillParserDelegate: AnyObject {
    func onSkill(_ skillName: String, params: [String: String])
}

struct SkillParser {
    static let skillPattern = #"\[\[skill:(\w+)\|([^\]]*)\]\]"#

    /// Parse skills from string and execute them, returning cleaned string
    static func parseAndExecute(
        from text: String,
        delegate: SkillParserDelegate
    ) -> String {
        var result = text

        let regex = try! NSRegularExpression(pattern: skillPattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches {
            guard let skillRange = Range(match.range(at: 1), in: text),
                  let paramsRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let skillName = String(text[skillRange])
            let paramsStr = String(text[paramsRange])
            let params = parseParams(paramsStr)

            delegate.onSkill(skillName, params: params)
        }

        // Remove all skill markers
        result = regex.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )

        return result
    }

    /// Parse skills from buffer in-place, returning list of removed ranges
    static func parseAndRemove(
        from buffer: inout String,
        delegate: SkillParserDelegate
    ) {
        let regex = try! NSRegularExpression(pattern: skillPattern)
        let text = buffer
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches.reversed() {
            guard let skillRange = Range(match.range(at: 1), in: text),
                  let paramsRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let skillName = String(text[skillRange])
            let paramsStr = String(text[paramsRange])
            let params = parseParams(paramsStr)

            delegate.onSkill(skillName, params: params)

            // Remove from end to start (reversed iteration)
            if let fullRange = Range(match.range, in: text) {
                buffer.removeSubrange(fullRange)
            }
        }
    }

    private static func parseParams(_ paramsStr: String) -> [String: String] {
        var params: [String: String] = [:]
        let parts = paramsStr.split(separator: "&")

        for part in parts {
            let keyValue = part.split(separator: "=", maxSplits: 1)
            if keyValue.count == 2 {
                let key = String(keyValue[0]).trimmingCharacters(in: .whitespaces)
                let value = String(keyValue[1]).trimmingCharacters(in: .whitespaces)
                params[key] = value
            }
        }

        return params
    }
}
