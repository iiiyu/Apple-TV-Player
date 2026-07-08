import FactoryKit
import Foundation
import Observation

@Observable
final class StreamViewModel {

    enum ProgramState: Equatable, Sendable {
        case past
        case now
        case future
    }

    struct DisplayProgram: Identifiable, Equatable, Sendable {
        let program: ProgramGuide.Program
        let state: ProgramState
        let text: String
        // Non-nil only for the currently airing program, clamped to 0...1.
        let progress: Double?

        var id: String {
            "\(program.start.timeIntervalSince1970)-\(program.stop.timeIntervalSince1970)-\(program.title)"
        }
    }

    /// A pure, time-derived view of the guide. Computed on demand during a
    /// TimelineView tick so nothing mutates observable state inside `body`.
    struct ProgramSnapshot: Equatable, Sendable {
        var displayed: [DisplayProgram] = []
        var originCurrent: DisplayProgram?
    }

    @ObservationIgnored @Injected(\.playlistService) private var playlistService
    @ObservationIgnored @Injected(\.logger) private var logger
    @ObservationIgnored private let timeFormatter: DateFormatter

    let content: PlaylistItem.Content
    let stream: PlaylistParser.Stream
    let title: String

    private(set) var programs: [ProgramGuide.Program] = []
    private(set) var didLoadPrograms = false
    private(set) var mediaInfo: StreamMediaInfo?
    private(set) var isLoadingMediaInfo = false
    private(set) var mediaInfoErrorMessage: String?

    init(
        content: PlaylistItem.Content,
        stream: PlaylistParser.Stream,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.content = content
        self.stream = stream
        title = Self.title(for: stream)

        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        timeFormatter = formatter
    }

    func loadPrograms() async {
        _ = await loadPrograms(stream)
    }

    func loadMediaInfo() async {
        guard !isLoadingMediaInfo, mediaInfo == nil else { return }
        isLoadingMediaInfo = true
        mediaInfoErrorMessage = nil
        defer { isLoadingMediaInfo = false }

        do {
            mediaInfo = try await StreamMediaInfoLoader.load(urlString: stream.url)
        } catch {
            logger.error(error, private: stream.url)
            mediaInfoErrorMessage = errorMessage(for: error)
        }
    }

    func loadPrograms(_ stream: PlaylistParser.Stream) async -> Bool {
        logger.info("Read program guide stream", private: stream.title)
        defer { didLoadPrograms = true }
        guard let guide = await playlistService.programGuide(for: content, stream: stream) else {
            programs = []
            return false
        }

        programs = guide.programs.sorted(by: { $0.start < $1.start })
        return !programs.isEmpty
    }

    func displayedPrograms(at now: Date, stream: PlaylistParser.Stream) -> ProgramSnapshot {
        guard !programs.isEmpty else {
            return ProgramSnapshot()
        }

        let previousPrograms = Array(programs.filter({ $0.stop <= now }).suffix(2))
        let currentProgram = programs.first(where: { isCurrent($0, at: now) })
        let futureWindowEnd = now.addingTimeInterval(24 * 60 * 60)
        let futurePrograms = programs.filter {
            $0.start > now && $0.start < futureWindowEnd
        }
        guard let currentProgram else {
            // A gap between programs: no "now" entry, but upcoming programs
            // should still be shown, and the origin-stream banner cleared.
            return ProgramSnapshot(
                displayed: (previousPrograms + futurePrograms).map { displayProgram(for: $0, at: now) }
            )
        }

        let originCurrent: DisplayProgram? = stream == self.stream
            ? displayProgram(for: currentProgram, at: now)
            : nil
        let displayed = (previousPrograms + [currentProgram] + futurePrograms)
            .map { displayProgram(for: $0, at: now) }
        return ProgramSnapshot(displayed: displayed, originCurrent: originCurrent)
    }

    private func displayProgram(for program: ProgramGuide.Program, at now: Date) -> DisplayProgram {
        let state = programState(for: program, at: now)
        return DisplayProgram(
            program: program,
            state: state,
            text: formattedText(for: program),
            progress: state == .now ? progress(for: program, at: now) : nil
        )
    }

    func progress(for program: ProgramGuide.Program, at now: Date) -> Double {
        let total = program.stop.timeIntervalSince(program.start)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(program.start) / total, 0), 1)
    }

    func currentTimeText(at now: Date) -> String {
        timeFormatter.string(from: now)
    }

    func programState(
        for program: ProgramGuide.Program,
        at now: Date
    ) -> ProgramState {
        if program.stop <= now {
            return .past
        }

        if isCurrent(program, at: now) {
            return .now
        }

        return .future
    }

    func formattedText(for program: ProgramGuide.Program) -> String {
        "\(timeFormatter.string(from: program.start)) - \(timeFormatter.string(from: program.stop)): \(program.title)"
    }

    isolated deinit {
        logger.info("deinit of \(self)")
    }
}

private extension StreamViewModel {

    func isCurrent(_ program: ProgramGuide.Program, at now: Date) -> Bool {
        program.start <= now && now < program.stop
    }

    func errorMessage(for error: Swift.Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return "\(error)"
    }

    static func title(for stream: PlaylistParser.Stream) -> String {
        let tvgName = stream.tvgName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (tvgName?.isEmpty == false ? tvgName : nil) ?? stream.title
    }
}
