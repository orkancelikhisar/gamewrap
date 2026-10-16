/// Splits the "launch arguments" text field like a shell would for simple cases:
/// spaces separate arguments, double quotes group them.
public enum ArgumentSplitter {
    public static func split(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var hasArgument = false
        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
                hasArgument = true
            } else if ch == " " && !inQuotes {
                if hasArgument { result.append(current); current = ""; hasArgument = false }
            } else {
                current.append(ch)
                hasArgument = true
            }
        }
        if hasArgument { result.append(current) }
        return result
    }
}
