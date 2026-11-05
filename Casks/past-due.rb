cask "past-due" do
  version "1.5.1"
  sha256 "3f53384af599a6c9d6125f99e7fa17e45318b1ceca08e88bd937c4e3fd4acaf8"

  url "https://github.com/michaelstonis/Past-Due/releases/download/v#{version}/Past-Due-#{version}.dmg"
  name "Past Due"
  desc "Software update checker and installer for macOS applications"
  homepage "https://github.com/michaelstonis/Past-Due"

  livecheck do
    url "https://raw.githubusercontent.com/michaelstonis/Past-Due/main/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on macos: :sequoia

  app "Past Due.app"
  binary "#{appdir}/Past Due.app/Contents/MacOS/Past Due", target: "past-due"

  zap trash: [
    "~/Library/Application Support/com.halfbuttonpress.PastDue",
    "~/Library/Caches/com.halfbuttonpress.PastDue",
    "~/Library/HTTPStorages/com.halfbuttonpress.PastDue",
    "~/Library/Preferences/com.halfbuttonpress.PastDue.plist",
    "~/Library/Saved Application State/com.halfbuttonpress.PastDue.savedState",
  ]
end
