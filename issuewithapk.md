# Issue with APK — Android build findings (2026-11-15)

First Android build of the TasteHub Flutter client, installed on a real phone
over Wi-Fi (`http://192.168.100.7:8090`). Two issues were found.

| # | Issue | Status |
|---|---|---|
| 1 | Debug APK is laggy | **Fixed** — use `app-release.apk` |
| 2 | Home screen looks cramped | **Fixed** — all four fixes implemented 2026-11-16, see §2 |

---

## 1. Debug APK is laggy — FIXED

**Symptom:** UI stutters while scrolling the dish grid, opening dishes and
searching.

**Cause:** `flutter build apk --debug` runs the Dart VM in interpreted/JIT
mode with debuggable flags. This is inherent to debug builds, not a bug in the
app.

**Fix:** build a release APK (ahead-of-time compiled):

```bash
cd tastehub_app
flutter build apk --release --dart-define=API_BASE_URL=http://<laptop-ip>:8080
```

| | Debug | Release |
|---|---|---|
| File | `app-debug.apk` | `app-release.apk` |
| Size | 155 MB | 53.4 MB |
| Feel | laggy | smooth |

**Required companion change (already made):** release builds block cleartext
HTTP by default (targetSdk 36), and the demo server is plain `http://`. Added
an explicit cleartext policy to
`tastehub_app/android/app/src/main/AndroidManifest.xml`:

```xml
<application
    android:label="TasteHub"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher"
    android:usesCleartextTraffic="true">
```

Both APKs share the package name and debug signing key, so installing the
release APK over the debug one is an in-place upgrade — no uninstall, saved
login session carries over.

---

## 2. Home screen looks cramped — FIXED (2026-11-16)

**Implemented exactly as agreed below** (`flutter analyze` clean, 56 widget
tests pass, rebuilt `app-release.apk`):

- **2a** header paddings/gaps compacted as specced (first card ~45 dp higher).
- **2b** single-column `mainAxisExtent` `148 → 128` and the subtitle clamped
  to one line — the dead band under the dish subtitle is gone.
- **2c** the `"N recipes"` pill was moved off the photo into an orange
  caption under the dish title; only the Top pick/New pill stays on the
  thumbnail.
- **2d** the FAB is the circular icon-only variant.

Screenshot reviewed: the first dish card starts ~45% down the screen, cards
contain a dead band, photo badges crowd the thumbnail, and the FAB overlaps
list content. Four agreed fixes:

### 2a. Compact the header (saves ~50 dp)

`lib/screens/home_screen.dart`

- `_buildHeader`: top padding `34 → 16`, bottom `20 → 12`, title/tagline gap
  `7 → 4`.
- `_buildSummary`: padding `fromLTRB(2, 20, 2, 12) → (2, 12, 2, 8)`.
- Toolbar gap between search and filter chips `12 → 10`.

### 2b. Tighten the single-column dish cards

- `lib/screens/home_screen.dart` `_buildContent`: `mainAxisExtent` for
  `columns == 1` is `148 → ~124`.
- `lib/widgets/dish_card.dart` `_content` / `_horizontalBody`: reduce inner
  padding (`md/lg` → `sm/lg`) so the `Spacer()` no longer leaves a visible
  empty band between the subtitle and the star row.

### 2c. Declutter the photo badges

- `lib/widgets/dish_card.dart`: move the `"N recipes"` count pill
  (`_countPill`) off the 104 dp thumbnail and into the text column as a small
  caption beside/under the dish title.
- Keep only the **Top pick / New** pill (`_statusPill`) on the photo.

### 2d. Shrink the FAB

- `lib/screens/home_screen.dart`: change `FloatingActionButton.extended`
  ("Add recipe" label) to a circular icon-only FAB so it covers less of the
  list. (Bottom grid padding `156` already clears the last card at full
  scroll.)

**After implementing:** run `flutter analyze && flutter test`
(`make app-test`), rebuild `app-release.apk`, reinstall, and re-check the
home screen at phone width.

---

## Environment notes from this session

- Android SDK installed at `~/android-sdk` (cmdline-tools 23.0, platform-tools
  37.0.1, platforms/android-36, build-tools/36.0.0, NDK 28.2 auto-pulled by
  Gradle, CMake 3.22.1, Platform 35 auto-pulled).
- JDK 17 (`jdk17-openjdk`) via pacman; `flutter config --android-sdk`
  set; `adb` added to `PATH` in `~/.bashrc`.
- `gradle.properties`: heap lowered `8G → 3G` (11 GB RAM machine).
- First build took ~59 min (dependency downloads); release build after that
  took ~7 min.
- APK served for phone download via `python3 -m http.server 8090` (ufw allows
  8080 and 8090/tcp).
- Since 2026-11-16 the release APK is built with the permanent Tailscale URL
  `--dart-define=API_BASE_URL=http://100.104.223.63:8080` (works on any
  network) and is copied to `~/Downloads/tastehub-app.apk` for sharing
  instead of being served over the network.
