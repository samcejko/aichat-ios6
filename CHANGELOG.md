# Changelog

## Unreleased

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
