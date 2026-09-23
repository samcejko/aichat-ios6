# AI Chat for iOS 6

Universal (iPhone + iPad) OpenRouter chat client for **jailbroken iOS 6.x** devices (armv7, e.g. iPad 2).

Why it is special: openrouter.ai only speaks TLS 1.2/1.3 with AEAD cipher suites, which the iOS 6
networking stack cannot negotiate. The app therefore ships its own TLS stack (mbedTLS) and a tiny
HTTP/1.1 client, so everything runs on the device without any relay server.

## Features

- OpenRouter API key onboarding, key status and free-tier daily counter
- Model picker with search, "free only" / "images" filters and sorting; remembers the last model
- Streaming replies with Markdown rendering (headings, lists, code blocks, tables, quotes)
- Photos (library, camera, clipboard) and files (iTunes File Sharing, "Open in…")
- Vision relay: when the chosen model cannot see images, a configurable vision helper model
  describes them and the description is passed on
- PDF via OpenRouter's file parser; docx/xlsx/pptx/odt/ods/odp/html/rtf converted to text on device
- Chat history, glossy iOS 6 look with light and dark themes, English and Czech

## Building (GitHub Actions)

No Mac needed. Pushing to `main` runs `.github/workflows/build.yml` on Ubuntu with Theos, the
iOS 9.3 SDK (deployment target 6.0) and mbedTLS. Artifacts: `AIChat-<version>.ipa` and a `.deb`.

Local helpers (Windows PowerShell, no git required):

```powershell
$env:GH_TOKEN = 'github_pat_...'
.\tools\gh-push.ps1 -Repo user/aichat-ios6 -Message "change"        # push via REST API
.\tools\gh-build.ps1 -Repo user/aichat-ios6 -Download -Install       # wait, fetch, install over SSH
. .\tools\ipad.ps1; Get-IPadCrashLogs; Get-IPadSyslog                 # debugging
```

## Installing on the device

1. Cydia: **AppSync Unified** (repo `https://cydia.akemi.ai/`) and **IPA Installer Console** (BigBoss),
   plus OpenSSH for the helper scripts.
2. Copy the `.ipa` to the device and run `ipainstaller -f AIChat.ipa`, or use iFunBox / 3uTools.
   The `.deb` works too (`dpkg -i`, then `uicache`) and installs into `/Applications`.

## Project layout

- `src/Net` – mbedTLS socket, HTTP/1.1 client, SSE parser, OpenRouter client
- `src/Chat` – conversation engine (vision relay, context building, streaming)
- `src/Model` – settings, models catalog, messages, attachments, storage
- `src/Markdown` – Markdown to attributed-string blocks
- `src/UI` – chat, composer, pickers, settings
- `vendor` – mbedTLS config and platform glue (mbedTLS itself is fetched at build time)
- `tools` – asset generator and PowerShell helpers
