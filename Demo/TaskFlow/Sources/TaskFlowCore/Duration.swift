/// Parses human durations: "45s", "2m", "1m30s", "2h", "500ms", "1.5s".
public enum Duration {
    public static func seconds(_ text: String) -> Double {
        var total = 0.0
        var number = ""
        for ch in text {
            if ch.isNumber || ch == "." {
                number.append(ch)
            } else {
                let value = Double(number) ?? 0
                number = ""
                switch ch {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: break
                }
            }
        }
        return total
    }
}
