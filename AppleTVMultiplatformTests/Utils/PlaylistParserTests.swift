import FactoryTesting
import Foundation
import Testing
@testable import HiPlayer

@Suite(.container)
struct PlaylistParserTests {

    @Test func case1() async throws {
        let playlist = """
        #EXTM3U url-tvg="https://example.com/guides/jtv.zip" url-img="https://example.com/icons/borpas-icons.zip" tvg-logo="https://example.com/icons/main-logo.png" tvg-shift=+07

        #EXTINF: -1 id="9104" tvg-name="9104" tvg-logo="9104" group-title="Эфирные", Первый канал
        https://example.tv/streams/channel-1.m3u8
        #EXTINF: -1 id="1004" tvg-name="1004" tvg-logo="1004" group-title="Эфирные", Россия 1
        https://example.tv/streams/channel-2.m3u8
        """

        let playlists = try await parse(string: playlist)

        #expect(playlists.count == 1)

        let parsedPlaylist = try #require(playlists.first)

        #expect(parsedPlaylist.tvgURL == "https://example.com/guides/jtv.zip")
        #expect(parsedPlaylist.imageURL == "https://example.com/icons/borpas-icons.zip")
        #expect(parsedPlaylist.xTvgURL == nil)
        #expect(parsedPlaylist.tvgLogo == "https://example.com/icons/main-logo.png")
        #expect(parsedPlaylist.streams.count == 2)

        let firstStream = parsedPlaylist.streams[0]
        let secondStream = parsedPlaylist.streams[1]

        #expect(firstStream.title == "Первый канал")
        #expect(firstStream.url == "https://example.tv/streams/channel-1.m3u8")
        #expect(firstStream.tvgLogo == "9104")
        #expect(firstStream.tvgID == nil)
        #expect(firstStream.tvgName == "9104")
        #expect(firstStream.groupTitle == "Эфирные")

        #expect(secondStream.title == "Россия 1")
        #expect(secondStream.url == "https://example.tv/streams/channel-2.m3u8")
        #expect(secondStream.tvgLogo == "1004")
        #expect(secondStream.tvgID == nil)
        #expect(secondStream.tvgName == "1004")
        #expect(secondStream.groupTitle == "Эфирные")
    }

    @Test func case2() async throws {
        let playlist = """
        #EXTM3U x-tvg-url="https://example.com/guides/af.xml,https://example.com/guides/al.xml,https://example.com/guides/by.xml,https://example.com/guides/ca.xml,https://example.com/guides/ee.xml,https://example.com/guides/fr.xml,https://example.com/guides/lu.xml,https://example.com/guides/ru.xml,https://example.com/guides/uk.xml,https://example.com/guides/us.xml"
        #EXTINF:-1 tvg-id="1HDMusicTelevision.ru" tvg-logo="https://example.com/logos/music.png" group-title="Music",1HD Music Television (404p) [Not 24/7]
        https://example.tv/streams/music.m3u8
        #EXTINF:-1 tvg-id="2x2.ru" tvg-logo="https://example.com/logos/entertainment.png" group-title="Entertainment",2x2 (720p) [Not 24/7]
        https://example.tv/streams/entertainment.m3u8
        #EXTINF:-1 tvg-id="Channel5.ru" tvg-logo="https://example.com/logos/channel-5.png" group-title="General",5 канал (480p) [Geo-blocked]
        https://example.tv/streams/channel-5.m3u8
        #EXTINF:-1 tvg-id="AmediaHit.ru" tvg-logo="https://example.com/logos/movie-hit.png" group-title="Movies;Series",Amedia Hit (1080p) [Geo-blocked]
        https://example.tv/streams/movie-hit.m3u8
        #EXTINF:-1 tvg-id="AmediaPremium.ru" tvg-logo="https://example.com/logos/premium.png" group-title="Movies;Series" user-agent="Mozilla/5.0 (iPhone; CPU iPhone OS 12_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",Amedia Premium (480p)
        #EXTVLCOPT:http-user-agent=Mozilla/5.0 (iPhone; CPU iPhone OS 12_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148
        https://example.tv/streams/premium.m3u8
        """

        let playlists = try await parse(dataFrom: playlist)

        #expect(playlists.count == 1)

        let parsedPlaylist = try #require(playlists.first)

        #expect(parsedPlaylist.tvgURL == nil)
        #expect(parsedPlaylist.imageURL == nil)
        #expect(parsedPlaylist.xTvgURL == "https://example.com/guides/af.xml,https://example.com/guides/al.xml,https://example.com/guides/by.xml,https://example.com/guides/ca.xml,https://example.com/guides/ee.xml,https://example.com/guides/fr.xml,https://example.com/guides/lu.xml,https://example.com/guides/ru.xml,https://example.com/guides/uk.xml,https://example.com/guides/us.xml")
        #expect(parsedPlaylist.tvgLogo == nil)
        #expect(parsedPlaylist.streams.count == 5)

        let lastStream = try #require(parsedPlaylist.streams.last)

        #expect(lastStream.title == "Amedia Premium (480p)")
        #expect(lastStream.url == "https://example.tv/streams/premium.m3u8")
        #expect(lastStream.tvgLogo == "https://example.com/logos/premium.png")
        #expect(lastStream.tvgID == "AmediaPremium.ru")
        #expect(lastStream.tvgName == nil)
        #expect(lastStream.groupTitle == "Movies;Series")
    }

