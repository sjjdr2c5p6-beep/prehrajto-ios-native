import Foundation

/// Native WebVTT (.vtt) and SubRip (.srt) parser for rendering synchronized subtitles
/// directly inside the native iOS AVPlayer overlay.
enum VTTParser {

    static func parse(content: String) -> [SubtitleCue] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []

        for block in blocks {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard !lines.isEmpty else { continue }
            if lines[0].uppercased().hasPrefix("WEBVTT") || lines[0].uppercased().hasPrefix("NOTE") {
                continue
            }

            // Find the line containing timestamp arrow "-->"
            guard let arrowLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }

            let timeLine = lines[arrowLineIndex]
            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count == 2 else { continue }

            let startStr = parts[0].trimmingCharacters(in: .whitespaces)
            // Strip any VTT positioning settings after the end timestamp (e.g., "00:01:20.000 line:85%")
            let endTokens = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            guard let endStr = endTokens.first,
                  let start = parseTimestamp(startStr),
                  let end = parseTimestamp(endStr),
                  end >= start else {
                continue
            }

            let textLines = lines.suffix(from: arrowLineIndex + 1)
            let rawText = textLines.joined(separator: "\n")
            let cleanText = cleanSubtitleText(rawText)

            if !cleanText.isEmpty {
                cues.append(SubtitleCue(startTime: start, endTime: end, text: cleanText))
            }
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    static func activeCue(at time: TimeInterval, in cues: [SubtitleCue], offset: TimeInterval = 0) -> SubtitleCue? {
        let adjustedTime = time - offset
        // Binary search for efficiency
        var low = 0
        var high = cues.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]
            if adjustedTime >= cue.startTime && adjustedTime <= cue.endTime {
                return cue
            } else if adjustedTime < cue.startTime {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return nil
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        let components = normalized.components(separatedBy: ":")

        switch components.count {
        case 3:
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else { return nil }
            return (hours * 3600.0) + (minutes * 60.0) + seconds
        case 2:
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else { return nil }
            return (minutes * 60.0) + seconds
        default:
            return nil
        }
    }

    private static func cleanSubtitleText(_ text: String) -> String {
        HTMLParser.decodeHTMLEntities(
            text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
