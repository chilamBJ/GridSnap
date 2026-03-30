import AppKit
import ScreenCaptureKit
import AVFoundation

/// 录屏状态
enum RecordingState {
    case idle
    case recording
    case paused
}

/// 屏幕录制管理器 — 使用 ScreenCaptureKit + AVAssetWriter
final class ScreenRecorder: NSObject, ObservableObject {
    static let shared = ScreenRecorder()

    @Published var state: RecordingState = .idle
    @Published var elapsed: TimeInterval = 0

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var elapsedTimer: Timer?
    private var recordingStartDate: Date?

    private var outputURL: URL?
    private var overlayController: RecordingOverlayController?

    // MARK: - Start Recording

    func startRecording(region: CGRect? = nil) {
        guard state == .idle else {
            if state == .recording {
                stopRecording()
            }
            return
        }

        Task {
            do {
                // 获取可共享内容
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )

                // 找鼠标所在的屏幕对应的 SCDisplay
                let mouseLocation = NSEvent.mouseLocation
                let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
                let targetDisplayID = targetScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID

                guard let display = content.displays.first(where: { targetDisplayID != nil && $0.displayID == targetDisplayID })
                        ?? content.displays.first
                else {
                    print("GridSnap: 未找到可用显示器")
                    return
                }
                print("GridSnap: 录屏目标显示器 ID=\(display.displayID) (\(display.width)×\(display.height))")

                // 配置流
                let config = SCStreamConfiguration()
                config.width = Int(display.width) * 2  // Retina
                config.height = Int(display.height) * 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 fps
                config.showsCursor = true
                config.pixelFormat = kCVPixelFormatType_32BGRA

                // 创建过滤器（排除 GridSnap 自身窗口）
                let filter = SCContentFilter(display: display, excludingWindows: [])

                // 设置输出文件路径
                let prefs = Preferences.shared
                let dir = prefs.screenshotSavePath
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
                let filename = "GridSnap_Recording_\(formatter.string(from: Date())).mp4"
                let path = (dir as NSString).appendingPathComponent(filename)
                let url = URL(fileURLWithPath: path)
                self.outputURL = url

                // 创建 AVAssetWriter
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: config.width,
                    AVVideoHeightKey: config.height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 8_000_000,  // 8 Mbps
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    ]
                ]

                let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                input.expectsMediaDataInRealTime = true

                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: config.width,
                        kCVPixelBufferHeightKey as String: config.height,
                    ]
                )

                writer.add(input)

                self.assetWriter = writer
                self.videoInput = input
                self.pixelBufferAdaptor = adaptor
                self.startTime = nil

                // 创建并启动流
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
                try await stream.startCapture()
                self.stream = stream

                // 开始写入
                writer.startWriting()

                await MainActor.run {
                    self.state = .recording
                    self.recordingStartDate = Date()
                    self.startElapsedTimer()
                    self.showOverlay()
                }

                print("GridSnap: 开始录屏 → \(path)")

            } catch {
                print("GridSnap: 录屏启动失败: \(error)")
                await MainActor.run {
                    self.state = .idle
                }
            }
        }
    }

    // MARK: - Stop Recording

    func stopRecording() {
        guard state == .recording || state == .paused else { return }

        Task {
            do {
                try await stream?.stopCapture()
            } catch {
                print("GridSnap: 停止捕获失败: \(error)")
            }

            stream = nil
            videoInput?.markAsFinished()

            await assetWriter?.finishWriting()

            await MainActor.run {
                self.state = .idle
                self.elapsed = 0
                self.elapsedTimer?.invalidate()
                self.elapsedTimer = nil
                self.dismissOverlay()

                if let url = self.outputURL {
                    print("GridSnap: 录屏保存到 \(url.path)")
                    // 在 Finder 中显示文件
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    // MARK: - Toggle

    func toggleRecording() {
        if state == .idle {
            startRecording()
        } else {
            stopRecording()
        }
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.recordingStartDate else { return }
            self.elapsed = Date().timeIntervalSince(start)
        }
    }

    // MARK: - Overlay

    private func showOverlay() {
        overlayController = RecordingOverlayController(recorder: self)
        overlayController?.showWindow(nil)
    }

    private func dismissOverlay() {
        overlayController?.close()
        overlayController = nil
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, state == .recording else { return }
        guard let assetWriter = assetWriter, assetWriter.status == .writing else { return }
        guard let videoInput = videoInput, videoInput.isReadyForMoreMediaData else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if startTime == nil {
            startTime = timestamp
            assetWriter.startSession(atSourceTime: timestamp)
        }

        videoInput.append(sampleBuffer)
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("GridSnap: 录屏流错误: \(error)")
        DispatchQueue.main.async {
            self.stopRecording()
        }
    }
}
