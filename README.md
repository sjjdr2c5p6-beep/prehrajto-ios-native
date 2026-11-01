# Prehraj.to – Natívna iOS Aplikácia (SwiftUI + AVPlayer)

Moderná, 100 % natívna iOS a iPadOS aplikácia pre **Prehraj.to / Prehrajto.cz** postavená v **Swift 5.10 / SwiftUI (iOS 17+)**. Nepoužíva žiadny WebView – priame streamy (`premiumcdn.net`) a `.vtt` titulky sú extrahované na pozadí a prehrávané priamo v hardvérovo akcelerovanom natívnom **`AVPlayer`** prehrávači.

---

## Hlavné funkcie

### 1. 100 % Natívny iOS Video Prehrávač (`AVPlayer` + `AVKit`)
- **Žiadny webový prehrávač ani reklamy**: Priame MP4/MKV CDN streamy prehrávané priamo cez `AVPlayerLayer`.
- **Prepínanie kvality za behu**: `Originál (Premium)`, `1080p`, `720p`, `480p` so zachovaním presného času prehrávania (`CMTime`).
- **Natívny engine pre titulky (`.vtt` / `.srt`)**: Automatické načítanie CZ/SK titulkov z Prehraj.to, nastavenie veľkosti písma (`14pt – 28pt`) a posunu synchronizácie (`±0.5s` kroky).
- **AirPlay 2 & Picture-in-Picture (Obraz v obraze)**: Natívny `AVRoutePickerView` a `AVPictureInPictureController` vrátane prehrávania zvuku na pozadí a ovládania zo zamknutej obrazovky (`MPNowPlayingInfoCenter`).
- **Gestá a ovládanie**: Dvojklik vľavo/vpravo pre posun `±10 sekúnd`, zmena rýchlosti (`0.5× – 2.0×`) a prepínanie pomeru strán (`Fit / Fill`).

### 2. Podpora Prehraj.to Premium účtu (`Keychain` + Nette Auth)
- **Prihlásenie cez E-mail a heslo** (`/?do=loginDialogForm-loginForm-submit`) alebo cez **`refresh_token` / Session Cookie**.
- Bezpečné uloženie prihlasovacích údajov v **iOS Keychain**.
- Automatické odomknutie **Originál nekomprimovaného streamu (`?do=download`)** a plnej rýchlosti pre offline sťahovanie.

### 3. Offline sťahovanie, Rozpozerané videá & Knižnica
- **Offline sťahovanie (`URLSessionDownloadTask`)**: Sťahovanie videí spolu s `.vtt` titulkami priamo do úložiska iPhonu pre prehrávanie bez internetu.
- **Rozpozerané (Resume)**: Automatické ukladanie pozície každých 5 sekúnd a možnosť pokračovať presne tam, kde ste skončili.
- **Obľúbené položky a filtre**: Filtrovanie výsledkov podľa `HD / 1080p+`, `Vysoká kvalita (>1.5 GB)` a `CZ / SK Dabing`.

---

## Ako aplikáciu skompilovať do `.ipa` a nainštalovať z Windows (bez Macu)

Keďže pracujete na Windows, projekt obsahuje pripravený **GitHub Actions workflow** ([`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)), ktorý aplikáciu skompiluje na macOS serveri priamo do súboru **`PrehrajTo-iOS.ipa`**:

1. Nahrajte tento priečinok do svojho (aj súkromného) GitHub repozitára.
2. Na GitHube otvorte kartu **Actions** → **Build iOS Native IPA (Prehraj.to)** → kliknite na **Run workflow**.
3. Po dokončení (~2 minúty) si stiahnite vygenerovaný artefakt **`PrehrajTo-iOS-IPA.zip`**, v ktorom sa nachádza `PrehrajTo-iOS.ipa`.
4. Nainštalujte `.ipa` do svojho iPhonu/iPadu z Windows pomocou:
   - **Sideloadly** (zadarmo s vaším Apple ID), alebo
   - **AltStore / SideStore**.

## Spustenie na macOS (Xcode)

1. Otvorte [`PrehrajTo.xcodeproj`](PrehrajTo.xcodeproj) v **Xcode 15.4+**.
2. V nastaveniach **Signing & Capabilities** vyberte svoj Apple účet (Team).
3. Pripojte iPhone alebo vyberte iOS Simulator a stlačte **Cmd + R**.
