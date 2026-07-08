import Foundation
import Kanna
import FactoryKit

nonisolated struct ProgramGuide: Equatable, Sendable {
    let channel: Channel
    let programs: [Program]
    
    nonisolated struct Channel: Equatable, Sendable {
        let id: String
        let displayName: String
        let iconURL: String?
    }
    
    nonisolated struct Program: Equatable, Sendable {
        let title: String
        let start: Date
        let stop: Date
    }
}

actor ProgramGuideParser {

    enum ParserError: Error, Equatable {
        case missingXMLFile
        case invalidXML
        case downloadFailed(Int)
    }

    enum Progress: String, Hashable, CaseIterable, Sendable {
        case start
        case downloading
        case unarchiving
        case parsing
        case complete
    }
    
    private func set(step: Unarchiver.Progress) {
        switch step {
        case .start:
            progress = .start
        case .downloading:
            progress = .downloading
        case .unarchiving:
            progress = .unarchiving
        default:
            break
        }
    }
    
    private func set(steps: [Unarchiver.Progress]) {
        guard self.progressSteps.isEmpty else {
            return
        }
        self.progressSteps = steps.map({ step -> [Progress] in
            switch step {
            case .start: return [.start]
            case .downloading: return [.downloading]
            case .unarchiving: return [.unarchiving, .parsing]
            case .complete: return [.complete]
            }
        }).flatMap({ $0 })
    }

    private let fileManager = FileManager.default
    @ObservationIgnored @Injected(\.logger) private var logger
    private lazy var unarchiver: Unarchiver = .init(onProgress: { [weak self] steps, step, unarchiver in
        guard let self = self else { return }
        Task {
            await self.apply(steps: steps, step: step)
        }
    })

    // Applies a progress event atomically so observers never see the steps
    // list and the current step from two different events.
    private func apply(steps: [Unarchiver.Progress], step: Unarchiver.Progress) {
        set(steps: steps)
        set(step: step)
    }
    private let dateFormatter = ManualDateFormatter()
    private let onProgress: @Sendable ([Progress], Progress, isolated ProgramGuideParser) -> Void
    private var progressSteps: [Progress] = []
    private var progress: Progress = .start {
        didSet {
            onProgress(progressSteps, progress, self)
            if progress == .complete {
                progressSteps = []
            }
        }
    }

    init(onProgress: @Sendable @escaping ([Progress], Progress, isolated ProgramGuideParser) -> Void = { _, _, _ in }) {
        self.onProgress = onProgress
    }

    func parse(archiveURL: URL) async throws -> [ProgramGuide] {
        defer { progress = .complete }
        let extractedURLs = try await unarchiver.unarchive(archiveURL.absoluteString)
        defer { cleanupExtraction(at: extractedURLs) }

        let xmlURL = try xmlFileURL(from: extractedURLs)
        return try await parse(xmlURL: xmlURL)
    }

    func parse(xmlURL: URL) async throws -> [ProgramGuide] {
        var needsComplete = false
        // `.complete` means a previous run finished and this is a fresh
        // parse; without treating it as a start, reused parsers would emit
        // `.parsing` and never `.complete`, leaving progress UIs stuck.
        if progress == .start || progress == .complete {
            progressSteps = [.start, .parsing, .complete]
            needsComplete = true
            progress = .start
        }
        progress = .parsing
        defer { if needsComplete { progress = .complete } }
        let xmlString = try await loadXMLString(from: xmlURL)
        let result = try parse(xmlString: xmlString)
        return result
    }
}

private extension ProgramGuideParser {

    private func loadXMLString(from url: URL) async throws -> String {
        let data = try await loadData(from: url)

        if let xmlString = String(data: data, encoding: .utf8) {
            return xmlString
        }

        // Non-UTF-8 guides (e.g. windows-1251 feeds) declare their encoding
        // in the XML prolog. Decode with it, then drop the declaration so
        // downstream parsing treats the string as the UTF-8 it now is.
        for encoding in [Self.declaredEncoding(in: data), .isoLatin1].compactMap({ $0 }) {
            if let xmlString = String(data: data, encoding: encoding) {
                return Self.removingEncodingDeclaration(from: xmlString)
            }
        }

        throw ParserError.invalidXML
    }

    private static func declaredEncoding(in data: Data) -> String.Encoding? {
        guard let prolog = String(data: data.prefix(200), encoding: .isoLatin1),
              let match = prolog.range(
                of: #"encoding=["'][^"']+["']"#,
                options: [.regularExpression, .caseInsensitive]
              ) else {
            return nil
        }
        let name = prolog[match]
            .dropFirst("encoding=\"".count)
            .dropLast()
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(String(name) as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    private static func removingEncodingDeclaration(from xmlString: String) -> String {
        guard let match = xmlString.range(
            of: #"\s*encoding=["'][^"']+["']"#,
            options: [.regularExpression, .caseInsensitive],
            range: xmlString.startIndex..<(xmlString.index(xmlString.startIndex, offsetBy: 200, limitedBy: xmlString.endIndex) ?? xmlString.endIndex)
        ) else {
            return xmlString
        }
        return xmlString.replacingCharacters(in: match, with: "")
    }

    private func loadData(from url: URL) async throws -> Data {
        let measure = try await measureTime {
            try await _loadData(from: url)
        }
        logger.info("Program Guide loading completed in \(measure.milliseconds) milliseconds", private: url.absoluteString)
        return measure.result
    }

    private func _loadData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }

        let (data, response) = try await URLSession.download.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            throw ParserError.downloadFailed(httpResponse.statusCode)
        }

