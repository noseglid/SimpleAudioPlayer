import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer

    var body: some View {
        VStack(spacing: 30) {
            Text("\(timeString(from: audioPlayer.currentTime)) / \(timeString(from: audioPlayer.totalDuration))")
                .font(.system(size: 48, weight: .medium, design: .monospaced))

            Text("Buffer: \(timeString(from: audioPlayer.bufferedDuration))")
                .font(.system(size: 20, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)

            // Buffer Progress Bar
            VStack(spacing: 8) {
                ProgressView(value: audioPlayer.bufferingProgress)
                    .frame(height: 4)
                    .opacity(audioPlayer.isPlaying ? 1 : 0.5)
            }
            .padding(.horizontal)

            // Playback controls
            HStack(spacing: 40) {
                // Skip back 1 hour
                Button(action: {
                    audioPlayer.seek(by: -3600)
                }) {
                    Image(systemName: "gobackward")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                }

                // Play/Pause
                Button(action: {
                    audioPlayer.togglePlayPause()
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                }

                // Skip forward 1 hour
                Button(action: {
                    audioPlayer.seek(by: 3600)
                }) {
                    Image(systemName: "goforward")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                }
            }

            // Reset button
            Button(action: {
                audioPlayer.reset()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(8)
            }

            // Buffering Status
            bufferedStatusView()

            // Buffering Metrics
            bufferingMetricsView()
        }
        .padding()
    }

    private func timeString(from seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else {
            return "0:00"
        }

        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func bytesString(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    @ViewBuilder
    private func bufferedStatusView() -> some View {
        switch audioPlayer.bufferingState {
        case .buffering:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Buffering...")
            }
            .font(.caption)
            .foregroundColor(.secondary)

        case .buffered:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Buffered")
            }
            .font(.caption)
            .opacity(0.7)

        case .stalled:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Connection stalled")
            }
            .font(.caption)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func bufferingMetricsView() -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 20) {
                // Buffer percentage
                Text("Buffer: \(String(format: "%.0f%%", audioPlayer.bufferingProgress * 100))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Buffered duration
                Text("\(String(format: "%.1f", audioPlayer.bufferedDuration))s buffered")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Bytes received
            Text("\(bytesString(from: audioPlayer.bytesReceived)) received")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioPlayer())
}
