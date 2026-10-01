# Brand sources

- `quolio-logo.svg` / `.png` — the approved notebook mascot with wordmark (wink + open smile).
- `AppIcon.svg` — the app icon: notebook only, on a warm cream tile. To rebuild `AppIcon.png`:
  render it at 1024×1024 with headless Chrome (`--window-size=1024,1024 --screenshot`) and flatten
  with `magick icon.png -alpha off AppIcon.png` into `InstantNotes/Assets.xcassets/AppIcon.appiconset/`.
- `splash/` — source of the launch animation (canvas, 5.8 s). `node Brand/splash/build.mjs` regenerates
  `InstantNotes/Views/Launch/QuolioSplash.html`, which `LaunchSplashView` plays in a web view.
