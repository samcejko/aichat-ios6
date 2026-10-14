# AI Chat for iOS 6

Universal (iPhone + iPad) OpenRouter chat client for **jailbroken iOS 6.x** devices (armv7, e.g. iPad 2),
with a second build for **64-bit devices with iOS 14–17** (iPhone X and newer: rootless jailbreaks and
TrollStore) that keeps the glossy iOS 6 look.
Bring your own [OpenRouter API key](https://openrouter.ai/keys) and chat with any of the models,
including the free ones.

Why it is special: openrouter.ai only speaks TLS 1.2/1.3 with AEAD cipher suites, which the iOS 6
networking stack cannot negotiate. The app therefore ships its own TLS stack (Mbed TLS) and a tiny
HTTP/1.1 client, so everything runs on the device without any relay server.

## Download

Get the latest packages from the [Releases](../../releases/latest) page:

| Device | Package |
| --- | --- |
| iOS 6.x, 32-bit (iPad 2, iPhone 4S, …) | `AIChat-<version>.ipa` or `com.samcejko.aichat_<version>_iphoneos-arm.deb` |
| iOS 14–17, 64-bit, rootless jailbreak (palera1n, Dopamine) | `com.samcejko.aichat_<version>_iphoneos-arm64.deb` |
| iOS 14–17, 64-bit, TrollStore | `AIChat-<version>-arm64.ipa` |

Tested on an iPad 2 (iPad2,2) with iOS 6.1.3. The iPhone layout is implemented but has not been
tried on a real iPhone yet; the 64-bit build has not been tried on a device yet either.

## Features

- OpenRouter API key onboarding, key status and free-tier daily counter
- Model picker with search, "free only" / "images" filters and sorting; remembers the last model;
  model info screen with context size, prices and modalities
- Streaming replies with Markdown rendering (headings, lists, code blocks, tables, quotes, task lists)
- LaTeX: display formulas are typeset with iosMath, inline math is converted to Unicode
- Photos (multi-select from the library, camera, clipboard) and files (iTunes File Sharing, "Open in…")
- Vision relay: when the chosen model cannot see images, a configurable vision helper model
  describes them and the description is passed on
- PDF via OpenRouter's file parser; docx/xlsx/pptx/odt/ods/odp/html/rtf converted to text on device
- Image generation with models that output images; images linked in a reply are shown inline
- Continue a cut-off reply, edit and resend, regenerate
- Personas (system prompt presets), reasoning display and reasoning effort
- Optional web search (billed separately by OpenRouter; the app warns before turning it on)
- A running reply finishes in the background and posts a notification
- Chat history, glossy iOS 6 look with light and dark themes, English and Czech

## Installing on the device

The easy way: add the repository `http://repo.samcejko.eu/` in Cydia (Sources → Edit → Add), Sileo, Zebra or Installer
and install AI Chat from there; updates then come through the package manager. The app is free; if it is useful to you, you can support the development
at [ko-fi.com/samcejko](https://ko-fi.com/samcejko). By hand:

1. Cydia: **AppSync Unified** (repo `https://cydia.akemi.ai/`) and **IPA Installer Console** (BigBoss),
   plus OpenSSH for the helper scripts.
2. Copy the `.ipa` to the device and run `ipainstaller -f AIChat.ipa`, or use iFunBox / 3uTools.
   The `.deb` works too (`dpkg -i`, then `uicache`) and installs into `/Applications`.

On iOS 14–17 (64-bit): with a rootless jailbreak add the same repository in Sileo or Zebra, or install the
`iphoneos-arm64` `.deb` with `dpkg -i` (it goes into `/var/jb/Applications`); without a jailbreak open the
`-arm64.ipa` in [TrollStore](https://github.com/opa334/TrollStore). The same app, the same iOS 6 look.

## Privacy

Requests go straight from the device to `openrouter.ai`; there is no server in between and no
analytics. The API key is stored on the device only: in the Keychain when it is available, otherwise
(typical for fake-signed installs) in the app's preferences file inside its sandbox, unencrypted.

## Building (GitHub Actions)

No Mac needed. Every push to a branch and every pull request runs `.github/workflows/build.yml` on
Ubuntu with Theos and Mbed TLS, twice from the same sources:

- `ios6-armv7`: the iOS 9.3 SDK, deployment target 6.0 → `AIChat-<version>.ipa` and the `iphoneos-arm` `.deb`;
- `ios14-arm64`: `make package THEOS_PACKAGE_SCHEME=rootless`, the iOS 16.5 SDK, deployment target 14.0 →
  `AIChat-<version>-arm64.ipa` (TrollStore) and the `iphoneos-arm64` `.deb` (rootless, `/var/jb`).

The differences live in `src/Util/ORModern.m` (safe areas, the iOS 6 look of the bars on iOS 7 and newer,
full-screen modals) and in `tools/modern_bundle.py` (the arm64 bundle's Info.plist and launch screen).

Local helpers (Windows PowerShell, no git required):

```powershell
$env:GH_TOKEN = 'github_pat_...'
.\tools\gh-push.ps1 -Repo user/aichat-ios6 -Message "change"        # push via REST API
.\tools\gh-build.ps1 -Repo user/aichat-ios6 -Download -Install       # wait, fetch both builds, install on the iPad
.\tools\gh-build.ps1 -Repo user/aichat-ios6 -Download -InstallIPhone # ... or the arm64 .deb on the iPhone
.\tools\gh-release.ps1 -Repo user/aichat-ios6 -Tag v0.3.0 -AssetDir .\packages\run-123   # publish a release
. .\tools\ipad.ps1; Get-IPadCrashLogs; Get-IPadSyslog                 # debugging (iPad)
. .\tools\iphone.ps1; Get-IPhoneCrashLogs; Get-IPhoneLog              # debugging (iPhone)
```

## Project layout

- `src/Net` – Mbed TLS socket, HTTP/1.1 client, SSE parser, OpenRouter client
- `src/Chat` – conversation engine (vision relay, context building, streaming)
- `src/Model` – settings, models catalog, messages, attachments, storage
- `src/Markdown` – Markdown and LaTeX to attributed-string blocks
- `src/UI` – chat, composer, pickers, settings
- `src/Util/ORModern.m` – what iOS 7 and newer need to look and behave like iOS 6 (no-op on iOS 6)
- `vendor` – Mbed TLS config and platform glue (Mbed TLS and iosMath are fetched at build time)
- `tools` – asset generator, the arm64 bundle script and PowerShell helpers

## Contributing

Pull requests are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md). You do not need a Mac: fork the
repository, push, and GitHub Actions builds the packages for you.

## License

[MIT](LICENSE), copyright (c) 2026 samcejko. You may fork, modify and redistribute the app, as long
as the copyright notice and the license text stay with every copy. A link back to this repository
is appreciated.

Mbed TLS (Apache-2.0), iosMath (MIT), the Latin Modern Math font (GUST Font License) and the Mozilla
CA bundle from curl.se (MPL-2.0) are downloaded at build time and included in the released packages
under their own licenses, see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
Changes are listed in [CHANGELOG.md](CHANGELOG.md).

This is an independent hobby project, not affiliated with OpenRouter or Apple.
