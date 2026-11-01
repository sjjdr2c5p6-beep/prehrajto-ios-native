import Foundation

/// Pure-Swift HTML & JavaScript player configuration parser for Prehraj.to / Prehrajto.cz.
/// Zero external dependencies so the Xcode project builds immediately out of the box.
enum HTMLParser {

    // MARK: - Parse Search Results (/hledej/<query>)

    static func parseSearchResults(html: String, baseURL: URL) -> [VideoItem] {
        var results: [VideoItem] = []
        var seenIds = Set<String>()

        // Prehraj.to renders each video card around <a class="video video--link..." href="/slug/id" title="...">
        // or <a class="video__picture..." href="/slug/id" title="...">
        let blockPattern = #"<a[^>]+href=["']\/([a-zA-Z0-9\-_]+)\/([a-f0-9]{10,16})["'][^>]*>([\s\S]*?)<\/a>"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsHTML = html as NSString
        let matches = blockRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            let slug = nsHTML.substring(with: match.range(at: 1))
            let videoId = nsHTML.substring(with: match.range(at: 2))
            let innerHTML = nsHTML.substring(with: match.range(at: 3))
            let fullMatchHTML = nsHTML.substring(with: match.range(at: 0))

            // Skip non-video links or duplicates
            guard !seenIds.contains(videoId) else { continue }
            // Only process blocks that contain thumbnail or title markup
            guard innerHTML.contains("video__") || innerHTML.contains("<img") || fullMatchHTML.contains("title=") else {
                continue
            }

            let rawTitle = extractFirst(pattern: #"title=["']([^"']+)["']"#, in: fullMatchHTML)
                ?? extractFirst(pattern: #"<h[234][^>]*class=["'][^"']*video__title[^"']*["'][^>]*>([\s\S]*?)<\/h[234]>"#, in: innerHTML)
                ?? extractFirst(pattern: #"alt=["']([^"']+)["']"#, in: innerHTML)
                ?? slug.replacingOccurrences(of: "-", with: " ").capitalized

            let title = decodeHTMLEntities(stripHTMLTags(rawTitle)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            // Duration: <div class="video__tag video__tag--time">01:42:15</div>
            let duration = extractFirst(
                pattern: #"video__tag--time[^>]*>\s*([0-9:]+)\s*<"#,
                in: innerHTML
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "--:--"

            // Size: <div class="video__tag video__tag--size">2.14 GB</div>
            let fileSize = extractFirst(
                pattern: #"video__tag--size[^>]*>\s*([^<]+?)\s*<"#,
                in: innerHTML
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // HD tag detection
            let isHD = innerHTML.localizedCaseInsensitiveContains("video__tag--format")
                || innerHTML.localizedCaseInsensitiveContains(">HD<")
                || title.localizedCaseInsensitiveContains("1080p")
                || title.localizedCaseInsensitiveContains("720p")
                || title.localizedCaseInsensitiveContains("4K")

            // Thumbnail extraction (data-src or src)
            var previewURLs: [URL] = []
            let imgMatches = extractAll(
                pattern: #"(?:data-src|src)=["'](https?:\/\/[^"']+(?:\.jpg|\.jpeg|\.png|\.webp)[^"']*)["']"#,
                in: innerHTML
            )
            for urlStr in imgMatches {
                let clean = decodeHTMLEntities(urlStr)
                if let url = URL(string: clean) {
                    previewURLs.append(url)
                }
            }

            let pageURL = baseURL.appendingPathComponent("\(slug)/\(videoId)")
            seenIds.insert(videoId)

            results.append(
                VideoItem(
                    videoId: videoId,
                    videoSlug: slug,
                    title: title,
                    duration: duration,
                    fileSize: fileSize,
                    thumbnailURL: previewURLs.first,
                    previewImages: previewURLs,
                    isHD: isHD,
                    pageURL: pageURL
                )
            )
        }

        return results
    }

    // MARK: - Parse Video Detail Page (/<slug>/<id>)

    static func parseVideoDetail(
        html: String,
        item: VideoItem,
        premiumOriginalURL: URL? = nil
    ) -> VideoDetail {
        var sources: [VideoStreamSource] = []
        var seenURLs = Set<String>()

        // 1. If we resolved a Premium Original direct URL (?do=download), add it at the top
        if let premiumURL = premiumOriginalURL {
            seenURLs.insert(premiumURL.absoluteString)
            sources.append(
                VideoStreamSource(
                    label: "Originál (Premium)",
                    resolution: 2160,
                    url: premiumURL,
                    isPremiumOriginal: true,
                    fileExtension: premiumURL.pathExtension.isEmpty ? "mp4" : premiumURL.pathExtension
                )
            )
        }

        // 2. Parse JS player sources array:
        // e.g. { file: "https://...premiumcdn.net/...", type: 'video/mp4', label: "1080p", res: 1080 }
        let sourceObjectPattern = #"\{[^{}]*?(?:file|src)\s*:\s*["'](https?:\/\/[^"']+)["'][^{}]*?\}"#
        if let regex = try? NSRegularExpression(pattern: sourceObjectPattern, options: [.caseInsensitive]) {
            let nsHTML = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
            for match in matches {
                let objectStr = nsHTML.substring(with: match.range(at: 0))
                let rawURL = nsHTML.substring(with: match.range(at: 1))
                let cleanURLStr = unescapeJSString(decodeHTMLEntities(rawURL))

                // Ignore subtitle VTT files inside sources
                guard !cleanURLStr.localizedCaseInsensitiveContains(".vtt"),
                      !cleanURLStr.localizedCaseInsensitiveContains(".srt"),
                      let streamURL = URL(string: cleanURLStr),
                      !seenURLs.contains(streamURL.absoluteString) else {
                    continue
                }

                let labelStr = extractFirst(pattern: #"label\s*:\s*["']([^"']+)["']"#, in: objectStr)
                let resStr = extractFirst(pattern: #"res(?:olution)?\s*:\s*["']?(\d{3,4})["']?"#, in: objectStr)
                let resolution = parseResolution(from: resStr ?? labelStr ?? cleanURLStr)
                let finalLabel = labelStr ?? "\(resolution)p"

                seenURLs.insert(streamURL.absoluteString)
                sources.append(
                    VideoStreamSource(
                        label: finalLabel,
                        resolution: resolution,
                        url: streamURL,
                        isPremiumOriginal: false,
                        fileExtension: streamURL.pathExtension.isEmpty ? "mp4" : streamURL.pathExtension
                    )
                )
            }
        }

        // 3. Fallback: Parse <source src="..." label="..." res="..."> or direct premiumcdn.net links
        let htmlSourcePattern = #"<source[^>]+src=["'](https?:\/\/[^"']+)["'][^>]*>"#
        if let regex = try? NSRegularExpression(pattern: htmlSourcePattern, options: [.caseInsensitive]) {
            let nsHTML = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
            for match in matches {
                let tagStr = nsHTML.substring(with: match.range(at: 0))
                let rawURL = nsHTML.substring(with: match.range(at: 1))
                let cleanURLStr = unescapeJSString(decodeHTMLEntities(rawURL))

                guard let streamURL = URL(string: cleanURLStr),
                      !seenURLs.contains(streamURL.absoluteString) else { continue }

                let labelStr = extractFirst(pattern: #"(?:label|data-res|title)=["']([^"']+)["']"#, in: tagStr)
                let resolution = parseResolution(from: labelStr ?? cleanURLStr)
                let finalLabel = labelStr ?? "\(resolution)p"

                seenURLs.insert(streamURL.absoluteString)
                sources.append(
                    VideoStreamSource(
                        label: finalLabel,
                        resolution: resolution,
                        url: streamURL,
                        isPremiumOriginal: false,
                        fileExtension: streamURL.pathExtension.isEmpty ? "mp4" : streamURL.pathExtension
                    )
                )
            }
        }

        // 4. Direct Regex Fallback for any remaining `premiumcdn.net` video stream links
        let cdnPattern = #"https?:\/\/[a-zA-Z0-9\-\.]+\.premiumcdn\.net\/[^\s"'<>\\]+"#
        for rawCDN in extractAll(pattern: cdnPattern, in: html) {
            let cleanCDN = unescapeJSString(decodeHTMLEntities(rawCDN))
            guard !cleanCDN.localizedCaseInsensitiveContains(".vtt"),
                  !cleanCDN.localizedCaseInsensitiveContains(".srt"),
                  !cleanCDN.localizedCaseInsensitiveContains(".jpg"),
                  !cleanCDN.localizedCaseInsensitiveContains(".png"),
                  let cdnURL = URL(string: cleanCDN),
                  !seenURLs.contains(cdnURL.absoluteString) else {
                continue
            }
            let res = parseResolution(from: cleanCDN)
            seenURLs.insert(cdnURL.absoluteString)
            sources.append(
                VideoStreamSource(
                    label: res > 0 ? "\(res)p" : "Stream",
                    resolution: res > 0 ? res : 720,
                    url: cdnURL,
                    isPremiumOriginal: false,
                    fileExtension: cdnURL.pathExtension.isEmpty ? "mp4" : cdnURL.pathExtension
                )
            )
        }

        // Sort sources highest quality first (Premium Original first, then descending resolution)
        sources.sort { lhs, rhs in
            if lhs.isPremiumOriginal != rhs.isPremiumOriginal {
                return lhs.isPremiumOriginal
            }
            return lhs.resolution > rhs.resolution
        }

        // 5. Parse Subtitles (.vtt tracks)
        let subtitles = parseSubtitles(from: html)

        return VideoDetail(
            item: item,
            sources: sources,
            subtitles: subtitles,
            descriptionText: nil,
            viewsCount: nil,
            uploadedDate: nil
        )
    }

    // MARK: - Parse Subtitles

    static func parseSubtitles(from html: String) -> [SubtitleTrack] {
        var tracks: [SubtitleTrack] = []
        var seenURLs = Set<String>()

        // Match JS track objects: { file: "https://...vtt", kind: "captions", label: "CZE - Čeština", srclang: "cze" }
        let trackObjPattern = #"\{[^{}]*?(?:file|src)\s*:\s*["'](https?:\/\/[^"']+\.vtt[^"']*)["'][^{}]*?\}"#
        if let regex = try? NSRegularExpression(pattern: trackObjPattern, options: [.caseInsensitive]) {
            let nsHTML = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
                let objStr = nsHTML.substring(with: match.range(at: 0))
                let rawURL = nsHTML.substring(with: match.range(at: 1))
                let cleanURLStr = unescapeJSString(decodeHTMLEntities(rawURL))
                guard let url = URL(string: cleanURLStr), !seenURLs.contains(url.absoluteString) else { continue }

                let lang = extractFirst(pattern: #"(?:srclang|lang|language)\s*:\s*["']([^"']+)["']"#, in: objStr) ?? "cze"
                let label = extractFirst(pattern: #"label\s*:\s*["']([^"']+)["']"#, in: objStr) ?? lang.uppercased()
                let isDefault = objStr.localizedCaseInsensitiveContains("default: true")
                    || objStr.localizedCaseInsensitiveContains("\"default\":true")

                seenURLs.insert(url.absoluteString)
                tracks.append(
                    SubtitleTrack(
                        label: decodeHTMLEntities(label),
                        language: lang.lowercased(),
                        url: url,
                        isDefault: isDefault
                    )
                )
            }
        }

        // Also match HTML <track src="...vtt" srclang="..." label="...">
        let htmlTrackPattern = #"<track[^>]+src=["'](https?:\/\/[^"']+\.vtt[^"']*)["'][^>]*>"#
        if let regex = try? NSRegularExpression(pattern: htmlTrackPattern, options: [.caseInsensitive]) {
            let nsHTML = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
                let tagStr = nsHTML.substring(with: match.range(at: 0))
                let rawURL = nsHTML.substring(with: match.range(at: 1))
                let cleanURLStr = unescapeJSString(decodeHTMLEntities(rawURL))
                guard let url = URL(string: cleanURLStr), !seenURLs.contains(url.absoluteString) else { continue }

                let lang = extractFirst(pattern: #"srclang=["']([^"']+)["']"#, in: tagStr) ?? "cze"
                let label = extractFirst(pattern: #"label=["']([^"']+)["']"#, in: tagStr) ?? lang.uppercased()
                let isDefault = tagStr.localizedCaseInsensitiveContains("default")

                seenURLs.insert(url.absoluteString)
                tracks.append(
                    SubtitleTrack(
                        label: decodeHTMLEntities(label),
                        language: lang.lowercased(),
                        url: url,
                        isDefault: isDefault
                    )
                )
            }
        }

        return tracks
    }

    // MARK: - Parse Account / Premium Status

    static func parseAccountStatus(html: String) -> (isLoggedIn: Bool, isPremium: Bool, validity: String?) {
        let lower = html.lowercased()
        let isLoggedIn = lower.contains("odhlásit")
            || lower.contains("odhlasit")
            || lower.contains("logout")
            || lower.contains("/profil")
            || lower.contains("můj účet")

        let isPremium = lower.contains("premium aktivní")
            || lower.contains("premium do")
            || lower.contains("aktivní premium")
            || lower.contains("neomezené stahování")
            || lower.contains("kredit:")

        let validity = extractFirst(
            pattern: #"(?:Premium\s+do|Platnost\s+do|Aktivní\s+do)[:\s]*([0-9]{1,2}\.\s*[0-9]{1,2}\.\s*[0-9]{4})"#,
            in: html
        )

        return (isLoggedIn, isPremium, validity)
    }

    // MARK: - Helpers

    private static func parseResolution(from text: String) -> Int {
        if text.contains("2160") || text.localizedCaseInsensitiveContains("4k") { return 2160 }
        if text.contains("1440") || text.localizedCaseInsensitiveContains("2k") { return 1440 }
        if text.contains("1080") { return 1080 }
        if text.contains("720") { return 720 }
        if text.contains("480") { return 480 }
        if text.contains("360") { return 360 }
        if text.contains("240") { return 240 }
        return 720
    }

    static func extractFirst(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    static func extractAll(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.map { match in
            let rangeIndex = match.numberOfRanges > 1 ? 1 : 0
            return nsText.substring(with: match.range(at: rangeIndex))
        }
    }

    static func unescapeJSString(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func stripHTMLTags(_ input: String) -> String {
        input.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    static func decodeHTMLEntities(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
