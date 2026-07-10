import AppKit
import Combine
import Foundation
import SwiftUI
import MediaRemoteAdapter
class PlaybackController: ObservableObject {
    static let shared = PlaybackController()
    private var mediaController: MediaRemoteAdapter.MediaController
    private var wasPlayingWhenRecordingStarted = false
    private var isMediaPlaying = false
    private var lastKnownTrackInfo: TrackInfo?
    private var originalMediaAppBundleId: String?
    private var resumeTask: Task<Void, Never>?

    @Published var isPauseMediaEnabled: Bool = UserDefaults.standard.bool(forKey: "isPauseMediaEnabled") {
        didSet {
            UserDefaults.standard.set(isPauseMediaEnabled, forKey: "isPauseMediaEnabled")

            // No persistent listener is started/stopped here anymore (see `init`).
            // When the feature is turned off, just drop any captured pause state.
            if !isPauseMediaEnabled {
                resetPauseState()
            }
        }
    }

    private init() {
        mediaController = MediaRemoteAdapter.MediaController()
        // Intentionally NOT calling `mediaController.startListening()`.
        //
        // `startListening()` spawns a persistent `perl … loop` helper process that
        // streams every system now-playing update for the entire lifetime of the app
        // (and kills+relaunches itself every 100 events). Keeping that alive 24/7 —
        // even while Quill sits idle in the menu bar — is a continuous CPU/wake source
        // that drains battery and keeps the MediaRemote daemons busy. It is the single
        // largest idle cost in the app.
        //
        // We don't need a live stream: media only needs pausing/resuming around an
        // actual recording. So we query now-playing state on demand with the adapter's
        // one-shot `getTrackInfo` (a short-lived `perl … get` that exits immediately),
        // and `pause()` works without a listener (it falls back to a one-shot command).
    }

    /// Fetches the current now-playing info once, via the adapter's one-shot `get`
    /// (no persistent listener). The adapter guarantees the callback fires exactly
    /// once — a parsed value, or `nil` when nothing is playing / on process exit.
    private func currentTrackInfo() async -> TrackInfo? {
        await withCheckedContinuation { continuation in
            mediaController.getTrackInfo { trackInfo in
                continuation.resume(returning: trackInfo)
            }
        }
    }

    private func resetPauseState() {
        isMediaPlaying = false
        lastKnownTrackInfo = nil
        wasPlayingWhenRecordingStarted = false
        originalMediaAppBundleId = nil
    }

    func pauseMedia() async {
        resumeTask?.cancel()
        resumeTask = nil

        wasPlayingWhenRecordingStarted = false
        originalMediaAppBundleId = nil

        guard isPauseMediaEnabled else { return }

        // Read the current now-playing state on demand instead of relying on a
        // continuously-running listener. The round-trip also gives in-flight media
        // state a moment to settle (replacing the old fixed 50 ms sleep).
        let trackInfo = await currentTrackInfo()
        lastKnownTrackInfo = trackInfo
        isMediaPlaying = trackInfo?.payload.isPlaying ?? false

        guard trackInfo?.payload.isPlaying == true,
              let bundleId = trackInfo?.payload.bundleIdentifier else {
            return
        }

        wasPlayingWhenRecordingStarted = true
        originalMediaAppBundleId = bundleId

        mediaController.pause()
    }

    func resumeMedia() async {
        let shouldResume = wasPlayingWhenRecordingStarted
        let originalBundleId = originalMediaAppBundleId
        let delay = MediaController.shared.audioResumptionDelay

        defer {
            wasPlayingWhenRecordingStarted = false
            originalMediaAppBundleId = nil
        }

        guard isPauseMediaEnabled,
              shouldResume,
              let bundleId = originalBundleId else {
            return
        }

        guard isAppStillRunning(bundleId: bundleId) else {
            return
        }

        // Re-read current state on demand (no live listener): only resume if the same
        // app we paused is still the now-playing app and is currently paused — so we
        // never fight the user if they already resumed it or switched to something else.
        let trackInfo = await currentTrackInfo()
        lastKnownTrackInfo = trackInfo
        guard let trackInfo,
              let currentBundleId = trackInfo.payload.bundleIdentifier,
              currentBundleId == bundleId,
              trackInfo.payload.isPlaying == false else {
            return
        }

        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if Task.isCancelled {
                return
            }

            Self.sendMediaPlayPauseKey()
        }

        resumeTask = task
        await task.value
    }

    /// Simulate the hardware media Play/Pause key (NX_KEYTYPE_PLAY = 16).
    /// Some apps (e.g. Plexamp) ignore the MediaRemote `play` command but
    /// respond to the same HID key event the physical F8 key produces.
    private static func sendMediaPlayPauseKey() {
        func post(down: Bool) {
            let flags: UInt = down ? 0xa00 : 0xb00
            let data1 = Int((16 << 16) | ((down ? 0xa : 0xb) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    private func isAppStillRunning(bundleId: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == bundleId }
    }
}

