cask "buffer" do
  version "1.6"

  if Hardware::CPU.arm?
    sha256 "2c3132215914962631a793164278f2d6290be2e16205266cb3e8a7e8e6ea8b00"
    url "https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Silicon.dmg"
  else
    sha256 "8c8684be5cada264be865686436e2544e5c4d5e13c506d926094921311832a46"
    url "https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Intel.dmg"
  end

  name "Buffer"
  desc "Lightweight clipboard manager for macOS"
  homepage "https://github.com/samirpatil2000/Buffer"

  depends_on macos: ">= :ventura"

  app "Buffer.app"

  zap trash: [
    "~/Library/Application Support/Buffer",
    "~/Library/Preferences/com.samirpatil.Buffer.plist",
  ]
end
