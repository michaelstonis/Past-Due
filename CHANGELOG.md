# 1.4.0
#### New and Improved:
- **Skip This Version (Ignore Until Next Update)**: Right-click any app with an available update and choose **Skip Version X.Y.Z** to silence that specific version while still receiving notifications when the next version ships (#24 / upstream #49, #419).
- **Sort by Support Status**: Added **View → Sort By → Support Status** to group full-support, limited-support, and unsupported apps cleanly (#23 / upstream #554, PR #556).
- **Export Installed App List**: Added **File → Export App List… (`⇧⌘E`)** to export your discovered app inventory in **JSON** (`.json`), **Markdown** (`.md`), or **CSV** (`.csv`) format (#27 / upstream #281).
- **Auto-Recheck on Network Recovery & Wake**: Past Due now monitors network reachability (`NWPathMonitor`) and system wake events to automatically check for updates once connectivity becomes available (#25 / upstream #32).
- **Cached Startup & Non-Blocking Refreshes**: Restores the last known app list from cache immediately on launch, moves `AppListSnapshot` generation off the main thread, and warns before adding broad scan roots such as `/` or `$HOME` (#26 / upstream PR #566).

#### Bug Fixes:
- **Resilient Version Parsing & SemVer Build Metadata**: Removed the `fatalError` fallback in `Version.swift` on overflowing/non-ASCII version strings and stripped SemVer 2.0.0 build metadata (`+...`) before comparing versions to eliminate phantom updates (#20 / upstream PRs #598, #596).
- **Accurate Update Dates for Self-Updating & Reproducible Builds**: Resolved `App.Bundle.modificationDate` across the outer `.app` bundle, `Contents/Info.plist`, and `.addedToDirectoryDateKey` while ignoring `1980-01-01` (`1979-12-31` local) ZIP epochs (#21 / upstream #591, #468).
- **Homebrew Channel & Wrapper Filtering**: Prevented prerelease Homebrew casks (`@beta`, `@nightly`, `-preview`, etc.) from matching stable local apps, filtered out unversioned `version :latest` casks, and resolved Electron/Code-OSS product versions (such as Positron IDE) from `product.json` (#22 / upstream #567, #577, #552, #359).

# 1.3.0
#### New and Improved:
- **Menu Bar Extra**: Added an optional **Show Past Due in the menu bar** setting in **Settings → General** that displays an `NSStatusItem` with the live available update count, quick access to available updates, and an **Update All** action (#16 / upstream #64).
- **Toggleable Scan Directories**: Added per-folder checkboxes in **Settings → Locations** so default directories (`/Applications`, `~/Applications`) and custom folders can be toggled on or off individually (#19 / upstream #512, #445, #49).

#### Bug Fixes:
- Fixed the first column width in **Settings → General** so `Frequency:` and `Command Line:` labels size dynamically without clipping.
- Replaced remaining user-facing `"Latest"` strings across localized menu and UI `.strings` files with `"Past Due"`.

# 1.2.2
#### Bug Fixes:
- Improve version heading typography, spacing, and live reload refresh.

# 1.2.1
#### Bug Fixes:
- Fixed double bullets appearing in bulleted lists within the Release Notes view on modern macOS (TextKit 2).
- Fixed Sparkle `appcast.xml` and GitHub Releases so release notes are automatically generated and displayed for every version.

# 1.2.0
#### New and Improved:
- **Command Line Interface (`past-due`)**: Added a headless CLI for listing and installing macOS app updates directly from the terminal (`past-due list`, `past-due list --all`, `past-due list --json`, `past-due update [<app> ...]`, `past-due update --all`) (#17 / upstream #13).
- **One-Click CLI Installation**: Added a **Command Line: Install 'past-due' Command…** button in **Settings → General** to symlink `/usr/local/bin/past-due`.

# 1.1.0
#### New and Improved:
- **Scheduled Background Update Checks & Notifications**: Past Due can now check for updates automatically in the background (hourly, every 6 hours, every 12 hours, or daily) and post a native macOS notification when new app updates are discovered (#15 / upstream #162).
- **Open at Login**: Added an **Open Past Due at login** option in **Settings → General** using `SMAppService`.

#### Bug Fixes:
- Enabled **Include apps with limited support** by default on fresh installs so Homebrew Cask updates outside Caskroom are discovered out of the box.
- Improved the toolbar update-check progress indicator on macOS 15 and macOS 26 so it uses a clean borderless spinner and collapses its toolbar space when idle.

# 1.0.1
#### Bug Fixes:
- **Sparkle Architecture Verification**: Verify that a Sparkle appcast item supports the Mac's CPU architecture (`arm64` vs. `x86_64`) before reporting or installing an update, preventing Intel-only builds from overwriting Universal or Apple Silicon apps (#18 / upstream #377).

# 1.0.0 (Past Due)
First release of **Past Due**, a community-maintained continuation of [Max Langer](https://max.codes)'s [**Latest**](https://github.com/mangerlahn/Latest), which is no longer actively maintained upstream.

#### Highlights & Upstream `0.12-beta` Integration:
- Incorporates Max Langer's unreleased `0.12-beta` (`develop`) work, including the privileged background helper (`PastDueUpdateInstaller`) for Mac App Store updates on macOS 15.7+ and macOS 26+, macOS Tahoe Liquid Glass UI refinements, and updated localizations.
- Raises minimum deployment target to **macOS 15.0 (Sequoia)** and upgrades **Sparkle** to `2.10.0`.
- **Direct Homebrew Cask Updates**: Apps installed via Homebrew Cask can now be updated directly within Past Due using `brew upgrade --cask` (#9 / upstream PR #607).
- **Improved Homebrew Bundle-ID Matching**: Matches apps against Homebrew Casks by bundle identifier and plausibility rules to eliminate false-positive updates (#10 / upstream PR #606).
- **Localized Mac App Store Release Notes**: Fetches App Store metadata using your preferred storefront language when available (#12 / upstream PR #568).

#### Stability & Bug Fixes:
- Fixed a launch crash caused by empty `osVersion` strings or malformed entries in the Homebrew Cask JSON catalog (#1 / upstream #579, PR #584).
- Fixed an `NSTableView` exception (`RowView cannot be inserted twice`) during rapid app list updates (#2 / upstream #588).
- Replaced force-unwrapped `PropertyListSerialization` decoding when loading excluded app identifiers (#3 / upstream #572).
- Replaced deprecated `CVDisplayLink` with `CADisplayLink` and a fallback timer to prevent crashes when waking from display sleep (#4 / upstream #592).
- Fixed `SparkleUpdateOperation` progress throttling, thread safety, and timer lifecycle leaks (#5 / upstream #601).
- Fixed a retain cycle in `AppDataStore` observer closures (#6 / upstream PR #605).
- Replaced non-recursive `DispatchSource` folder watching with recursive `FSEvents` monitoring and balanced `DispatchGroup` calls in `BundleCollector` (#7 / upstream #316, PR #565).
- Fixed asymmetric build-number comparison in `Version` that caused false-positive updates when build numbers differed in format from marketing versions (#8 / upstream #549).
- Fixed Sparkle `SUFeedURL` lookup when app bundle paths contain spaces or non-ASCII characters (#11 / upstream PR #569).
- Added deterministic path tie-breaker sorting for duplicate app bundles (#13 / upstream #507).

# 0.10.3
Fixes a crash that may occur after updating to 0.10.2.

# 0.10.2
This update fixes more issues with the Homebrew check introduced in a recent update. Thank you for your continued reports, [please keep them coming][1]!

- Language support for:
	- Hebrew
	- Serbian (Thanks smudja)!
	- Various tweaks to other languages.


# 0.10.1
This update fixes many issues with the Homebrew check introduced in the last update. Sorry for the inconvenience and thanks for the numerous reports highlighting these issues. [Please keep them coming][2]!
 
- Improvements to update checking:
	- Fix many cases where an update would be shown for up to date apps
	- Fix using wrong app variant for version checking
	- Ignore certain apps with unclear version information
	- Ignore Safari web apps in update checks
	- Ignore apps without version information

- Various interface improvements:
	- Clarify which apps can be updated within Latest
	- Tweak interface when search did not find any apps

- Fixes a crash some people encountered that would occur when launching the app.

- Language support for:
	- Bulgarian (Thanks Desislav!)
	- Romanian (Thanks arsradu!)
	- Turkish (Thanks Hakan!)
- Tweaks for many languages, including Italian, Korean & Slovak (Thanks everyone!)


# 0.10
#### New and Improved:
- Added update checking via Homebrew Cask, which should allow for many more updates to be found
- The app list is now sorted by recently updated apps. Sort by app name can be restored via the main menu: View \> Sort By \> Name
- Improved messages when no release notes are available
- Interface improvements for macOS Sonoma

- Language support for:
	- Arabic (Thanks Hussain & Nas!)
	- Traditional Chinese (Thanks Pan!)
	- Filipino (Thanks Gean Paulo!)
	- Polish (Thanks Konrad!)
	- Portugiese (Brasilian) (Thanks Felipe!)
- Tweaks for many languages, including Czech, Italian and Swedish (Thanks Jiří, Francesco, Peeter and all the others!)

#### Bug Fixes:
- Fixed a crash when updating apps via context menu
- Fixed an UI crash when updating apps
- Fixed cases in which the update button would be hidden
- Attempt to fix app list being empty
- The Update All button now only updates apps within Latest (no other apps will be opened)
- Fixed loading of release notes for certain apps

# 0.9
#### New and Improved:
- Apps from the Mac App Store can be updated from within Latest
- Ignored Apps can be shown independent of installed apps
- Updates only show up if they are compatible with the installed operating system
- Show installed apps by default

- Language Support for Czech (Thanks Lubos!)
- Language Support for Hungarian (Thanks Barczi!)
- Language Support for Indonesian (Thanks Adrian!)
- Language Support for Norwegian Bokmål (Thanks Sander!)
- Language Support for Persian (Thanks Shayan!)
- Language Support for Swedish (Thanks Tygyh & Peter!)
- Language Support for Ukrainian (Thanks Ihor!)

#### Bug Fixes
- Tweaked Croatian localization (Thanks Milo!)
- Fixed empty app list when spotlight search is disabled (Thanks Mikhail!)
- Latest now remembers the width of the update list
- Fixed a crash with non-western arabic numerals in version numbers

# 0.8.3
- Language Support for Catalan (Thanks Maite!)
- Language Support for Dutch (Thanks Eitot!)
- Language Support for Greek (Thanks Efthymis!)
- Language Support for Spanish (Thanks Darío!)
- Language Support for Simplified Chinese
- Hopefully fixed some crashes around updating apps.

# 0.8.2
- Language Support for Portuguese (Thanks Filipe!)
- It should also fix a crash on launch occurring on macOS 10.13. Sorry about that!

# 0.8.1
#### New and Improved:
- Language Support for various languages like:
	- Croatian (Thanks Milo!)
	- Italian (Thanks Christiano!)
	- Korean (Thanks 이정희!)
	- Malay (Thanks Rosdi!)
	- Slovak (Thanks Marek!)
- Tweaked French Localization (Thanks J. Lavoie!)
- Tweaked German Localization
More langauges like Arabic, Catalan, Chinese, Indonesian and Norwegian are well on the way.

#### Now Fixed:
- Added a fallback to look for files manually if Spotlight is not available (Thanks mbarashkov!)
- Apps using DevMate should now correctly update though Latest
- Smaller UI fixes
# 0.8
#### New and Improved:
- The Update All button returned to the toolbar. (Thanks [decodism][3]!)
- Icons of unsupported apps are now dimmed in the app list. (Thanks decodism!)
- Added an action to open apps right from app list.  

#### Now Fixed:
- Latest should be much more stable when apps are updated.
- Latest mistakenly showed updates for iPad versions of apps, fixed.
- The progress indicator on updates animates at normal speed on displays with high refresh rate.
- Fixed a crash when opening release notes that requested an unknown font.  

# 0.7.3
Version 0.7.3 fixes a crash that occurred when updating apps.

# 0.7.2
Version 0.7.2 provides smaller fixes and UI improvements:
- The source icon for each app is now displayed alongside the release notes instead of the app list.
- Tweaked the update button size and animations
- Fixes disabled "Update All" menu item
- Apps contained in other apps are no longer listed

# 0.7.1
Version 0.7.1 fixes a crash on launch that occurred for some people.

# 0.7
#### What's New:
- Refined interface with support for macOS Big Sur
- Runs natively on M1 Macs
- Adds Update checking support for iOS apps installed from the Mac App Store (M1 Macs only)
- Latest is now available in French (Thanks [Flavien][4]!)
- A little icon next to an app's name shows its source (Mac App Store or Web)
- Adds an option to display unsupported apps in the update list, they appear greyed out

#### Improvements:
- Apps in your User-Application folder are now checked as well
- Latest automatically quits when closing the window

#### Now Fixed:
- Some supported apps would not appear (Thanks [Simeon][5]!)
- The window would not maximize when minimized in the dock
- Fixed a crash when right-clicking insite the update list
- Fixed a crash when quitting Latest or updating apps while Latest is open

# 0.6.3
#### Now Fixed:
- Fixed a crash that occurred when searching for apps.

# 0.6.2
#### Improved:
- Better handling of empty selection in the update list
- Significant faster startup time for some users
- Apps are inserted faster into the list on update checks

#### Now Fixed:
- Fixed a crash that occurred after update checks.
- Minor interface and localisation fixes.

> Note: This update removes the ability to update apps from the Mac App Store directly in Latest. I plan to bring this feature back in one of the next updates.

# 0.6.1
#### Now Fixed:
- Fixed a crash that occurred after update checks.
- Minor interface and localisation fixes.

# 0.6
#### Whats New and Improved:
- Add ability to update apps within Latest! (#9)
- Add ability to ignore certain apps. (#17)

#### Now Fixed:
- Improvements to the update list and Touch Bar integration.
- Add link to website (#44) and donations page.

# 0.5
#### Whats New and Improved:
- Add search functionality to quickly browse apps by their name.
- Apps within the Setapp folder are ignored for now, as the update might not be available yet.

#### Now Fixed:
- Various graphics issues in the release notes

# 0.4.5
This is basically version 0.4.4, but there was an issue with codesigning so many people were not able to open the app. I am very sorry about that!

# 0.4.4
#### Now Fixed:
- Includes basic state restoration
- Fixes for the release notes in macOS Mojave

# 0.4.3
Version 0.4.3 slightly improves the way Latest handles offline situations and fixes a bug that caused apps in the update list to disappear after reload.

# 0.4.2
This update fixes some cases where the app could crash based on [\#25][6].

# 0.4.1
#### Now Fixed:
- Improvements to the Sparkle parser for better quality of information and filtering of unsupported apps (partly [\#27][7])
- The "Open All" button really opened all installed apps! ([\#26][8])

# 0.4
#### Whats new:
- Redesigned, uniform Release Notes ([\#3][9])
- Touch Bar Support ([\#20][10])
- Latest can show already installed updates ([\#15][11])
- Latest now searches subfolders for updates ([\#22][12])

#### Thats fixed:
- Apps will no longer disappear after reload ([\#21][13], [\#23][14])
- Some release notes failed to load ([\#24][15])

# 0.3.2
#### Now Fixed:
- Sparkle Apps deployed with DevMate are now supported
- Use a new version checker to hopefully cover more cases correctly
- Improvements to the checkers performance
- Fix stuck progress bar

# 0.3.1
- Latest can now update itself through Sparkle

# 0.3
- App reloads if an app gets updated
- Small UI tweaks

[1]:	https://github.com/mangerlahn/Latest/issues
[2]:	https://github.com/mangerlahn/Latest/issues
[3]:	https://github.com/decodism
[4]:	https://github.com/flavienbonvin
[5]:	https://github.com/sleifer
[6]:	https://github.com/mangerlahn/Latest/issues/25
[7]:	https://github.com/mangerlahn/Latest/issues/27
[8]:	https://github.com/mangerlahn/Latest/issues/26
[9]:	https://github.com/mangerlahn/Latest/issues/3
[10]:	https://github.com/mangerlahn/Latest/issues/20
[11]:	https://github.com/mangerlahn/Latest/issues/15
[12]:	https://github.com/mangerlahn/Latest/issues/22
[13]:	https://github.com/mangerlahn/Latest/issues/21
[14]:	https://github.com/mangerlahn/Latest/issues/23
[15]:	https://github.com/mangerlahn/Latest/issues/24