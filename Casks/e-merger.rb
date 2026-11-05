cask "e-merger" do
  version "1.0.1"
  sha256 "7fc6d08f012e47ea4b8039e2c83666f0afd3490e47b94a04e3e5545e1f1f87d0"

  url "https://github.com/ersel95/e-merger/releases/download/v#{version}/E-Merger-#{version}.dmg"
  name "E-Merger"
  desc "Multi-account Bitbucket pull request approver & merger for macOS"
  homepage "https://github.com/ersel95/e-merger"

  app "E-Merger.app"

  zap trash: [
    "~/Library/Application Support/E-Merger",
  ]
end
