import AVFoundation
import Foundation
import YouTubeKit

/// Experimental, unofficial: local on-device extraction. No home computer or proxy.
struct AudioResolver {
    enum ResolveError: LocalizedError {
        case noAudio
        var errorDescription: String? {
            "YouTube non ha fornito uno stream audio compatibile per questo brano."
        }
    }

    func playerItem(for track: MusicTrack) async throws -> AVPlayerItem {
        let streams = try await YouTube(videoID: track.id).streams
        guard let stream = streams
            .filterAudioOnly()
            .filter({ $0.isNativelyPlayable })
            .highestAudioBitrateStream() else {
            throw ResolveError.noAudio
        }
        return AVPlayerItem(url: stream.url)
    }
}
