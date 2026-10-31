import Foundation

func redactOriginalLog(_ text: String) -> String {
    var value = text.replacingOccurrences(of: #"(?i)(Bearer\s+)[^\s\"'<>]+"#, with: "$1[redacted]", options: .regularExpression)
    value = value.replacingOccurrences(
        of: #"(?i)((?:access[_-]?token|infoToken|token|password|passwd|cuid|puid|nickname|username|userId|sdk_openid|phone|mobile|captcha|verification[_-]?code)[\"']?\s*[:=]\s*[\"']?)[^\s\"',;&}]+"#,
        with: "$1[redacted]", options: .regularExpression)
    return value.replacingOccurrences(of: #"(?<!\d)1[3-9]\d{9}(?!\d)"#, with: "[phone]", options: .regularExpression)
}
