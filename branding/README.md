# Branding drop folder

Drop your generated assets here and I'll wire them into the extension, popup, website, and
Flutter app from this single location.

```
branding/
  logos/
    logo-full.svg        wordmark + mark, used on the website header and pricing/checkout pages
    logo-full.png        same, raster fallback (PNG, transparent background)
  icons/
    icon-mark.png         square icon-only mark, at least 512x512, transparent background
                           (this is the source I'll downscale to 16/48/128 for the extension
                           and to the Flutter app icon / launcher icon)
  brand.json             optional: hex codes + font names, see template below
```

## brand.json template (optional)

If you have exact hex codes / fonts, drop a `brand.json` here like:

```json
{
  "colors": {
    "primary": "#4F8CFF",
    "background": "#0B0F14",
    "surface": "#121821",
    "text": "#E8EDF4",
    "success": "#34C77B",
    "warning": "#F4B740",
    "danger": "#EF5466"
  },
  "fonts": {
    "heading": "Your Font Name",
    "body": "Your Font Name"
  }
}
```

If you skip this, I'll keep the current palette (already used across `redactr-website/css/styles.css`,
`redactr-extension/popup/popup.css`, and `redactr_app/lib/theme/app_theme.dart`) and only swap the
logo/icon imagery.

## What happens once files land here

- `icons/icon-mark.png` → regenerated into `redactr-extension/icons/icon{16,48,128}.png` and the
  Flutter Android/iOS/web launcher icons.
- `logos/logo-full.(svg|png)` → copied into `redactr-website/assets/` and referenced from the site
  header (replacing the current "Redactr" text logo) and into `redactr_app/assets/branding/` for
  use in the app's dashboard app bar.
- `brand.json` → color tokens updated in `styles.css`, `popup.css`, and `AppColors` in
  `app_theme.dart`.

Nothing here is consumed automatically — tell me once files are in place and I'll do the wiring.
