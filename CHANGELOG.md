# Changelog

## 0.3.0 (2026-10-14)

- A second build for 64-bit devices with iOS 14–17 (iPhone X and newer), from the same source tree: the `.deb` with
  `iphoneos-arm64` in its name for rootless jailbreaks (palera1n, Dopamine; it installs into `/var/jb`) and
  `AIChat-<version>-arm64.ipa` for TrollStore. Not tried on a device yet.
- On iOS 7 and newer the app draws the glossy iOS 6 bars, bar buttons, switches and rounded grouped tables itself,
  stays in light mode and opens its screens full screen, so it looks the same as on the iPad 2. The composer and the
  other screens keep clear of the notch and the home indicator; the launch screen is the app icon.
- iOS 14 and newer pick photos with the system's multi-select picker (no photo permission needed); the camera and
  "save image" permission texts are in English and Czech.
- The 32-bit build gets the same look on devices with iOS 7–10.

## 0.2.6 (2026-10-14)

- Settings → About has a "Support the development" row that opens the author's Ko-fi page. The app stays free.
- AI Chat is in the repository `http://repo.samcejko.eu/` now (Cydia, Sileo, Zebra, Installer): add it as a source to get updates.

## 0.2.5 (2026-10-02)

- Settings > About shows the author.
- The project is MIT licensed; the license is shipped inside the app next to the third-party ones.
- Pull requests are built by GitHub Actions; see `CONTRIBUTING.md`.

## 0.2.4 (2026-10-01)

- Turning on web search (the globe in the composer) now shows a warning that OpenRouter bills web
  search separately, even with free models. The alert has a "Don't Show Again" button.
- License texts of the bundled third-party components are shipped inside the app (`licenses/`).

## 0.2.3 (2026-09-23)

- Images linked in a reply (`![alt](https://...)`) are downloaded and shown inline; tap to zoom or save.
- LaTeX written in text mode (`\section`, `\item`, `\textbf`, ...) is cleaned up instead of shown raw.

## 0.2.2 (2026-09-23)

- `latex` / `tex` / `math` code fences and `\begin{equation}`-style environments render as formulas.

## 0.2.1 (2026-09-23)

- LaTeX: display math (`$$...$$`, `\[...\]`) is typeset with iosMath, inline math is converted to Unicode.
- Stray HTML in replies is cleaned up; Markdown task lists.

## 0.2.0 (2026-09-23)

- Continue a reply that was cut off; edit and resend a message.
- Model info screen (context, prices, modalities, description).
- Web search toggle, personas (system prompt presets), reasoning box and reasoning effort setting.
- Multi-photo picker, image generation with models that output images.
- A running reply finishes in the background and posts a notification.

## 0.1.0 (2026-09-23)

- First working build: TLS 1.2/1.3 through bundled Mbed TLS, streaming chat, model picker with a
  "free only" filter, photos and files, vision relay, PDF and office documents, chat history,
  light and dark glossy iOS 6 themes, English and Czech.
