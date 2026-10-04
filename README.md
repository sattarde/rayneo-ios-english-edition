# Turbo-IO — iOS & English Edition for RayNeo iO

> **English & iOS-Unlocked Fork of [Turbo1123/Turbo-IO](https://github.com/Turbo1123/Turbo-IO)** for the **RayNeo iO** smart glasses (`StrixOS 1.0.4.12`).
> *(For the original Chinese documentation, see [README_CN.md](./README_CN.md).)*

---

## Overview

The upstream **Turbo-IO** project added custom firmware patches (`StrixOS 1.0.4.12`) and an iOS companion addon (`TurboIOPrivateAddon.dylib`), but was primarily designed around **Android BLE/SPP pairing behavior**, **Chinese UI/firmware strings**, and **Chinese cloud services** (AMap for navigation, NetEase/QQ Music for lyrics, WeRead for books).

This **iOS & English Edition** brings full first-class **iPhone (iOS)** support, complete **English localization** across both the iOS app and the **RayNeo iO** glasses firmware, **native carousel app unlocking on iOS**, **Apple MapKit + OpenStreetMap navigation**, **Spotify + LRCLIB synchronized lyrics**, and **bidirectional Reverse-Todo sync**.

---

## Key Enhancements Over Upstream Turbo-IO

### 1. Native Carousel Apps Unlocked on iOS (`nuttx_ap.bin` Firmware Patch)
On the upstream `TurboFocus` firmware, the 4 custom Strix OS carousel apps (**Nav**, **Music**, **Reader**, and **Timer**) did not respond to temple touchpad clicks when paired with an iPhone:
- **Root Cause 1 — Android `0x80` SPP Pairing Bitmask (`paired()`)**: The custom firmware checked `(*0x200a5fb2 & 0x80)` inside `paired()`. On Android, Classic Bluetooth SPP sets bit `0x80` (`128`), whereas iOS BLE sets `0x42` (`66`). Because `0x42 & 0x80 == 0`, the firmware treated iOS connections as unpaired.
- **Root Cause 2 — LifeLog Idle Gate (`safe_home()` / `home()`)**: Every temple touchpad single-tap called `safe_home()` (`0x10a9c3dc`) or `home()` (`0x10a9df5a`, `0x10aa169a`, `0x10aa3282`), which checked whether the LifeLog subsystem was busy (`*(int *)(0x200a6298 + 0x13c) == 2`). On iOS, this value remains `2`, causing all temple clicks on Options 9–12 to be silently ignored.
- **Solution**: Patched `nuttx_ap.bin` inside `StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-ENGLISH.zip` so that:
  1. All 5 `paired()` functions (`0x10a9c788`, `0x10a9dee6`, `0x10a9f3ae`, `0x10aa1626`, `0x10aa2f8a`) accept any active BLE/SPP connection (`!= 0`).
  2. `safe_home()` (`0x10a9c3dc`) and the three inline `home()` checks (`0x10a9df5a`, `0x10aa169a`, `0x10aa3282`) return `1` cleanly on iOS.

All 4 native carousel apps on the **RayNeo iO** glasses now launch and communicate bi-directionally with the iPhone:
- **Option 9 — Nav (`TNV1`)**: Turn-by-turn distance, road name, direction arrows, and telemetry.
- **Option 10 — Music (`TMU1`)**: Track title, artist, playback controls (Play/Pause/Next/Prev), and live synchronized lyrics.
- **Option 11 — Reader (`TWB1`)**: Chapter list, page turn via temple swipe, and progress sync.
- **Option 12 — Timer (`TFA1`)**: Focus timer countdown and session sync.

### 2. Complete English Localization (iOS App + Strix OS Firmware)
- **iOS Companion Addon (`official-addon/focus-edition/`)**: Translated all menus, HUD controls, navigation prompts, music controls, reader views, voice/TTS settings, todo screens, and diagnostic panels from Chinese into English.
- **Glasses Firmware (`StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-ENGLISH.zip`)**: Translated the on-glasses UI strings (`res.bin` / `nuttx_ap.bin`) into English via `patch_firmware_english.py`.

### 3. Apple MapKit + OpenStreetMap Navigation (Replaces AMap)
- Replaced the Chinese AMap (`高德地图`) dependency (which required a Chinese API key and only worked reliably in China) with native **Apple MapKit** (`MKDirections`, `MKLocalSearchCompleter`, and `CoreLocation`).
- **Zero API Keys Required**: Search for any address or point of interest worldwide directly in the app.
- **Dual HUD Support**:
  - **Native Nav App (Option 9 / `TNV1`)**: Streams native turn-by-turn arrow icons, remaining step distance, and current/next street names directly to the **RayNeo iO** Nav app.
  - **Display Wireframe Mini-Map HUD (Option 8 / `TDP1`)**: Queries the public **OpenStreetMap Overpass API** for surrounding street geometry and renders a live rotating 1-bit wireframe vector map on the glasses display.

### 4. Spotify Integration + Synchronized LRC Lyrics
- Added a full **Spotify Web API** client (`official-addon/focus-edition/SpotifyAPI.m`) using **OAuth 2.0 Authorization Code with PKCE** (`turboio://spotify-callback`).
- Automatically queries **LRCLIB (`https://lrclib.net/api/get`)** for time-synced `.lrc` lyrics matching the currently playing Spotify or Apple Music track.
- Streams real-time synchronized lyrics and playback state to both the native **Music** carousel app (**Option 10**, `TMU1`) and the **Display** HUD (**Option 8**, `TDP1`).

### 5. Bidirectional "Reverse-Todo" Synchronization
- Enhanced `TodoRuntime.m` and `TodoProtocol.m` so Todo checklists synchronize in **both directions**:
  - Create, reorder, and push Todo items from the iPhone to the **RayNeo iO** glasses.
  - Check or uncheck items directly on the **RayNeo iO** glasses using the temple touchpad, and the completion status updates back on the iPhone automatically.

---

## Repository Structure

```text
├── StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-ENGLISH.zip  # English + iOS-unlocked firmware package for RayNeo iO
├── patch_firmware_english.py                             # Script for inspecting/patching firmware strings
├── official-addon/
│   ├── package.mjs                                       # Automated build, injection & IPA signing script
│   ├── focus-edition/                                    # Main iOS English Edition Objective-C/C source code
│   │   ├── build.sh                                      # Compiles TurboIOPrivateAddon.dylib for arm64 iOS
│   │   ├── NavigationCore.m / NavigationUI.m             # Apple MapKit + OpenStreetMap Overpass navigation
│   │   ├── SpotifyAPI.m / MusicPlayer.m / MusicUI.m      # Spotify OAuth PKCE + LRCLIB lyrics + TMU1 bridge
│   │   ├── ReaderBridge.m / ReadingContent.m / reader.c  # TWB1 Reader protocol & book management
│   │   ├── FocusBridge.m / FocusTransport.m / focus.c    # TFA1 Focus Timer protocol
│   │   └── TodoRuntime.m / TodoProtocol.m                # Bidirectional Reverse-Todo sync
│   └── firmware-research/                                # Firmware reverse-engineering utilities & tools
└── README_CN.md                                          # Original upstream Chinese README
```

---

## Prerequisites & What You Need

1. **Hardware**:
   - **RayNeo iO** smart glasses.
   - **iPhone** running iOS 16.0 or later (with Developer Mode enabled in **Settings → Privacy & Security → Developer Mode**).
   - USB-C data cable to connect the iPhone to your Mac.

2. **macOS Build Dependencies**:
   - **Xcode** & **Xcode Command Line Tools** (`xcode-select --install`)
   - **Node.js** (v18 or newer)
   - **Python 3**
   - **`ldid`** (for Mach-O entitlement extraction: `brew install ldid`)

3. **Apple Developer Signing Credentials**:
   - An **Apple Developer certificate** installed in your macOS Keychain (`security find-identity -v -p codesigning`).
   - A matching **iOS Provisioning Profile** (`.mobileprovision`) registered for your iPhone's UDID.

4. **Base RayNeo iOS App Bundle (`GlassesApp.app`)**:
   - Place a decrypted copy of the official RayNeo iOS app (`v1.2.0`) at:
     ```text
     official-addon/.cache/extracted-ipa/Payload/GlassesApp.app
     ```

5. **Optional API Keys (Configured in the App UI)**:
   - **Navigation (Apple MapKit + OpenStreetMap)**: **No API key required.** Works out of the box.
   - **Spotify Integration (Optional)**:
     1. Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and create an app.
     2. Add `turboio://spotify-callback` as a **Redirect URI** in your Spotify app settings.
     3. Copy your **Client ID** (and optional **Client Secret**) and enter them directly inside the app's **Music → Spotify Setup** screen (or set `kDefaultSpotifyClientId` in `official-addon/focus-edition/SpotifyAPI.m` before building).
   - **AI Assistant / Knowledge Base (Optional)**:
     - Enter your own OpenAI-compatible API key and endpoint inside the app's **Profile / AI Settings** menu.

---

## Step-by-Step Build & Installation Guide

### Step 1: Clone the Repository
```bash
git clone -b ios-english-edition https://github.com/<your-username>/rayneo-ios-english-edition.git
cd rayneo-ios-english-edition
```

### Step 2: Place Your Provisioning Profile & Base App
1. Copy your decrypted `GlassesApp.app` into:
   ```bash
   mkdir -p official-addon/.cache/extracted-ipa/Payload
   cp -R /path/to/GlassesApp.app official-addon/.cache/extracted-ipa/Payload/
   ```
2. Copy your Apple Developer `.mobileprovision` file to `Signing.mobileprovision` in the repository root (or pass `--profile` in Step 3).

### Step 3: Build the Addon and Package the Signed `.ipa`
Find your code-signing certificate SHA-1 hash:
```bash
security find-identity -v -p codesigning
```

Run `official-addon/package.mjs` to compile `TurboIOPrivateAddon.dylib` (`focus-edition`), embed `StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-ENGLISH.zip` as the local OTA firmware payload, inject the addon into `GlassesApp.app`, and sign the output `.ipa`:

```bash
node official-addon/package.mjs \
  --variant focus-edition \
  --profile /path/to/Signing.mobileprovision \
  --identity "<YOUR_CODESIGN_SHA1_HASH>" \
  --bundle-id "<YOUR_APP_BUNDLE_ID>" \
  --firmware-zip ./StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-ENGLISH.zip \
  --output-dir ./build/output
```

When complete, the signed `.ipa` will be generated at:
```text
./build/output/TurboIO-local-only.ipa
```

### Step 4: Install the `.ipa` onto Your iPhone
Connect your iPhone via USB and run:
```bash
xcrun devicectl device install app \
  --device <YOUR_IPHONE_UDID> \
  ./build/output/TurboIO-local-only.ipa
```

### Step 5: Flash the English iOS-Unlocked Firmware to RayNeo iO
1. Connect your **RayNeo iO** glasses to your iPhone via Bluetooth inside the installed app.
2. In the app, open the **Turbo-IO** addon menu and enable **15-Minute Local Firmware Download Mode** (or stage the bundled `StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-ENGLISH.zip` into the app's `Documents/ota/` directory).
3. Trigger the firmware update from the app settings while the **RayNeo iO** glasses are connected to power / charging cable as prompted.
4. Once the glasses reboot into `StrixOS 1.0.4.12 (FOCUS04-ENGLISH)`, single-tap the temple touchpad on **Nav**, **Music**, **Reader**, or **Timer** in the glasses carousel to use them directly with your iPhone.

---

## Credits & License

- Original **Turbo-IO** firmware research and addon architecture by **[Turbo1123](https://github.com/Turbo1123/Turbo-IO)**.
- **iOS & English Edition** enhancements: iOS `nuttx_ap.bin` `paired()` / `safe_home()` carousel unlock, English app & firmware localization, Apple MapKit + OpenStreetMap wireframe HUD navigation, Spotify OAuth PKCE + LRCLIB synchronized lyrics, and bidirectional Reverse-Todo sync.
- Provided for educational and personal research purposes only. Use custom firmware at your own risk.
