cask "espalier" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/btucker/espalier/releases/download/v#{version}/Espalier-#{version}.zip"
  name "Espalier"
  desc "Worktree-aware terminal multiplexer"
  homepage "https://github.com/btucker/espalier"

  depends_on macos: ">= :sonoma"

  app "Espalier.app"
  binary "#{appdir}/Espalier.app/Contents/Helpers/espalier"

  zap trash: [
    "~/Library/Application Support/Espalier",
    "~/Library/Preferences/com.espalier.app.plist",
    "~/Library/Caches/com.espalier.app",
  ]

  caveats <<~EOS
    Espalier is currently ad-hoc signed (not notarized). On first launch,
    macOS will refuse to open it. Right-click Espalier in Applications and
    choose "Open" to approve it once.
  EOS
end
