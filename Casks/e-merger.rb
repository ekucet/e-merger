cask "e-merger" do
  version "1.0.0"
  sha256 "c81f8a2e0c04dfbd3ed5ae0c71a969cdde674ecd0230ad147512bccbe2e74b1d"

  url "https://github.com/ersel95/e-merger/releases/download/v#{version}/E-Merger-#{version}.dmg"
  name "E-Merger"
  desc "Multi-account Bitbucket pull request approver & merger for macOS"
  homepage "https://github.com/ersel95/e-merger"

  app "E-Merger.app"

  zap trash: [
    "~/Library/Application Support/E-Merger",
  ]
end
