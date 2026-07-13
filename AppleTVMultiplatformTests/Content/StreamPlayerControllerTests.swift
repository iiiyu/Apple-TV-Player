import AVFoundation
import Foundation
import Testing
@testable import HiPlayer

@Suite
struct StreamPlayerControllerTests {

    @MainActor
    @Test func stoppedControllerUnloadsItsItemAndCanRestartWithoutCreatingAnotherOwner() {
        let controller = StreamPlayerController(
            urlString: "https://example.invalid/live.m3u8",
            autoplays: false
        )

        #expect(controller.player.currentItem == nil)
        #expect(!controller.isPlaybackRequested)

        controller.play()
        #expect(controller.player.currentItem != nil)
        #expect(controller.isPlaybackRequested)

        controller.stop()
        #expect(controller.player.currentItem == nil)
        #expect(!controller.isPlaybackRequested)

        controller.play()
        #expect(controller.player.currentItem != nil)
        #expect(controller.isPlaybackRequested)

        controller.stop()
    }

    @MainActor
    @Test func hlsFallbackURLUsesXtreamLivePathForExtensionlessStream() throws {
        let url = try #require(URL(string: "https://iptv.example/sample-user/sample-password/119328"))

        let fallbackURL = try #require(StreamPlayerController.hlsFallbackURL(for: url))

        #expect(fallbackURL.absoluteString == "https://iptv.example/live/sample-user/sample-password/119328.m3u8")
    }

    @MainActor
    @Test func hlsFallbackURLRewritesExistingLiveTransportStream() throws {
        let url = try #require(URL(string: "https://example.com/live/user/password/42.ts?token=old"))

        let fallbackURL = try #require(StreamPlayerController.hlsFallbackURL(for: url))

        #expect(fallbackURL.absoluteString == "https://example.com/live/user/password/42.m3u8")
    }

    @MainActor
    @Test func hlsFallbackURLSkipsNonXtreamAndExistingHLSURLs() throws {
        let regularURL = try #require(URL(string: "https://example.com/channel/playlist.m3u8"))
        let nonNumericURL = try #require(URL(string: "https://example.com/user/password/channel"))

        #expect(StreamPlayerController.hlsFallbackURL(for: regularURL) == nil)
        #expect(StreamPlayerController.hlsFallbackURL(for: nonNumericURL) == nil)
    }

    @MainActor
    @Test func rangeWithoutContentLengthErrorMatchesUnderlyingCoreMediaError() {
        let underlying = NSError(
            domain: "CoreMediaErrorDomain",
            code: -12939,
            userInfo: [NSLocalizedDescriptionKey: "byte range and no content length - error code is 200"]
        )
        let error = NSError(
            domain: "AVFoundationErrorDomain",
            code: -11850,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        #expect(StreamPlayerController.isRangeWithoutContentLengthError(error))
    }

    @MainActor
    @Test func forbiddenResourceErrorMatchesHTTP403ErrorChain() {
        let underlying = NSError(
            domain: "CoreMediaErrorDomain",
            code: -12660,
            userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed. HTTP 403: Forbidden"]
        )
        let error = NSError(
            domain: NSURLErrorDomain,
            code: -1102,
            userInfo: [
                NSLocalizedDescriptionKey: "You do not have permission to access the requested resource.",
                NSUnderlyingErrorKey: underlying
            ]
        )

        #expect(StreamPlayerController.isForbiddenResourceError(error))
    }

    @MainActor
    @Test func forbiddenResourceErrorDoesNotMatchOtherNetworkFailures() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
        )

        #expect(!StreamPlayerController.isForbiddenResourceError(error))
    }

    @MainActor
    @Test func forbiddenResourceErrorDoesNotMatchBareCoreMediaHTTPError() {
        let error = NSError(
            domain: "CoreMediaErrorDomain",
            code: -12660,
            userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed."]
        )

        #expect(!StreamPlayerController.isForbiddenResourceError(error))
    }

    @MainActor
    @Test func forbiddenResourceLogMatchesHTTP403() {
        #expect(StreamPlayerController.isForbiddenResourceLog(statusCode: 403, comment: nil))
        #expect(StreamPlayerController.isForbiddenResourceLog(statusCode: 0, comment: "HTTP 403: Forbidden"))
    }

    @MainActor
    @Test func errorLogRecoverySkipsForbiddenButRetriesTransportErrors() {
        #expect(!StreamPlayerController.shouldRecoverFromErrorLog(statusCode: 403, domain: "HTTP", comment: nil))
        #expect(StreamPlayerController.shouldRecoverFromErrorLog(statusCode: -12860, domain: "CoreMediaErrorDomain", comment: nil))
        #expect(StreamPlayerController.shouldRecoverFromErrorLog(statusCode: 500, domain: "HTTP", comment: "segment failed"))
        #expect(!StreamPlayerController.shouldRecoverFromErrorLog(statusCode: 0, domain: nil, comment: nil))
    }

    @MainActor
    @Test func unsupportedMediaFormatErrorMatchesCannotOpenErrorChain() {
        let underlying = NSError(
            domain: NSOSStatusErrorDomain,
            code: -12847
        )
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: -11828,
            userInfo: [
                NSLocalizedDescriptionKey: "Cannot Open",
                NSLocalizedFailureReasonErrorKey: "This media format is not supported.",
                NSUnderlyingErrorKey: underlying
            ]
        )

        #expect(StreamPlayerController.isUnsupportedMediaFormatError(error))
    }

    @Test func streamLatencyProbeOnlyAcceptsHTTPURLs() throws {
        #expect(StreamLatencyProbe.isProbeable(try #require(URL(string: "https://example.com/live.m3u8"))))
        #expect(StreamLatencyProbe.isProbeable(try #require(URL(string: "http://example.com/live.m3u8"))))
        #expect(!StreamLatencyProbe.isProbeable(try #require(URL(string: "file:///tmp/live.m3u8"))))
        #expect(!StreamLatencyProbe.isProbeable(try #require(URL(string: "rtmp://example.com/live"))))
    }
}
