cask "buffer" do
  arch arm: "Silicon", intel: "Intel"

  version "latest"
  sha256 :no_check

  url "https://github.com/samirpatil2000/Buffer/releases/latest/download/Buffer_#{arch}.dmg",
      verified: "github.com/samirpatil2000/Buffer/"
  name "Buffer"
  desc "Lightweight clipboard manager for macOS"
  homepage "https://github.com/samirpatil2000/Buffer"

  depends_on macos: ">= :ventura"

  app "Buffer.app"

  zap trash: [
    "~/Library/Application Support/Buffer",
    "~/Library/Containers/com.samirpatil.Buffer",
    "~/Library/Preferences/com.samirpatil.Buffer.plist",
    "~/Library/Saved Application State/com.samirpatil.Buffer.savedState",
  ]
end
