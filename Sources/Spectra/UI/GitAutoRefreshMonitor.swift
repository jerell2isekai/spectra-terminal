import Foundation
import CoreServices

final class GitAutoRefreshMonitor {
    enum Trigger {
        case fileSystemEvent
        case focusRegained
        case gitTabVisible
        case manual
        case rootChanged
    }

    private final class ContextBox {
        weak var monitor: GitAutoRefreshMonitor?

        init(monitor: GitAutoRefreshMonitor) {
            self.monitor = monitor
        }
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let box = Unmanaged<ContextBox>.fromOpaque(info).takeUnretainedValue()
        box.monitor?.handleFileSystemEvent()
    }

    private let queue = DispatchQueue(label: "com.spectra.git-auto-refresh")
    private let queueKey = DispatchSpecificKey<Void>()
    private let debounceInterval: TimeInterval
    private let staleInterval: TimeInterval

    private var rootURL: URL?
    private var eventStream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var isWindowFocused = true
    private var isDirty = false
    private var refreshInFlight = false
    private var pendingRefresh = false
    private var lastCompletedRefreshAt: Date?

    var onRefreshRequested: ((Trigger) -> Void)?

    init(debounceInterval: TimeInterval = 0.8, staleInterval: TimeInterval = 5.0) {
        self.debounceInterval = debounceInterval
        self.staleInterval = staleInterval
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring(rootURL: URL) {
        syncOnQueue {
            if self.rootURL?.path == rootURL.path, eventStream != nil {
                return
            }

            stopMonitoringLocked(clearRefreshState: false)
            self.rootURL = rootURL
            startStreamLocked(rootURL: rootURL)
        }
    }

    func stopMonitoring() {
        syncOnQueue {
            stopMonitoringLocked(clearRefreshState: true)
        }
    }

    func setWindowFocused(_ focused: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            let wasFocused = isWindowFocused
            isWindowFocused = focused
            guard focused, !wasFocused, isDirty else { return }
            enqueueRefresh(.focusRegained, debounce: false, respectFocus: true)
        }
    }

    func requestImmediateRefresh(_ trigger: Trigger) {
        queue.async { [weak self] in
            self?.enqueueRefresh(trigger, debounce: false, respectFocus: false)
        }
    }

    func requestVisibleRefreshIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            let isStale = lastCompletedRefreshAt.map { Date().timeIntervalSince($0) >= self.staleInterval } ?? true
            guard isDirty || isStale else { return }
            enqueueRefresh(.gitTabVisible, debounce: false, respectFocus: true)
        }
    }

    func refreshDidFinish() {
        queue.async { [weak self] in
            guard let self else { return }
            refreshInFlight = false
            lastCompletedRefreshAt = Date()

            guard isWindowFocused else { return }
            if pendingRefresh || isDirty {
                pendingRefresh = false
                enqueueRefresh(.fileSystemEvent, debounce: false, respectFocus: true)
            }
        }
    }

    private func handleFileSystemEvent() {
        enqueueRefresh(.fileSystemEvent, debounce: true, respectFocus: true)
    }

    private func enqueueRefresh(_ trigger: Trigger, debounce: Bool, respectFocus: Bool) {
        if respectFocus && !isWindowFocused {
            isDirty = true
            return
        }

        if refreshInFlight {
            pendingRefresh = true
            isDirty = true
            return
        }

        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if debounce {
            let workItem = DispatchWorkItem { [weak self] in
                self?.dispatchRefresh(trigger)
            }
            debounceWorkItem = workItem
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
        } else {
            dispatchRefresh(trigger)
        }
    }

    private func dispatchRefresh(_ trigger: Trigger) {
        guard !refreshInFlight else {
            pendingRefresh = true
            isDirty = true
            return
        }

        refreshInFlight = true
        pendingRefresh = false
        isDirty = false
        debounceWorkItem = nil

        let callback = onRefreshRequested
        DispatchQueue.main.async {
            callback?(trigger)
        }
    }

    private func startStreamLocked(rootURL: URL) {
        let box = ContextBox(monitor: self)
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque()),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<ContextBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let stream = FSEventStreamCreate(
            nil,
            Self.eventCallback,
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) {
            eventStream = stream
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func stopMonitoringLocked(clearRefreshState: Bool) {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }

        rootURL = nil

        if clearRefreshState {
            isDirty = false
            refreshInFlight = false
            pendingRefresh = false
            lastCompletedRefreshAt = nil
        }
    }

    private func syncOnQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }
}
