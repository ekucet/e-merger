cask "e-merger" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/ersel95/e-merger/releases/download/v#{version}/E-Merger-#{version}.dmg"
  name "E-Merger"
  desc "Multi-account Bitbucket pull request approver & merger for macOS"
  homepage "https://github.com/ersel95/e-merger"

  app "E-Merger.app"

  zap trash: [
    "~/Library/Application Support/E-Merger",
  ]
end
