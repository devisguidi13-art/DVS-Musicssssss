import SwiftUI

private let green = Color(red: 0.14, green: 0.91, blue: 0.46)
private let canvas = Color(red: 0.035, green: 0.055, blue: 0.045)

enum MusicTab: String, CaseIterable {
    case cerca = "Cerca"
    case coda = "Coda"
    case preferiti = "Preferiti"
}

struct ContentView: View {
    @EnvironmentObject private var player: PlaybackController
    @State private var tab: MusicTab = .cerca
    @State private var query = ""
    @State private var results: [MusicTrack] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var showPlayer = false
    private let catalog = CatalogService()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DVS").font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(green)
                Text("Music").font(.system(size: 24, weight: .bold))
                Spacer()
                Text("0.5 · iOS").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)

            HStack(spacing: 8) {
                ForEach(MusicTab.allCases, id: \.self) { option in
                    Button { tab = option } label: {
                        Text(option.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(tab == option ? green : Color.white.opacity(0.07), in: Capsule())
                            .foregroundStyle(tab == option ? .black : .white)
                    }
                }
            }.padding(.horizontal, 18).padding(.bottom, 14)

            Group {
                switch tab {
                case .cerca: searchPage
                case .coda: queuePage
                case .preferiti: favoritesPage
                }
            }.frame(maxHeight: .infinity)

            if player.current != nil { miniPlayer }
            Text("Player sperimentale non ufficiale · YouTube può interrompere gli stream")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(canvas.ignoresSafeArea())
        .sheet(isPresented: $showPlayer) { playerSheet }
    }

    private var searchPage: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(green)
                TextField("Cerca artista o canzone", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if searching { ProgressView().tint(green) }
                Button { Task { await search() } } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.title3).foregroundStyle(green)
                }.accessibilityLabel("Cerca")
            }
            .padding(14).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 18)

            if let searchError {
                Text(searchError).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 18)
            }
            if results.isEmpty && !searching {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list").font(.system(size: 42)).foregroundStyle(green)
                    Text("Cerca la tua musica")
                        .font(.headline)
                    Text("Risultati da YouTube tramite istanze Invidious. Nessun account richiesto.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
            } else {
                trackList(results, mode: .search)
            }
        }
    }

    private var queuePage: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("In riproduzione e prossimi brani")
                    .font(.headline)
                Spacer()
                Button {
                    player.autoRadio.toggle()
                } label: {
                    Label("Radio", systemImage: player.autoRadio ? "dot.radiowaves.left.and.right" : "radio")
                        .font(.caption).foregroundStyle(player.autoRadio ? green : .secondary)
                }
            }.padding(.horizontal, 18)
            trackList(player.queue, mode: .queue)
        }
    }

    private var favoritesPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("La tua libreria").font(.headline).padding(.horizontal, 18)
            if player.favorites.isEmpty {
                Text("Tocca il cuore su un brano per salvarlo qui.")
                    .foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 24)
                Spacer()
            } else { trackList(player.favorites, mode: .favorites) }
        }
    }

    private enum ListMode { case search, queue, favorites }

    private func trackList(_ tracks: [MusicTrack], mode: ListMode) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(tracks) { track in
                    HStack(spacing: 12) {
                        Artwork(track: track, size: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        if player.current?.id == track.id {
                            Image(systemName: "waveform").foregroundStyle(green)
                        }
                        Button { player.toggleFavorite(track) } label: {
                            Image(systemName: player.isFavorite(track) ? "heart.fill" : "heart")
                                .foregroundStyle(player.isFavorite(track) ? green : .gray)
                        }.accessibilityLabel("Preferiti")
                        if mode != .queue {
                            Button { player.append(track) } label: {
                                Image(systemName: "text.badge.plus").foregroundStyle(.gray)
                            }.accessibilityLabel("Aggiungi alla coda")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        switch mode {
                        case .search: player.playSelection(tracks, selected: track)
                        case .favorites: player.playSelection(tracks, selected: track)
                        case .queue: player.playSelection(player.queue, selected: track)
                        }
                    }
                    .padding(.vertical, 7).padding(.horizontal, 18)
                }
            }
        }
    }

    private var miniPlayer: some View {
        HStack(spacing: 12) {
            if let track = player.current {
                Artwork(track: track, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .onTapGesture { showPlayer = true }
            }
            Spacer(minLength: 4)
            if player.preparing { ProgressView().tint(green) }
            Button { player.togglePlayback() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.title3).foregroundStyle(.white)
            }.accessibilityLabel(player.playing ? "Pausa" : "Riprendi")
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill").font(.title3).foregroundStyle(.white)
            }.accessibilityLabel("Successivo")
        }
        .padding(11)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    private var playerSheet: some View {
        VStack(spacing: 20) {
            Capsule().fill(.gray.opacity(0.6)).frame(width: 42, height: 5).padding(.top, 12)
            Spacer(minLength: 4)
            if let track = player.current {
                Artwork(track: track, size: 250)
                Text(track.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                Text(track.artist).foregroundStyle(.secondary)
            }
            if let error = player.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            if player.duration > 1 {
                Slider(value: Binding(get: { min(player.elapsed, player.duration) },
                                      set: { player.seek(to: $0) }),
                       in: 0...max(1, player.duration)).tint(green)
            }
            HStack {
                Text(formatTime(player.elapsed))
                Spacer()
                Text(formatTime(player.duration))
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 38) {
                Button { player.shuffle.toggle() } label: {
                    Image(systemName: "shuffle").foregroundStyle(player.shuffle ? green : .gray)
                }
                Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 65)).foregroundStyle(green)
                }
                Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                Button { player.cycleRepeat() } label: {
                    Image(systemName: "repeat").foregroundStyle(player.repeatSetting == .all ? green : .gray)
                }
            }
            .font(.title2).foregroundStyle(.white)
            Spacer()
        }
        .padding(24)
        .background(canvas.ignoresSafeArea())
    }

    private func formatTime(_ value: Double) -> String {
        let t = Int(value.isFinite ? max(value, 0) : 0)
        return "\(t / 60):\(String(format: "%02d", t % 60))"
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searching = true
        searchError = nil
        do {
            results = try await catalog.search(trimmed)
        } catch {
            searchError = "Ricerca non riuscita: \(error.localizedDescription)"
            results = []
        }
        searching = false
    }
}

private struct Artwork: View {
    let track: MusicTrack
    let size: CGFloat
    var body: some View {
        AsyncImage(url: track.artworkURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color(red: 0.07, green: 0.20, blue: 0.12)
                Image(systemName: "music.note").foregroundStyle(green)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
