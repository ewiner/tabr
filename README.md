# Tabr

A macOS app that automatically finds and displays guitar tabs for whatever song is currently playing on your Mac. It monitors the system's Now Playing info and fetches matching tabs from Ultimate Guitar, displaying them in a clean, dark UI.

## Caveats

1. **This app was entirely vibecoded** by Claude (Opus 4.6) with no human code review.
2. **Tab content is scraped from Ultimate Guitar**, which makes it inherently brittle and subject to breaking if UG changes their page structure. I (the author) am a paid UG subscriber and have no moral qualms about this, but YMMV.

## Building

Requires macOS 14+ and Swift 6.2.

```bash
swift build
./build.sh  # creates Tabr.app bundle
```

## License

MIT
