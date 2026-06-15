import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

struct StreamMediaInfo: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let name: String
        let value: String

        var id: String {
            "\(name):\(value)"
        }
    }

    let badges: [String]
    let videoItems: [Item]
    let audioItems: [Item]
}

enum StreamMediaInfoLoader {

    enum LoaderError: LocalizedError {
        case invalidURL
        case noReadableTracks

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                String(localized: "The stream URL is not valid.")
            case .noReadableTracks:
                String(localized: "No readable media tracks were found for this stream.")
            }
        }
    }

    static func load(urlString: String) async throws -> StreamMediaInfo {
        guard let url = URL(string: urlString) else {
            throw LoaderError.invalidURL
        }

        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let tracks = try await asset.load(.tracks)
        let videoTrack = tracks.first(where: { $0.mediaType == .video })
        let audioTrack = tracks.first(where: { $0.mediaType == .audio })

        var badges: [String] = []
        let videoItems = await videoItems(for: videoTrack, badges: &badges)
        let audioItems = await audioItems(for: audioTrack, badges: &badges)

        guard !videoItems.isEmpty || !audioItems.isEmpty else {
            throw LoaderError.noReadableTracks
        }

        badges.append(String(localized: "AVPlayer"))
        return StreamMediaInfo(
            badges: badges,
            videoItems: videoItems,
            audioItems: audioItems
        )
    }

    private static func videoItems(
        for track: AVAssetTrack?,
        badges: inout [String]
    ) async -> [StreamMediaInfo.Item] {
        guard let track else { return [] }

        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        let formatDescriptions = (try? await track.load(.formatDescriptions)) ?? []
        let estimatedDataRate = (try? await track.load(.estimatedDataRate)) ?? 0
        let nominalFrameRate = (try? await track.load(.nominalFrameRate)) ?? 0

        let codec = codecText(for: formatDescriptions.first)
        let resolution = resolutionText(size: naturalSize, transform: preferredTransform)
        let frameRate = frameRateText(nominalFrameRate)
        let bitrate = bitrateText(estimatedDataRate)
        let dynamicRange = dynamicRangeText(for: formatDescriptions.first, codec: codec)

        var items: [StreamMediaInfo.Item] = []
        append("Resolution", resolution, to: &items, badges: &badges, includeBadge: true)
        append("Codec", codec, to: &items, badges: &badges, includeBadge: true)
        append("Bitrate", bitrate, to: &items, badges: &badges)
        append("Frame Rate", frameRate, to: &items, badges: &badges, includeBadge: true)
        append("Dynamic Range", dynamicRange, to: &items, badges: &badges, includeBadge: true)
        return items
    }

    private static func audioItems(
        for track: AVAssetTrack?,
        badges: inout [String]
    ) async -> [StreamMediaInfo.Item] {
        guard let track else { return [] }

        let formatDescriptions = (try? await track.load(.formatDescriptions)) ?? []
        let estimatedDataRate = (try? await track.load(.estimatedDataRate)) ?? 0
        let extendedLanguageTag = try? await track.load(.extendedLanguageTag)
        let languageCode = try? await track.load(.languageCode)

        let codec = codecText(for: formatDescriptions.first)
        let channels = channelText(for: formatDescriptions.first)
        let bitrate = bitrateText(estimatedDataRate)
        let language = extendedLanguageTag ?? languageCode

        var items: [StreamMediaInfo.Item] = []
        append("Codec", codec, to: &items, badges: &badges)
        append("Channels", channels, to: &items, badges: &badges, includeBadge: true)
        append("Bitrate", bitrate, to: &items, badges: &badges)
        append("Language", language, to: &items, badges: &badges)
        return items
    }

    private static func append(
        _ name: String,
        _ value: String?,
        to items: inout [StreamMediaInfo.Item],
        badges: inout [String],
        includeBadge: Bool = false
    ) {
        guard let value, !value.isEmpty else { return }
        items.append(.init(name: name, value: value))
        if includeBadge {
            badges.append(value)
        }
    }

    private static func resolutionText(size: CGSize, transform: CGAffineTransform) -> String? {
        let transformedSize = size.applying(transform)
        let width = Int(abs(transformedSize.width).rounded())
        let height = Int(abs(transformedSize.height).rounded())
        guard width > 0, height > 0 else { return nil }
        return "\(width)x\(height)"
    }

    private static func codecText(for formatDescription: CMFormatDescription?) -> String? {
        guard let formatDescription else { return nil }
        return CMFormatDescriptionGetMediaSubType(formatDescription).fourCCString
    }

    private static func bitrateText(_ bitsPerSecond: Float) -> String? {
        guard bitsPerSecond > 0 else { return nil }
        return String(format: "%.2f Mbps", Double(bitsPerSecond) / 1_000_000)
    }

    private static func frameRateText(_ framesPerSecond: Float) -> String? {
        guard framesPerSecond > 0 else { return nil }
        return String(format: "%.2f FPS", Double(framesPerSecond))
    }

    private static func channelText(for formatDescription: CMFormatDescription?) -> String? {
        guard
            let formatDescription,
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        let channels = Int(streamDescription.pointee.mChannelsPerFrame)
        guard channels > 0 else { return nil }
        if channels == 1 {
            return String(localized: "Mono")
        }
        if channels == 2 {
            return String(localized: "Stereo")
        }
        return "\(channels).0"
    }

    private static func dynamicRangeText(
        for formatDescription: CMFormatDescription?,
        codec: String?
    ) -> String? {
        let lowercasedCodec = codec?.lowercased()
        if lowercasedCodec == "dvh1" || lowercasedCodec == "dvhe" {
            return String(localized: "Dolby Vision")
        }

        guard
            let formatDescription,
            let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any],
            let transferFunction = extensions[kCMFormatDescriptionExtension_TransferFunction as String]
        else {
            return nil
        }

        let transferDescription = String(describing: transferFunction)
        if transferDescription.localizedCaseInsensitiveContains("HLG") {
            return String(localized: "HLG")
        }
        if transferDescription.localizedCaseInsensitiveContains("2084")
            || transferDescription.localizedCaseInsensitiveContains("PQ") {
            return String(localized: "HDR PQ")
        }
        if transferDescription.localizedCaseInsensitiveContains("709") {
            return String(localized: "SDR")
        }
        return transferDescription
    }
}

private extension FourCharCode {

    var fourCCString: String {
        let bytes: [UInt8] = [
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(self)"
    }
}
