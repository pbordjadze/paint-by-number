import Combine
import Foundation
import GroupActivities
import Observation
import os
import PaintCore

/// SharePlay's side of Paint Together: starts a session for a painting, joins the ones that
/// come (`AppShellView` listens from launch), sends the painting through the journal, and
/// carries `TogetherEngine`'s bytes over the session's messenger. One session at a time.
///
/// The host's painting is theirs; the friend's arrives as a received painting (free, never a
/// free painting's worth: `Library.receive`), which the shell opens, and both keep theirs.
@MainActor @Observable
final class TogetherLink {
    static let shared = TogetherLink()

    /// The painting someone else started, arrived and waiting for the shell to add and open.
    var arrived: TogetherPainting?
    /// How many others are painting.
    private(set) var friends = 0
    private(set) var isActive = false

    @ObservationIgnored private var groupSession: GroupSession<PaintTogetherActivity>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var engine: TogetherEngine?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// This device's painting in the session: the one it shared, or the one it was sent.
    @ObservationIgnored private var painting: UUID?
    @ObservationIgnored private var hosting: (id: UUID, data: Data)?
    @ObservationIgnored private var isListening = false
    /// Stamps tell this device's fills from the friend's; a fresh one for each launch.
    let painter = UInt64.random(in: 1...UInt64.max)

    /// Waits for sessions for as long as the app runs (started once, by the shell).
    func listen() async {
        guard !isListening else { return }
        isListening = true
        for await session in PaintTogetherActivity.sessions() { join(session) }
    }

    /// More › Paint Together: shares `artwork` with the people in the call or the conversation.
    func start(artwork id: UUID, title: String, data: Data) async {
        hosting = (id, data)
        painting = id
        let activity = PaintTogetherActivity(painting: id, title: title)
        do {
            // With no call, the system offers to start one (or to share in Messages).
            _ = try await activity.activate()
        } catch {
            Log.together.error("Paint Together didn't start: \(String(describing: error), privacy: .public)")
        }
    }

    /// The shell added the painting someone sent: this is the painting of the session.
    func received(as id: UUID) {
        painting = id
        arrived = nil
        bind()
    }

    /// The painting on screen, whichever it is: painted together once it is the session's.
    @ObservationIgnored private var open: (id: UUID, session: PaintingSession)?

    /// Each painting's ledger, kept while the session lasts (`TogetherEngine.init`).
    @ObservationIgnored private var ledgers: [UUID: TogetherLedger] = [:]

    func paintingOpened(_ id: UUID, session: PaintingSession) {
        if let open, open.id == id, open.session !== session, engine != nil {
            // Cut again or changed: its areas are no longer the friend's, so painting together ends.
            leave()
        } else if open?.session !== session {
            stopEngine()
        }
        open = (id, session)
        bind()
    }

    func paintingClosed(_ id: UUID) {
        guard open?.id == id else { return }
        stopEngine()
        open = nil
    }

    private func stopEngine() {
        guard let engine else { return }
        engine.stop()
        if let id = open?.id ?? painting { ledgers[id] = engine.ledger }
        self.engine = nil
    }

    /// Paints the open painting together when it is the session's and the session is up,
    /// whichever of the three comes last.
    private func bind() {
        guard engine == nil, let open, open.id == painting, let messenger else { return }
        let engine = TogetherEngine(session: open.session, painter: painter, ledger: ledgers[open.id]) { data in
            Task { try? await messenger.send(data) }
        }
        self.engine = engine
        engine.start()
    }

    func leave() {
        groupSession?.leave()
        end()
    }

    private func join(_ session: GroupSession<PaintTogetherActivity>) {
        end()
        groupSession = session
        let messenger = GroupSessionMessenger(session: session)
        let journal = GroupSessionJournal(session: session)
        self.messenger = messenger
        let isHost = hosting?.id == session.activity.painting
        if !isHost {
            hosting = nil
            painting = nil
        }
        session.join()
        #if DEBUG
        TourLog.trace("together", "join\thost=%@", isHost.description)
        #endif
        isActive = true
        bind()
        tasks.append(Task { [weak self] in
            for await (data, _) in messenger.messages(of: Data.self) { self?.engine?.receive(data) }
        })
        tasks.append(Task { [weak self] in
            for await participants in session.$activeParticipants.values {
                guard let self else { return }
                let others = participants.count - 1
                #if DEBUG
                TourLog.trace("together", "friends\tcount=%ld", max(0, others))
                #endif
                // Someone new arrived: they get everything painted.
                if others > self.friends { self.engine?.sendSnapshot() }
                self.friends = max(0, others)
            }
        })
        tasks.append(Task { [weak self] in
            for await state in session.$state.values {
                if case .invalidated = state {
                    #if DEBUG
                    TourLog.trace("together", "ended")
                    #endif
                    self?.end()
                    return
                }
            }
        })
        if isHost, let data = hosting?.data {
            tasks.append(Task {
                do { _ = try await journal.add(TogetherPainting(data: data)) } catch {
                    Log.together.error("The painting couldn't be shared: \(String(describing: error), privacy: .public)")
                }
            })
        } else {
            tasks.append(Task { [weak self] in
                for await attachments in journal.attachments {
                    guard let first = attachments.first else { continue }
                    do {
                        let painting = try await first.load(TogetherPainting.self)
                        #if DEBUG
                        TourLog.trace("together", "arrived\tbytes=%ld", painting.data.count)
                        #endif
                        if self?.painting == nil { self?.arrived = painting }
                    } catch {
                        Log.together.error("The shared painting didn't arrive: \(String(describing: error), privacy: .public)")
                    }
                }
            })
        }
    }

    private func end() {
        for task in tasks { task.cancel() }
        tasks = []
        engine?.stop()
        engine = nil
        ledgers = [:]
        messenger = nil
        groupSession = nil
        friends = 0
        isActive = false
    }
}
