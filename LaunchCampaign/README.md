# Launch campaigns

Each release campaign is a self-contained HTML document named `YYYY-MM-DD.html`.
`latest.json` identifies the campaign the macOS app checks at startup:

```json
{
  "date": "2026-10-20",
  "file": "2026-10-20.html"
}
```

The date must be a real calendar date in the exact `YYYY-MM-DD` format. The file
must equal that date followed by `.html`. Use a newer date for a new campaign;
keep existing documents available for reference. The app records the date only
after successfully displaying the page, and silently skips failed requests.

## Publish a campaign

1. Copy the newest HTML to a new date-named file. Update its release date and
   release notes, including every supported language. Do not invent version
   numbers; add version numbers only when the release versions are known.
2. Keep all styles, scripts, images, and QR data inside the HTML. Do not add
   external fonts, analytics, tracking, network requests, or native message
   handlers. Preserve the restrictive content security policy.
3. Keep `window.setCampaignLanguage(locale)` callable by the app. Accept a
   `lang` query parameter for standalone previews, normalize regional language
   tags, and fall back to English. Keep the visible language picker usable.
   Use CSS `prefers-color-scheme` for live system light/dark adaptation.
4. Verify each language, light/dark appearance, keyboard navigation, and narrow
   layouts. Scan the QR code and check the download link. The existing download
   destination is https://apps.apple.com/us/app/onlyremote/id6793657946.
5. Update `latest.json` after the HTML is ready. Commit and push the HTML and
   manifest together to `main`; if publishing separately, publish the HTML
   first and the manifest last. Confirm both raw URLs return the expected data
   before shipping an app that consumes them.

Production base URL:
`https://raw.githubusercontent.com/jacklandrin/OnlySwitch/main/LaunchCampaign/`

Supported languages: `en`, `zh-Hans`, `de`, `hr`, `tr`, `pl`, `fil`, `nl`, `it`,
`ru`, `es`, `ja`, `so`, `ko`, `fr`, `uk`, `sk`, `pt-BR`, `cs`.
