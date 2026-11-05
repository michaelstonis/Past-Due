cask "past-due" do
  version "1.6.0"
  sha256 "551d72f74bf43599356905c6915e84e289241220ed34ef3b79de4ab94a6181a4"

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
