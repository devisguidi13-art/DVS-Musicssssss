# DVS Music 0.5 — iOS nativo (PROTOTIPO SPERIMENTALE)

## Perché un'app separata da Expo?

La versione 0.4 usa `react-native-webview` per la scheda YouTube e `expo-audio`
per Audius. La WebView non assicura il background audio di YouTube.
Questo prototipo iPhone usa **YouTubeKit** (risoluzione *locale* non ufficiale degli
stream) e **AVQueuePlayer** (coda nativa con più elementi pre-preparati) per testare
la riproduzione YouTube a schermo bloccato senza un server domestico.

## Funzioni implementate nel codice

- Ricerca di brani per artista/titolo tramite API Invidious pubbliche (4 istanze fallback)
- Stream YouTube selezionato sul telefono tramite YouTubeKit (audio-only)
- Player `AVQueuePlayer` e sessione audio iOS `.playback`
- Pre-caricamento dei prossimi ~6 brani perché il passaggio successivo possa avvenire in background
- Controlli di blocco (play, pausa, avanti, indietro, seek) tramite MediaPlayer
- Coda, preferiti persistenti, ripetizione, casuale iniziale, radio automatica da suggerimenti
- Interfaccia minimal nera/verde

## Cosa NON è verificato

- Non è stato compilato su un Mac/iPhone reale.
- Non è stato testato con una riproduzione effettiva YouTube; i flussi possono
  smettere di funzionare per anti-bot, 403, regione e cambi del servizio.
- Ricerca e radio dipendono da istanze Invidious di terzi, che possono essere indisponibili.
- La coda pre-caricata migliora la probabilità di passaggio automatico, ma non
  garantisce riproduzione infinita a schermo spento in ogni condizione.
- Questo progetto è **solo iOS**. La cartella root conserva la versione Expo
  0.4 per iOS/Android come base alternativa; sono due app separate.

## Attenzione alle condizioni YouTube

L'estrazione dello stream audio non usa le API ufficiali di YouTube e può
violarne le condizioni. Il player YouTube ufficiale vieta l'isolamento audio e la
riproduzione nascosta in background. Non ci sono garanzie di conformità,
continuità del servizio o approvazione sull'App Store.

## Come creare l'IPA su GitHub

1. Carica tutti i file dello ZIP nel repository **mantenendo la struttura**.
2. Vai su **Actions** e scegli **DVS Music 0.5 - iPhone audio nativo (sperimentale)**.
3. Seleziona **Run workflow** su `main`.
4. Dopo la compilazione verde, apri il job e scarica l'artifact
   `DVS_Music_05_iPhone_IPA_non_firmato`.
5. Firma l'IPA con uno strumento come Sideloadly su Windows: l'IPA non firmato
   non si installa direttamente. Con Apple ID gratuito la firma scade normalmente
   dopo 7 giorni.

Per build locale Mac: `brew install xcodegen`, `cd native-ios`,
`xcodegen generate`, apri `DVSMusicNative.xcodeproj` e gestisci la firma.
