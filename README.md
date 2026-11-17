# DVS Music 0.5 — prova audio nativo su iPhone

- **NUOVO:** `native-ios/`: prototipo SwiftUI separato, con YouTubeKit e
  AVQueuePlayer, pensato per testare l'audio a schermo spento senza PC/server.
- **Conservato:** codice Expo/React Native 0.4 nella root (Audius + WebView YouTube).
- **Nuovo workflow:** `.github/workflows/crea-ipa-native.yml`.

Leggi `native-ios/README.md` prima di compilare: **non abbiamo verificato la
build sul runner macOS né la riproduzione effettiva su iPhone**. Il metodo usa
API non ufficiali e può violare le condizioni di YouTube.
