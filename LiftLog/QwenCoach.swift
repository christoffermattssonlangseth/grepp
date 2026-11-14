import Foundation
import Combine
import UIKit
import FoundationModels
import HuggingFace
import MLXFoundationModels
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Qwen3 4B on the phone, run by MLX: free and private like Apple's model,
/// but larger and with a much longer window, so it can be shown months of
/// the log rather than weeks.
///
/// It is not bundled. The weights (about 2.3 GB) are fetched from Hugging
/// Face once, when the lifter asks for them in Settings, and kept in the
/// app's caches. MLX's adapter makes the model a FoundationModels
/// `LanguageModel`, so `AppleCoach` drives it exactly as it drives Apple's:
/// the same tools, the same typed answers — constrained by a grammar here
/// rather than by Apple's guided generation — and the same fences.
///
/// The adapter needs iOS 27, and the model needs memory: it's offered on
/// phones with 8 GB or more, which is what a 4-bit 4B model plus its cache
/// and the app can live in.
@MainActor
final class QwenModel: ObservableObject {
    static let shared = QwenModel()

    /// The instruct release from July 2025: no thinking phase, so answers
    /// start at once, and better at following instructions than the
    /// original Qwen3 4B.
    static let repo = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    static let downloadSize = "2.3 GB"
    /// Room the download needs, with some to spare.
    private static let bytesNeeded: Int64 = 3_000_000_000

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .notDownloaded
    private var download: Task<Void, Never>?

    private init() {
        // A 2.3 GB model resident in the background is the first thing iOS
        // kills. Let it go; the next question reloads it from disk in seconds.
        // An answer already running keeps its own reference and finishes.
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification,
                     UIApplication.didReceiveMemoryWarningNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in QwenModel.shared.unload() }
            }
        }
        Task { await refresh() }
    }

    /// Whether this phone can run it at all. The picker and Settings offer
    /// Qwen only when this is true.
    static var isSupported: Bool {
        guard #available(iOS 27.0, *) else { return false }
        return ProcessInfo.processInfo.physicalMemory >= 7_500_000_000
    }

    /// Nil when the model can answer now; otherwise why not, in words.
    var unavailableReason: String? {
        guard Self.isSupported else {
            if #available(iOS 27.0, *) { return "Qwen needs an iPhone with 8 GB of memory (15 Pro or later)." }
            return "Qwen on device needs iOS 27 or later."
        }
        switch state {
        case .ready: return nil
        case .notDownloaded: return "Download Qwen first: Settings ▸ Qwen on device (\(Self.downloadSize))."
        case .downloading: return "Qwen is still downloading. Keep the app open until it's done."
        case .failed(let why): return "Qwen's download failed: \(why) Try again in Settings."
        }
    }

    /// Reads the state from disk: whether the weights are there.
    func refresh() async {
        guard #available(iOS 27.0, *), Self.isSupported else { return }
        if case .downloading = state { return }
        state = await Self.model.isAvailable ? .ready : .notDownloaded
    }

    /// Fetch the weights. Safe to call again after a failure: it resumes.
    func startDownload() {
        guard #available(iOS 27.0, *), Self.isSupported, download == nil else { return }
        let model = Self.model
        if let free = model.freeDiskSpaceBytes, free < Self.bytesNeeded {
            state = .failed("Not enough free space: it needs about 3 GB.")
            return
        }
        state = .downloading(0)
        // The adapter reports progress to one shared observable; read it
        // while the load runs.
        let watch = Task {
            while !Task.isCancelled {
                if let d = MLXDownloadProgress.shared.download(forModelID: model.modelID),
                   case .downloading = state {
                    state = .downloading(d.fractionCompleted)
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        download = Task {
            do {
                try await model.preload()
                state = .ready
            } catch is CancellationError {
                state = .notDownloaded
            } catch {
                state = Task.isCancelled ? .notDownloaded : .failed(error.localizedDescription)
            }
            watch.cancel()
            download = nil
        }
    }

    func cancelDownload() {
        download?.cancel()
        if #available(iOS 27.0, *) { Task { await Self.model.evict() } }
    }

    /// Remove the weights from the phone.
    func delete() {
        guard #available(iOS 27.0, *) else { return }
        cancelDownload()
        Task {
            await Self.model.evict()
            if let id = Repo.ID(rawValue: Self.repo) {
                try? FileManager.default.removeItem(at: HubCache.default.repoDirectory(repo: id, kind: .model))
            }
            state = .notDownloaded
        }
    }

    /// Load the weights and compile the shaders ahead of the first question,
    /// so it isn't the question that waits for them. Called when Coach shows
    /// with Qwen picked and when the app comes back to the front.
    func prewarm() {
        guard #available(iOS 27.0, *), state == .ready else { return }
        LanguageModelSession(model: Self.model).prewarm()
    }

    /// Free the memory the loaded weights hold; they stay on disk.
    func unload() {
        guard #available(iOS 27.0, *), download == nil else { return }
        Task { await Self.model.evict() }
    }

    /// The model as FoundationModels sees it. Cheap to make: the weights
    /// live in a cache shared by every instance with this ID.
    @available(iOS 27.0, *)
    static var model: MLXLanguageModel {
        #huggingFaceLanguageModel(
            configuration: ModelConfiguration(id: repo, extraEOSTokens: ["<|im_end|>"]),
            capabilities: [.guidedGeneration, .toolCalling])
    }
}
