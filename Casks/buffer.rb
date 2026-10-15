cask "buffer" do
  version "3.0.0"

  on_arm do
    sha256 "1f7672b4750b5457c36258eefa006c4e6b1d42790e4d7cd3020f80ca29415a43"
    url "https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Silicon.dmg"
  end
  on_intel do
    sha256 "63c008ea99661cb206ff875c2053c3caef569fc31ef2301381861d332fc214b8"
    url "https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Intel.dmg"
  end

  name "Buffer"
  desc "Lightweight clipboard manager for macOS"
  homepage "https://github.com/samirpatil2000/Buffer"

  auto_updates true
  depends_on macos: :ventura

  app "Buffer.app"

  zap trash: [
    "~/Library/Application Support/Buffer",
    "~/Library/Caches/com.samirpatil.Buffer",
    "~/Library/Preferences/com.samirpatil.Buffer.plist",
  ]
end
