import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var queue: [MusicTrack] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var playing: Bool = false
    @Published private(set) var preparing: Bool = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var errorMessage: String? = nil
    @Published var shuffle: Bool = false
    @Published var autoRadio: Bool = true
    @Published var repeatSetting: RepeatSetting = .off
    @Published private(set) var favorites: [MusicTrack] = []

    let player = AVQueuePlayer()
    private let resolver = AudioResolver()
    private let catalog = CatalogService()
    private var itemIndexByID: [ObjectIdentifier: Int] = [:]
    private var queuedIndices = Set<Int>()
    private var failedIndices = Set<Int>()
    private var session = UUID()
    private var filling = false
    private var radioLoading = false
    private var observedItem: NSKeyValueObservation?
    private var timeObserver: Any?
    private var finishObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

    var current: MusicTrack? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }
    var duration: Double {
        if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            return duration
        }
        return Double(current?.duration ?? 0)
    }

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { errorMessage = "Sessione audio: \(error.localizedDescription)" }
        player.automaticallyWaitsToMinimizeStalling = true
        if let saved = UserDefaults.standard.data(forKey: "dvs-native-favorites"),
           let value = try? JSONDecoder().decode([MusicTrack].self, from: saved) {
            favorites = value
        }
        observedItem = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.itemChanged() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.elapsed = max(0, time.seconds.isFinite ? time.seconds : 0)
                self?.updateNowPlaying()
            }
        }
        finishObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.itemChanged() }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.errorMessage = "Stream interrotto. Prova il prossimo brano."
            }
        }
        setupRemoteCommands()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let finishObserver { NotificationCenter.default.removeObserver(finishObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }

    func toggleFavorite(_ track: MusicTrack) {
        if favorites.contains(track) { favorites.removeAll { $0.id == track.id } }
        else { favorites.insert(track, at: 0) }
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: "dvs-native-favorites")
        }
    }

    func isFavorite(_ track: MusicTrack) -> Bool { favorites.contains(track) }

    func playSelection(_ source: [MusicTrack], selected: MusicTrack) {
        guard let start = source.firstIndex(of: selected) else { return }
        let selectedFirst = Array(source[start...]) + Array(source[..<start])
        let rest = Array(selectedFirst.dropFirst())
        let ordered = [selectedFirst[0]] + (shuffle ? rest.shuffled() : rest)
        restart(with: ordered)
    }

    func append(_ track: MusicTrack) {
        if queue.isEmpty { restart(with: [track]); return }
        if !queue.contains(track) {
            queue.append(track)
            Task { await fillAhead() }
        }
    }

    private func restart(with tracks: [MusicTrack]) {
        session = UUID()
        player.pause()
        player.removeAllItems()
        itemIndexByID.removeAll()
        queuedIndices.removeAll()
        failedIndices.removeAll()
        queue = tracks
        currentIndex = 0
        elapsed = 0
        playing = false
        preparing = true
        errorMessage = nil
        filling = false
        let request = session
        Task { await prepareFirst(sessionID: request) }
    }

    private func prepareFirst(sessionID request: UUID) async {
        guard let first = queue.first else { preparing = false; return }
        do {
            let item = try await resolver.playerItem(for: first)
            guard session == request else { return }
            itemIndexByID[ObjectIdentifier(item)] = 0
            queuedIndices.insert(0)
            player.insert(item, after: nil)
            preparing = false
            player.play()
            playing = true
            updateNowPlaying()
            Task { await fillAhead() }
        } catch {
            guard session == request else { return }
            preparing = false
            playing = false
            errorMessage = "Audio non disponibile: \(error.localizedDescription)"
        }
    }

    private func itemChanged() {
        guard let item = player.currentItem else {
            playing = false
            updateNowPlaying()
            return
        }
        guard let index = itemIndexByID[ObjectIdentifier(item)], queue.indices.contains(index) else { return }
        if index != currentIndex {
            currentIndex = index
            elapsed = 0
        }
        playing = player.rate > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        updateNowPlaying()
        Task { await fillAhead() }
    }

    /// Pre-resolve several native AVPlayerItems *before* the device locks.
    /// AVQueuePlayer can advance through already queued items in background.
    private func fillAhead() async {
        guard !filling, player.currentItem != nil else { return }
        filling = true
        defer { filling = false }
        let request = session

        if autoRadio && queue.count - currentIndex < 5 && !radioLoading {
            radioLoading = true
            let anchor = current
            if let anchor {
                let candidates = await catalog.suggested(near: anchor)
                guard session == request else { return }
                let known = Set(queue.map(\.id))
                queue.append(contentsOf: candidates.filter { !known.contains($0.id) }.prefix(12))
            }
            radioLoading = false
        }

        if repeatSetting == .all && queue.count - currentIndex < 4 && !queue.isEmpty {
            queue.append(contentsOf: Array(queue.prefix(min(20, queue.count))))
        }
        let upper = min(queue.count, currentIndex + 7)
        guard currentIndex + 1 < upper else { return }
        for idx in (currentIndex + 1)..<upper {
            guard session == request else { return }
            if queuedIndices.contains(idx) || failedIndices.contains(idx) { continue }
            do {
                let item = try await resolver.playerItem(for: queue[idx])
                guard session == request else { return }
                itemIndexByID[ObjectIdentifier(item)] = idx
                queuedIndices.insert(idx)
                player.insert(item, after: nil)
            } catch {
                guard session == request else { return }
                failedIndices.insert(idx)
            }
        }
    }

    func togglePlayback() {
        if playing { player.pause(); playing = false }
        else { player.play(); playing = true }
        updateNowPlaying()
    }

    func pause() { player.pause(); playing = false; updateNowPlaying() }
    func resume() { player.play(); playing = true; updateNowPlaying() }

    func next() {
        if player.items().count > 1 {
            player.advanceToNextItem()
            player.play()
            playing = true
            itemChanged()
        } else if queue.indices.contains(currentIndex + 1) {
            let remaining = Array(queue[(currentIndex + 1)...])
            restart(with: remaining)
        } else {
            player.pause()
            playing = false
            updateNowPlaying()
        }
    }

    func previous() {
        if elapsed > 4 { seek(to: 0); return }
        guard !queue.isEmpty else { return }
        let from = max(0, currentIndex - 1)
        restart(with: Array(queue[from...]))
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        elapsed = seconds
        updateNowPlaying()
    }

    func cycleRepeat() { repeatSetting = repeatSetting == .off ? .all : .off }

    private func updateNowPlaying() {
        guard let current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: event.positionTime) }
            return .success
        }
    }
}