        return data
    }

    private func parse(xmlString: String) throws -> [ProgramGuide] {
        let measure = try measureTime {
            try _parse(xmlString: xmlString)
        }
        logger.info("Program Guide parsing completed in \(measure.milliseconds) milliseconds")
        return measure.result
    }

    private func _parse(xmlString: String) throws -> [ProgramGuide] {
        do {
            let document = try Kanna.XML(xml: xmlString, encoding: .utf8)

            var channelOrder: [String] = []
            var channelsByID: [String: ProgramGuide.Channel] = [:]

            for channelNode in document.xpath("/tv/channel") {
                guard
                    let channelID = normalized(channelNode["id"]),
                    let displayName = normalized(channelNode.at_xpath("display-name")?.text)
                else {
                    continue
                }

                if channelsByID[channelID] == nil {
                    channelOrder.append(channelID)
                }

                channelsByID[channelID] = .init(
                    id: channelID,
                    displayName: displayName,
                    iconURL: normalized(channelNode.at_xpath("icon")?["src"])
                )
            }

            var programsByChannelID: [String: [ProgramGuide.Program]] = [:]

            for programNode in document.xpath("/tv/programme") {
                guard
                    let channelID = normalized(programNode["channel"]),
                    let title = normalized(programNode.at_xpath("title")?.text),
                    let startValue = normalized(programNode["start"]),
                    let stopValue = normalized(programNode["stop"]),
                    let startDate = dateFormatter.date(from: startValue),
                    let stopDate = dateFormatter.date(from: stopValue)
                else {
                    continue
                }

                programsByChannelID[channelID, default: []].append(
                    .init(
                        title: title,
                        start: startDate,
                        stop: stopDate
                    )
                )
            }

            return channelOrder.compactMap { channelID in
                guard let channel = channelsByID[channelID] else {
                    return nil
                }

                return ProgramGuide(
                    channel: channel,
                    programs: programsByChannelID[channelID] ?? []
                )
            }
        } catch {
            logger.error(error)
            throw ParserError.invalidXML
        }
    }

    private func xmlFileURL(from extractedURLs: [URL]) throws -> URL {
        guard let xmlURL = extractedURLs.first(where: { $0.pathExtension.lowercased() == "xml" }) else {
            throw ParserError.missingXMLFile
        }

        return xmlURL
    }

    private func cleanupExtraction(at extractedURLs: [URL]) {
        let roots = Set(extractedURLs.compactMap(extractionRoot(for:)))

        for root in roots {
            try? fileManager.removeItem(at: root)
        }
    }

    private func extractionRoot(for extractedURL: URL) -> URL? {
        var currentURL = extractedURL

        while currentURL.path != "/" {
            if currentURL.lastPathComponent.hasPrefix("Unarchiver-") {
                return currentURL
            }

            currentURL.deleteLastPathComponent()
        }

        return nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}

nonisolated private struct ManualDateFormatter {

    // XMLTV dates must resolve in the Gregorian calendar regardless of the
    // device calendar (e.g. Buddhist on Thai locales).
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func date(from string: String) -> Date? {
        // Format: "20260218135322 +0000"
        // Positions: YYYYMMDDHHMMSS +HHMM
        // XMLTV allows truncated timestamps ("202602181400 +0300") and an
        // omitted offset (then UTC is assumed).
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard digits.count >= 8, digits.count <= 14, digits.count.isMultiple(of: 2) else {
            return nil
        }
        let padded = String(digits).padding(toLength: 14, withPad: "0", startingAt: 0)

        let yearStart = padded.startIndex
        let yearEnd = padded.index(yearStart, offsetBy: 4)
        let monthEnd = padded.index(yearEnd, offsetBy: 2)
        let dayEnd = padded.index(monthEnd, offsetBy: 2)
        let hourEnd = padded.index(dayEnd, offsetBy: 2)
        let minuteEnd = padded.index(hourEnd, offsetBy: 2)
        let secondEnd = padded.index(minuteEnd, offsetBy: 2)

        guard let year = Int(padded[yearStart..<yearEnd]),
              let month = Int(padded[yearEnd..<monthEnd]),
              let day = Int(padded[monthEnd..<dayEnd]),
              let hour = Int(padded[dayEnd..<hourEnd]),
              let minute = Int(padded[hourEnd..<minuteEnd]),
              let second = Int(padded[minuteEnd..<secondEnd]) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = timeZone(from: trimmed[digits.endIndex...])

        return calendar.date(from: components)
    }

    private func timeZone(from suffix: Substring) -> TimeZone {
        let utc = TimeZone(secondsFromGMT: 0)!
        let offset = suffix.trimmingCharacters(in: .whitespaces)
        guard offset.count == 5,
              let sign = offset.first, sign == "+" || sign == "-",
              let hours = Int(offset.dropFirst().prefix(2)),
              let minutes = Int(offset.suffix(2)) else {
            return utc
        }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds) ?? utc
    }
}
