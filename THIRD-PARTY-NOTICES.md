# Third-party notices

AI Chat itself contains no third-party source code in this repository. The build (see
`.github/workflows/build.yml`) downloads the components below and compiles or copies them into the
app. The released `.ipa` and `.deb` therefore contain them, and the full license texts are shipped
inside the app bundle in the `licenses/` folder.

## Mbed TLS 3.6.7

- TLS 1.2/1.3, X.509 and cryptography used for every HTTPS connection of the app
- Copyright The Mbed TLS Contributors
- License: Apache-2.0 OR GPL-2.0-or-later (used here under Apache-2.0)
- https://github.com/Mbed-TLS/mbedtls
- Changes: built with the configuration in `vendor/mbedtls_config_ios6.h` and the platform glue in
  `vendor/mbedtls_glue.c`; the library sources are not modified

## iosMath 0.9.5

- Typesetting of LaTeX formulas
- Copyright (c) 2013 MathChat (Kostub Deshmukh)
- License: MIT
- https://github.com/kostub/iosMath

## Latin Modern Math

- Font used for the formulas (`mathFonts.bundle/latinmodern-math.otf`, distributed with iosMath)
- Copyright 2012-2014 B. Jackowski, P. Strzelczyk and P. Pianowski (on behalf of TeX Users Groups)
- License: GUST Font License (GFL), https://www.gust.org.pl/projects/e-foundry/licenses
- https://www.gust.org.pl/projects/e-foundry/lm-math

## CA certificate bundle

- `cacert.pem`, the Mozilla CA certificate store converted to PEM by the curl project
- License: MPL-2.0
- https://curl.se/docs/caextract.html

## Not affiliated

OpenRouter is a service and trademark of OpenRouter, Inc. This project is an independent client and
is not affiliated with or endorsed by OpenRouter, Apple or any model provider.
