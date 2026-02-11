import Foundation
import AVFoundation
import Combine
enum BufferingState: Equatable {
    case idle
    case buffering
    case buffered
    case stalled
}

class AudioPlayer: NSObject, ObservableObject {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    // Internal buffer state tracking
    private var bufferIsEmpty: Bool = false
    private var bufferIsFull: Bool = false
    private var bufferIsLikelyToKeepUp: Bool = false

    @Published var currentTime: Double = 0
    @Published var totalDuration: Double = 0
    @Published var isPlaying: Bool = false

    // Buffering state
    @Published var bufferingProgress: Double = 0
    @Published var bufferedDuration: Double = 0
    @Published var bufferingState: BufferingState = .idle
    @Published var isBuffered: Bool = false
    @Published var bytesReceived: Int64 = 0


    // Sine wave, 50h, long lived
    private let audioURL = "https://storytel-bridge-test.global.ssl.fastly.net/noseglid-playground/sine-50h.mp4?token=1796816383_d548f5137d45b2f4236e05f51b485af8f4343d98d4acdc86db6c75d60a64a355"

    
    override init() {
        super.init()

        setupAudioSession()
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            guard let url = URL(string: audioURL) else {
                print("Invalid URL")
                return
            }

            let asset = AVURLAsset(url: url)
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem)
            setupPlayerObservers()
            
        } catch {
            print("Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
    }

    func seek(by offset: TimeInterval) {
        guard let player = player else { return }

        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: offset, preferredTimescale: 600))

        // Ensure we don't seek to negative time
        let seekTime = CMTimeGetSeconds(newTime) < 0 ? .zero : newTime

        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func reset() {
        // Remove time observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        // Cancel all subscriptions
        cancellables.removeAll()

        // Pause and tear down player
        player?.pause()
        player = nil
        playerItem = nil

        // Reset all published properties
        currentTime = 0
        totalDuration = 0
        isPlaying = false
        bufferingProgress = 0
        bufferedDuration = 0
        bufferingState = .idle
        isBuffered = false
        bytesReceived = 0

        // Reset internal state
        bufferIsEmpty = false
        bufferIsFull = false
        bufferIsLikelyToKeepUp = false

        // Reinitialize with the same URL
        setupAudioSession()
    }

    private func calculateBufferingMetrics(loadedTimeRanges: [NSValue], currentTime: Double) -> (bufferedDuration: Double, bufferingProgress: Double) {
        guard !loadedTimeRanges.isEmpty else {
            return (0, 0)
        }

        var maxBufferedEnd: Double = 0

        for value in loadedTimeRanges {
            let range = value.timeRangeValue
            let start = CMTimeGetSeconds(range.start)
            let duration = CMTimeGetSeconds(range.duration)
            let end = start + duration

            // Find the furthest buffered point beyond current time
            if end > currentTime && end > maxBufferedEnd {
                maxBufferedEnd = end
            }
        }

        let bufferedDuration = max(0, maxBufferedEnd - currentTime)

        // Calculate progress (0.0 to 1.0)
        // If we have the total duration, use it; otherwise use a reasonable buffer ahead target
        let totalDuration = playerItem?.duration.seconds ?? 0
        let bufferingProgress: Double
        if totalDuration > 0 && !totalDuration.isNaN && !totalDuration.isInfinite {
            bufferingProgress = min(1.0, maxBufferedEnd / totalDuration)
        } else {
            // For live streams or unknown duration, show progress based on buffer ahead
            // Consider 30 seconds ahead as "full buffer"
            bufferingProgress = min(1.0, bufferedDuration / 30.0)
        }

        return (bufferedDuration, bufferingProgress)
    }

    private func determineBufferingState(isEmpty: Bool, isFull: Bool, isLikelyToKeepUp: Bool, isPlaying: Bool) -> BufferingState {
        if isEmpty {
            return .buffering
        } else if isPlaying && !isLikelyToKeepUp {
            return .stalled
        } else if isLikelyToKeepUp {
            return .buffered
        } else {
            return .idle
        }
    }

    private func updateBytesReceived() {
        guard let playerItem = playerItem,
              let accessLog = playerItem.accessLog() else {
            return
        }

        var totalBytes: Int64 = 0
        for event in accessLog.events {
            totalBytes += event.numberOfBytesTransferred
        }

        bytesReceived = totalBytes
    }

    private func setupPlayerObservers() {
        guard let playerItem = playerItem else { return }

        // Observe time updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            self?.updateBytesReceived()
        }

        // Observe loaded time ranges (buffer status)
        playerItem.publisher(for: \.loadedTimeRanges)
            .sink { [weak self] ranges in
                guard let self = self else { return }

                print("📊 BUFFER STATUS:")
                print("   Ranges: \(ranges.count)")
                for (index, value) in ranges.enumerated() {
                    let range = value.timeRangeValue
                    let start = CMTimeGetSeconds(range.start)
                    let duration = CMTimeGetSeconds(range.duration)
                    print("   [\(index)] \(String(format: "%.1f", start))s - \(String(format: "%.1f", start + duration))s (duration: \(String(format: "%.1f", duration))s)")
                }

                // Calculate and update buffering metrics
                let metrics = self.calculateBufferingMetrics(loadedTimeRanges: ranges, currentTime: self.currentTime)
                self.bufferedDuration = metrics.bufferedDuration
                self.bufferingProgress = metrics.bufferingProgress

                print("   Buffered ahead: \(String(format: "%.1f", metrics.bufferedDuration))s")
                print("   Buffer progress: \(String(format: "%.1f%%", metrics.bufferingProgress * 100))")
            }
            .store(in: &cancellables)

        // Observe total duration
        playerItem.publisher(for: \.duration)
            .sink { [weak self] duration in
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds >= 0 {
                    self?.totalDuration = seconds
                }
            }
            .store(in: &cancellables)

        // Observe buffer state flags
        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { [weak self] isLikelyToKeepUp in
                guard let self = self else { return }

                print("   LikelyToKeepUp: \(isLikelyToKeepUp)")

                self.bufferIsLikelyToKeepUp = isLikelyToKeepUp
                self.isBuffered = isLikelyToKeepUp

                // Update buffering state
                self.bufferingState = self.determineBufferingState(
                    isEmpty: self.bufferIsEmpty,
                    isFull: self.bufferIsFull,
                    isLikelyToKeepUp: self.bufferIsLikelyToKeepUp,
                    isPlaying: self.isPlaying
                )
            }
            .store(in: &cancellables)

        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .sink { [weak self] isEmpty in
                guard let self = self else { return }

                if isEmpty {
                    print("   ⚠️ Buffer is EMPTY")
                }

                self.bufferIsEmpty = isEmpty

                // Update buffering state
                self.bufferingState = self.determineBufferingState(
                    isEmpty: self.bufferIsEmpty,
                    isFull: self.bufferIsFull,
                    isLikelyToKeepUp: self.bufferIsLikelyToKeepUp,
                    isPlaying: self.isPlaying
                )
            }
            .store(in: &cancellables)

        playerItem.publisher(for: \.isPlaybackBufferFull)
            .sink { [weak self] isFull in
                guard let self = self else { return }

                if isFull {
                    print("   ✅ Buffer is FULL")
                }

                self.bufferIsFull = isFull

                // Update buffering state
                self.bufferingState = self.determineBufferingState(
                    isEmpty: self.bufferIsEmpty,
                    isFull: self.bufferIsFull,
                    isLikelyToKeepUp: self.bufferIsLikelyToKeepUp,
                    isPlaying: self.isPlaying
                )
            }
            .store(in: &cancellables)

        // Observe player item status and errors
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .failed:
                    print("❌ PlayerItem FAILED: \(self.playerItem?.error?.localizedDescription ?? "unknown")")
                    if let error = self.playerItem?.error as NSError? {
                        print("   Error domain: \(error.domain), code: \(error.code)")
                        print("   Underlying error: \(error.userInfo[NSUnderlyingErrorKey] ?? "none")")
                    }
                case .readyToPlay:
                    print("✅ PlayerItem ready to play")
                default:
                    print("⏳ PlayerItem status: unknown")
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
            .sink { notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                print("❌ Failed to play to end: \(error?.localizedDescription ?? "unknown")")
                if let error = error {
                    print("   Error domain: \(error.domain), code: \(error.code)")
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemNewErrorLogEntry, object: playerItem)
            .sink { [weak self] _ in
                guard let errorLog = self?.playerItem?.errorLog() else { return }
                for event in errorLog.events {
                    print("❌ Error log entry: status=\(event.errorStatusCode) domain=\(event.errorDomain) comment=\(event.errorComment ?? "none")")
                }
            }
            .store(in: &cancellables)

        // Observe player's waiting reason
        player?.publisher(for: \.reasonForWaitingToPlay)
            .sink { reason in
                if let reason = reason {
                    print("⏸️ Player waiting: \(reason.rawValue)")
                } else {
                    print("▶️ Player not waiting")
                }
            }
            .store(in: &cancellables)
    }

}
