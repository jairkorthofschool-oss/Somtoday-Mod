# Somtoday Mod for iOS

A WKWebView app for iOS 15+ that loads the Somtoday student website with Somtoday
Mod injected, equivalent to the Android-WebView app in this repository. The IPA is
intended to be installed with [TrollStore](https://github.com/opa334/TrollStore),
which re-signs the app itself, so no Apple Developer account is needed.

## How it works

- All mod logic is **reused** from the shared extension source
  (`Chromium/scripts` + `Chromium/css`). Nothing was rewritten.
- `tools/generate_ios_bundle.py` (or `generate.php` at the repo root) generates
  `SomtodayMod/Resources/SomtodayMod-iOS.js`: one minified script with the CSS
  inlined and all images/fonts embedded as base64 data URIs (`platform: 'iOS'`).
- The native shell (`SomtodayMod/`) is a thin WKWebView host:
  - injects the bundle as a `WKUserScript` at document end
  - uses a mobile Safari user agent: the iOS 15 WebKit engine cannot run the
    desktop site's modern JavaScript (which is why the desktop user agent of
    the Android apps is not used here); Somtoday Mod also ships as a Safari
    userscript, so the mobile layout is fully supported
  - opens links outside Somtoday in Safari
  - shows the same skeleton loading screens as the Android-GeckoView app
  - receives the chosen theme via a `somtodaymod` script message handler
  - supports file uploads and JavaScript alert/confirm dialogs
  - mirrors the Android navigation rules: Somtoday (leerling, inloggen,
    som.today) always stays inside the app — including login redirects to
    Microsoft/Entra — while user-tapped external links on the student site
    open in Safari
  - retries failed loads a few times, then shows a tap-to-retry spinner
    overlay like the Android-WebView app
  - ships an app icon derived from the Android launcher foreground

Differences from other platforms (kept in line with the Android versions):
- Easter-egg sounds are disabled on iOS because WebKit cannot play Opus audio.
- Grade-image download and settings export/import are hidden because file
  downloads do not work inside WebKit on iOS (same as Android).
- The mod's own settings page lives inside the Somtoday site, just like on
  other platforms.

## Building the IPA (macOS with Xcode required)

```bash
cd iOS
./build_ipa.sh
```

The unsigned IPA is written to `iOS/build/SomtodayMod.ipa`. Install it by
opening the IPA in TrollStore, or via a direct link:

```
apple-magnifier://install?url=<https link to SomtodayMod.ipa>
```

### Updating the mod code

After changing files in `Chromium/` (or `Firefox/`), regenerate the bundle:

```bash
python3 iOS/tools/generate_ios_bundle.py Chromium
```

or run `generate.php` on a PHP server, which now also produces the iOS bundle.

Minimum iOS version is 15.0; the app uses no APIs from iOS 16 or newer.
