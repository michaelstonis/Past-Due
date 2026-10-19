# Past Due

> **A Reverent Continuation of [Latest](https://github.com/mangerlahn/Latest)**
>
> **Past Due** is an actively maintained fork and continuation of [**Latest**](https://github.com/mangerlahn/Latest), originally created and lovingly crafted by [**Max Langer**](https://max.codes) (`@mangerlahn`). Because the original *Latest* repository is no longer actively maintained, *Past Due* carries forward Max's vision, design, and final unreleased `0.12` work—fixing community-reported issues, modernizing for macOS Sequoia (15) and macOS Tahoe (26+), and adding direct Homebrew Cask update support.
>
> All credit for the foundational architecture, user interface, and years of stewardship belongs to [Max Langer](https://github.com/mangerlahn) and the original [Latest contributors](https://github.com/mangerlahn/Latest/graphs/contributors). If you appreciate the years of work that made this app possible, please consider [supporting Max Langer directly](https://max.codes/latest/donate/).

---

**Past Due** is a free and open-source utility app for macOS that checks if all of your installed apps are up to date. Get a quick, unified overview of which apps have updates waiting, read their release notes, and update them right away.

Past Due supports:
- **Mac App Store** apps (including a privileged background installer helper for macOS 15.7+ and macOS 26+)
- **Sparkle**-powered macOS apps
- **Homebrew Cask** apps (both version checking against the Homebrew Cask repository and direct in-app updates via `brew upgrade --cask` when Homebrew is installed)

![Past Due](./latest.png)

## System Requirements

- **macOS 15.0 (Sequoia)** or later (including **macOS 26 Tahoe** and **macOS 27**)

## Installation

### Download the App

Download the latest `Past-Due.dmg` or `.zip` archive from the [Releases](https://github.com/michaelstonis/Past-Due/releases) page, open it, and drag **Past Due.app** into your `/Applications` folder.

### Build from Source

**Xcode 16+ (or Xcode 26+) and Swift 5/6 are required.**

1. Clone the repository:
   ```bash
   git clone https://github.com/michaelstonis/Past-Due.git
   cd Past-Due
   ```
2. Build a release `.app` and `.dmg` using the packaging script:
   ```bash
   ./scripts/build_dmg.sh
   ```
   Or open `Latest.xcodeproj` in Xcode, select the **Latest** scheme, and hit **Build and Run** (`⌘R`). See [BUILD.md](./BUILD.md) for detailed build and code-signing instructions.

## Contributing & Issues

Have an idea for an improvement or encountered a bug? Check out the [Issues](https://github.com/michaelstonis/Past-Due/issues) page! High-priority issues and community pull requests from the original `mangerlahn/Latest` repository have been triaged and migrated here.

### Translations

Original localizations were contributed by the community via [Weblate](https://hosted.weblate.org/engage/latest/). Translation improvements and pull requests are always welcome.

## License & Credits

- **Original Author**: [Max Langer](https://max.codes) — Creator of [Latest](https://github.com/mangerlahn/Latest) (Copyright © 2017–2026 Max Langer)
- **Continuation Maintainer**: [Michael Stonis](https://github.com/michaelstonis) (Copyright © 2026 Michael Stonis)
- Licensed under the [MIT License](./LICENSE).
