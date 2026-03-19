import SwiftUI
import AVFoundation

@MainActor
final class CardExporter {

    enum ExportError: Error {
        case renderFailed
        case writerSetupFailed
        case writingFailed
    }

    static func exportImage(for record: DailyRecord) -> UIImage? {
        let cardView = DailyCardView(record: record)
        let renderer = ImageRenderer(content: cardView.frame(width: 360))
        renderer.scale = 3.0
        return renderer.uiImage
    }

    static func exportVideo(for record: DailyRecord) async throws -> URL {
        let size = CGSize(width: 1080, height: 1350) // 4:5 aspect ratio for Instagram
        let fps: Int32 = 30
        let totalFrames = 90 // 3 seconds at 30fps

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("pushup-card-\(UUID().uuidString).mp4")

        // Clean up if file exists
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw ExportError.writerSetupFailed
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let formScore = record.formScore ?? 0

        for frameIndex in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            // Calculate animation progress for this frame
            let time = Double(frameIndex) / Double(fps)
            let ringProgress: Double
            if time < 1.2 {
                // Ease-out ring fill
                let t = time / 1.2
                ringProgress = 1.0 - pow(1.0 - t, 3)
            } else {
                ringProgress = 1.0
            }
            let currentScore = formScore * ringProgress
            let statsOpacity = time >= 1.2 ? min((time - 1.2) / 0.5, 1.0) : 0.0
            let chipsOffset = time >= 1.7 ? min((time - 1.7) / 0.3, 1.0) : 0.0

            let frameView = AnimatedCardFrame(
                record: record,
                currentScore: currentScore,
                statsOpacity: statsOpacity,
                chipsOffset: chipsOffset
            )
            .frame(width: size.width / 3, height: size.height / 3)

            let renderer = ImageRenderer(content: frameView)
            renderer.scale = 3.0
            guard let cgImage = renderer.cgImage else { continue }

            guard let pixelBuffer = pixelBuffer(from: cgImage, size: size) else { continue }

            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status == .completed {
            return outputURL
        } else {
            throw ExportError.writingFailed
        }
    }

    private static func pixelBuffer(from cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

// MARK: - Animated Card Frame (for video rendering)

private struct AnimatedCardFrame: View {
    let record: DailyRecord
    let currentScore: Double
    let statsOpacity: Double
    let chipsOffset: Double

    private var totalTime: TimeInterval {
        record.sessions.reduce(0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
    }

    private var formattedTime: String {
        Duration.seconds(totalTime).formatted(.units(allowed: [.minutes, .seconds]))
    }

    private var sortedSessions: [PushupSession] {
        record.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Date header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Text(record.date.formatted(.dateTime.month().day().year()))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("PUSHUP COUNTER")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.5)
            }
            .padding(.bottom, 24)

            // Form ring (non-animated, driven by currentScore)
            FormQualityRingView(score: currentScore, size: 140, animated: false)
                .padding(.bottom, 28)

            // Stats
            HStack {
                statColumn(value: "\(record.totalPushups)", label: "PUSHUPS")
                Spacer()
                statColumn(value: "\(record.sessions.count)", label: "SETS")
                Spacer()
                statColumn(value: formattedTime, label: "TIME")
            }
            .opacity(statsOpacity)
            .padding(.vertical, 16)

            // Chips
            if !sortedSessions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                        VStack(spacing: 4) {
                            Text("\(session.count)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.green)
                            Text("SET \(index + 1)")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .offset(y: (1 - chipsOffset) * 20)
                .opacity(chipsOffset)
                .padding(.top, 16)
            }
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.1), Color(red: 0.1, green: 0.1, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
        }
    }
}
