# Past Due

> **A Reverent Continuation of [Latest](https://github.com/mangerlahn/Latest)**
>
> **Past Due** is an actively maintained fork and continuation of [**Latest**](https://github.com/mangerlahn/Latest), originally created and lovingly crafted by [**Max Langer**](https://max.codes) (`@mangerlahn`). Because the original *Latest* repository is no longer actively maintained, *Past Due* carries forward Max's vision, design, and final unreleased `0.12` work—fixing community-reported issues, modernizing for macOS Sequoia (15) and macOS Tahoe (26+), and adding direct Homebrew Cask update support, background update notifications, a menu bar item, and a command-line interface.
>
> All credit for the foundational architecture, user interface, and years of stewardship belongs to [Max Langer](https://github.com/mangerlahn) and the original [Latest contributors](https://github.com/mangerlahn/Latest/graphs/contributors). If you appreciate the years of work that made this app possible, please consider [supporting Max Langer directly](https://max.codes/latest/donate/).

---

**Past Due** is a free and open-source utility app for macOS that checks if all of your installed apps are up to date. Get a quick, unified overview of which apps have updates waiting, read their release notes, and update them right away.

## Features

- **Mac App Store Updates**: Checks and installs Mac App Store updates directly in-app (including a privileged background installer helper for macOS 15.7+ and macOS 26+) with localized release notes.
- **Sparkle Updates**: Checks and installs updates for Sparkle-powered macOS apps with automatic CPU architecture (`arm64` / `x86_64`) compatibility verification.
- **Homebrew Cask Updates**: Checks installed apps against the Homebrew Cask catalog using bundle-identifier matching and updates them directly in-app via `brew upgrade --cask` when Homebrew is installed.
- **Background Update Checks & Notifications**: Optionally check for updates in the background on a schedule (Every 6 Hours, Daily, or Weekly), launch at login, and receive native macOS notifications when new updates arrive.
- **Menu Bar Extra**: Optional macOS menu bar item showing the live count of available updates with one-click access to **Update All** and individual app updates.
- **Command Line Interface (`past-due`)**: Built-in headless CLI for listing and installing app updates from the terminal or scripts.
- **Flexible Scan Locations**: Monitor `/Applications`, `~/Applications`, and any custom application folders, with per-folder checkboxes in **Settings → Locations** to toggle individual directories on or off.

![Past Due](./latest.png)

## System Requirements

- **macOS 15.0 (Sequoia)** or later (including **macOS 26 Tahoe** and **macOS 27**)

## Installation

### Homebrew Cask

You can install **Past Due** via Homebrew using the repository's built-in tap:

```bash
brew tap michaelstonis/past-due https://github.com/michaelstonis/Past-Due
brew install --cask past-due
```

To upgrade later:

```bash
brew upgrade --cask past-due
```

### Direct Download

Download the latest signed and notarized `Past-Due-<version>.dmg` from the [Releases](https://github.com/michaelstonis/Past-Due/releases) page, open it, and drag **Past Due.app** into your `/Applications` folder.

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

## Command Line Interface (`past-due`)

To install the `past-due` command into `/usr/local/bin/past-due`, open **Past Due → Settings… (`⌘,`) → General** and click **Install 'past-due' Command…**.

```bash
# List applications with available updates
past-due list

# List all scanned applications (including up-to-date apps)
past-due list --all

# Output available updates as JSON
past-due list --json

# Install all directly updatable app updates
past-due update --all

# Install updates for specific apps by name or bundle identifier
past-due update "Wireshark" com.Figma.Desktop
```

## Contributing & Issues

Have an idea for an improvement or encountered a bug? Check out the [Issues](https://github.com/michaelstonis/Past-Due/issues) page! High-priority issues and community pull requests from the original `mangerlahn/Latest` repository have been triaged and integrated here.

### Translations

Original localizations were contributed by the community via [Weblate](https://hosted.weblate.org/engage/latest/). Translation improvements and pull requests are always welcome.

## License & Credits

- **Original Author**: [Max Langer](https://max.codes) — Creator of [Latest](https://github.com/mangerlahn/Latest) (Copyright © 2017–2026 Max Langer)
- **Continuation Maintainer**: [Michael Stonis](https://github.com/michaelstonis) (Copyright © 2026 Michael Stonis)
- Licensed under the [MIT License](./LICENSE).