    @Test func case3() async throws {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-id="1HDMusicTelevision.ru" tvg-logo="https://example.com/logos/music.png" group-title="Music",1HD Music Television (404p) [Not 24/7]
        https://example.tv/streams/music.m3u8
        #EXTINF:-1 tvg-id="AmediaPremium.ru" tvg-logo="https://example.com/logos/premium.png" group-title="Movies;Series" user-agent="Mozilla/5.0 (iPhone; CPU iPhone OS 12_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",Amedia Premium (480p)
        #EXTVLCOPT:http-user-agent=Mozilla/5.0 (iPhone; CPU iPhone OS 12_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148
        https://example.tv/streams/premium.m3u8
        #EXTINF:-1 tvg-id="Yamal.ru" tvg-logo="https://example.com/logos/yamal.png" group-title="Undefined",ЯМАЛ 1
        https://example.tv/streams/yamal.m3u8?e=1653312522&s=sample&scheme=https

        #EXTM3U x-tvg-url="https://example.com/guides/af.xml,https://example.com/guides/al.xml,https://example.com/guides/ao.xml,https://example.com/guides/ar.xml,https://example.com/guides/ba.xml,https://example.com/guides/by.xml,https://example.com/guides/cy.xml,https://example.com/guides/cz.xml,https://example.com/guides/pt.xml,https://example.com/guides/ru.xml" tvg-logo="https://example.com/playlist-logo.png"
        #EXTINF:-1 tvg-id="1Plus1.ua" tvg-logo="https://example.com/logos/one-plus-one.png" group-title="Undefined",1+1 (1080p)
        https://example.tv/streams/one-plus-one.m3u8?source=live
        #EXTINF:-1 tvg-id="1Plus1Sport.ua" tvg-logo="https://example.com/logos/sports.png" group-title="Sports",1+1 Спорт (720p) [Not 24/7]
        https://example.tv/streams/sports.m3u8
        #EXTINF:-1 tvg-id="1HDMusicTelevision.ru" tvg-logo="https://example.com/logos/music.png" group-title="Music",1HD Music Television (404p) [Not 24/7]
        https://example.tv/streams/music.m3u8
        """

        let playlists = try await parse(string: playlist)

        #expect(playlists.count == 2)

        let firstPlaylist = playlists[0]
        let secondPlaylist = playlists[1]

        #expect(firstPlaylist.xTvgURL == nil)
        #expect(firstPlaylist.tvgLogo == nil)
        #expect(secondPlaylist.xTvgURL == "https://example.com/guides/af.xml,https://example.com/guides/al.xml,https://example.com/guides/ao.xml,https://example.com/guides/ar.xml,https://example.com/guides/ba.xml,https://example.com/guides/by.xml,https://example.com/guides/cy.xml,https://example.com/guides/cz.xml,https://example.com/guides/pt.xml,https://example.com/guides/ru.xml")
        #expect(secondPlaylist.tvgLogo == "https://example.com/playlist-logo.png")
        #expect(firstPlaylist.streams.count == 3)
        #expect(secondPlaylist.streams.count == 3)

        let firstPlaylistLastStream = try #require(firstPlaylist.streams.last)
        let secondPlaylistFirstStream = secondPlaylist.streams[0]

        #expect(firstPlaylistLastStream.title == "ЯМАЛ 1")
        #expect(firstPlaylistLastStream.url == "https://example.tv/streams/yamal.m3u8?e=1653312522&s=sample&scheme=https")
        #expect(firstPlaylistLastStream.tvgID == "Yamal.ru")
        #expect(firstPlaylistLastStream.groupTitle == "Undefined")

        #expect(secondPlaylistFirstStream.title == "1+1 (1080p)")
        #expect(secondPlaylistFirstStream.url == "https://example.tv/streams/one-plus-one.m3u8?source=live")
        #expect(secondPlaylistFirstStream.tvgID == "1Plus1.ua")
        #expect(secondPlaylistFirstStream.groupTitle == "Undefined")
    }

    @Test func case4() async throws {
        let playlist = """
        #EXTM3U
        #EXT-INETRA-CHANNEL-INF: channel-id=36942372 recordable=false
        #EXT-INETRA-STREAM-INF: aspect-ratio=16:9 has-timeshift=false access=allowed
        #EXTINF:-1 cn-id=36942372 cn-records=0, Paramount Comedy HD
        https://example.tv/streams/paramount-comedy.m3u8?sid=sample

        #EXT-INETRA-CHANNEL-INF: channel-id=10338251 recordable=true
        #EXT-INETRA-STREAM-INF: has-timeshift=true access=allowed
        #EXTINF:-1 cn-id=10338251 cn-records=1, РЕН-ТВ
        https://example.tv/streams/rentv.m3u8?sid=sample
        """

        let playlists = try await parse(string: playlist)

        #expect(playlists.count == 1)

        let parsedPlaylist = try #require(playlists.first)

        #expect(parsedPlaylist.tvgURL == nil)
        #expect(parsedPlaylist.imageURL == nil)
        #expect(parsedPlaylist.xTvgURL == nil)
        #expect(parsedPlaylist.tvgLogo == nil)
        #expect(parsedPlaylist.streams.count == 2)

        let firstStream = parsedPlaylist.streams[0]
        let secondStream = parsedPlaylist.streams[1]

        #expect(firstStream.title == "Paramount Comedy HD")
        #expect(firstStream.url == "https://example.tv/streams/paramount-comedy.m3u8?sid=sample")
        #expect(firstStream.tvgLogo == nil)
        #expect(firstStream.tvgID == nil)
        #expect(firstStream.tvgName == nil)
        #expect(firstStream.groupTitle == nil)

        #expect(secondStream.title == "РЕН-ТВ")
        #expect(secondStream.url == "https://example.tv/streams/rentv.m3u8?sid=sample")
        #expect(secondStream.groupTitle == nil)
    }

    @Test func case5() async throws {
        let playlist = """
        #EXTM3U url-tvg="https://example.com/guides/epg.xml.gz"
        #EXTINF:-1 group-title="Развлекательные" tvg-rec="7" timeshift="7",ТВ3 HD
        #EXTGRP:Развлекательные
        https://example.tv/streams/api-key/136.m3u8
        #EXTINF:-1 group-title="Развлекательные" tvg-rec="7" timeshift="7",Пятница! HD
        #EXTGRP:Развлекательные
        https://example.tv/streams/api-key/181.m3u8
        #EXTINF:-1 group-title="Развлекательные" tvg-rec="7" timeshift="7",Суббота! HD
        #EXTGRP:Развлекательные
        https://example.tv/streams/api-key/269.m3u8
        #EXTINF:-1 group-title="Развлекательные" tvg-rec="7" timeshift="7",Ю
        #EXTGRP:Развлекательные
        https://example.tv/streams/api-key/230.m3u8
        """

        let playlists = try await parse(string: playlist)

        #expect(playlists.count == 1)

        let parsedPlaylist = try #require(playlists.first)

        #expect(parsedPlaylist.tvgURL == "https://example.com/guides/epg.xml.gz")
        #expect(parsedPlaylist.tvgLogo == nil)
        #expect(parsedPlaylist.streams.count == 4)

        let firstStream = parsedPlaylist.streams[0]
        let lastStream = try #require(parsedPlaylist.streams.last)

        #expect(firstStream.title == "ТВ3 HD")
        #expect(firstStream.url == "https://example.tv/streams/api-key/136.m3u8")
        #expect(firstStream.tvgLogo == nil)
        #expect(firstStream.tvgID == nil)
        #expect(firstStream.tvgName == nil)
        #expect(firstStream.groupTitle == "Развлекательные")

        #expect(lastStream.title == "Ю")
        #expect(lastStream.url == "https://example.tv/streams/api-key/230.m3u8")
        #expect(lastStream.groupTitle == "Развлекательные")
    }

    @Test func case6() async throws {
        let playlist = """
        #EXTM3U url-tvg="https://example.com/guides/pluto-us.xml.gz"
        #EXTINF:-1 tvg-id="62bdb1c5e25122000798ac79" tvg-name="South Park" tvg-logo="https://example.com/logos/south-park.png" group-title="Entertainment" tvg-chno="5", South Park
        https://example.tv/streams/south-park.m3u8?sid=sample

        #EXTINF:-1 tvg-id="673247127d5da5000817b4d6" tvg-name="Pluto TV Trending Now" tvg-logo="https://example.com/logos/pluto-trending.png" group-title="Movies" tvg-chno="5", Pluto TV Trending Now
        https://example.tv/streams/pluto-trending.m3u8?sid=sample
        """

        let playlists = try await parse(dataFrom: playlist)

        #expect(playlists.count == 1)

        let parsedPlaylist = try #require(playlists.first)

        #expect(parsedPlaylist.tvgURL == "https://example.com/guides/pluto-us.xml.gz")
        #expect(parsedPlaylist.imageURL == nil)
        #expect(parsedPlaylist.xTvgURL == nil)
        #expect(parsedPlaylist.tvgLogo == nil)
        #expect(parsedPlaylist.streams.count == 2)

        let firstStream = parsedPlaylist.streams[0]
        let secondStream = parsedPlaylist.streams[1]

        #expect(firstStream.title == "South Park")
        #expect(firstStream.tvgID == "62bdb1c5e25122000798ac79")
        #expect(firstStream.tvgName == "South Park")
        #expect(firstStream.tvgLogo == "https://example.com/logos/south-park.png")
        #expect(firstStream.groupTitle == "Entertainment")

        #expect(secondStream.title == "Pluto TV Trending Now")
        #expect(secondStream.tvgID == "673247127d5da5000817b4d6")
        #expect(secondStream.tvgName == "Pluto TV Trending Now")
        #expect(secondStream.tvgLogo == "https://example.com/logos/pluto-trending.png")
        #expect(secondStream.groupTitle == "Movies")
    }
}

private extension PlaylistParserTests {
    func parse(string: String) async throws -> [PlaylistParser.Playlist] {
        try await PlaylistParser(string: string).parse()
    }

    func parse(dataFrom string: String) async throws -> [PlaylistParser.Playlist] {
        try await PlaylistParser(data: Data(string.utf8)).parse()
    }
}
