import XCTest
@testable import PrehrajTo

final class ParserTests: XCTestCase {

    func testParseSearchResultsExtractsVideoCards() {
        let sampleHTML = """
        <div class="video-list">
            <a class="video video--link" href="/duna-cast-druha-2024-cz-dabing-1080p/65f1a2b3c4d5e" title="Duna: Časť druhá (2024) CZ Dabing 1080p">
                <div class="video__picture">
                    <img data-src="https://thumb.prehraj.to/12345/thumb1.jpg" alt="Duna 2" />
                    <div class="video__tag video__tag--time">02:45:50</div>
                    <div class="video__tag video__tag--size">4.82 GB</div>
                    <div class="video__tag video__tag--format">HD</div>
                </div>
                <h3 class="video__title">Duna: Časť druhá (2024) CZ Dabing 1080p</h3>
            </a>
        </div>
        """

        let items = HTMLParser.parseSearchResults(html: sampleHTML, baseURL: URL(string: "https://prehraj.to")!)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.videoId, "65f1a2b3c4d5e")
        XCTAssertEqual(items.first?.videoSlug, "duna-cast-druha-2024-cz-dabing-1080p")
        XCTAssertEqual(items.first?.duration, "02:45:50")
        XCTAssertEqual(items.first?.fileSize, "4.82 GB")
        XCTAssertTrue(items.first?.isHD == true)
    }

    func testParseVideoDetailExtractsDirectCDNSourcesAndSubtitles() {
        let sampleDetailHTML = """
        <script>
            var sources = [
                { file: "https://pf-storage2.premiumcdn.net/stream/720p.mp4?token=abc", type: 'video/mp4', label: "720p", res: 720 },
                { file: "https://pf-storage2.premiumcdn.net/stream/1080p.mp4?token=def", type: 'video/mp4', label: "1080p", res: 1080 }
            ];
            var tracks = [
                { file: "https://pf-storage2.premiumcdn.net/subs/cze.vtt", kind: "captions", label: "CZE - Čeština", srclang: "cze", default: true }
            ];
        </script>
        """

        let dummyItem = VideoItem(
            videoId: "65f1a2b3c4d5e",
            videoSlug: "duna-2",
            title: "Duna 2",
            duration: "02:45:50",
            fileSize: "4.82 GB",
            thumbnailURL: nil,
            previewImages: [],
            isHD: true,
            pageURL: URL(string: "https://prehraj.to/duna-2/65f1a2b3c4d5e")!
        )

        let premiumOriginal = URL(string: "https://pf-storage2.premiumcdn.net/orig/duna2-original.mkv?token=xyz")!
        let detail = HTMLParser.parseVideoDetail(
            html: sampleDetailHTML,
            item: dummyItem,
            premiumOriginalURL: premiumOriginal
        )

        XCTAssertEqual(detail.sources.count, 3)
        XCTAssertEqual(detail.sources.first?.label, "Originál (Premium)")
        XCTAssertTrue(detail.sources.first?.isPremiumOriginal == true)
        XCTAssertEqual(detail.sources[1].resolution, 1080)
        XCTAssertEqual(detail.subtitles.count, 1)
        XCTAssertEqual(detail.subtitles.first?.language, "cze")
    }

    func testVTTParserParsesCuesAndFindsActiveSubtitle() {
        let sampleVTT = """
        WEBVTT

        1
        00:00:02.500 --> 00:00:05.000
        Vitajte na planéte Arrakis.

        2
        00:00:06.000 --> 00:00:09.250
        <i>Korenie musí prúdiť.</i>
        """

        let cues = VTTParser.parse(content: sampleVTT)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Vitajte na planéte Arrakis.")
        XCTAssertEqual(cues[1].text, "Korenie musí prúdiť.")

        let active = VTTParser.activeCue(at: 3.2, in: cues)
        XCTAssertEqual(active?.text, "Vitajte na planéte Arrakis.")
    }
}
