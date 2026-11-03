# Homebrew cask. Lives in the tap repository (ya-makariy/homebrew-tap) as Casks/to-review.rb;
# the release workflow bumps version/sha256 there automatically.
cask "to-review" do
  version "0.1.2"
  sha256 "510f10674bb468f219788e4d67c32d893679fad0399af25b46bd91b775741b80"

  url "https://github.com/ya-makariy/to-review/releases/download/v#{version}/ToReview-#{version}.zip"
  name "ToReview"
  desc "Menu-bar app and widgets for GitHub and GitLab pull requests waiting for your review"
  homepage "https://github.com/ya-makariy/to-review"

  depends_on macos: :tahoe

  app "ToReview.app"

  uninstall quit: "com.ya-makariy.toreview"

  zap trash: [
    "~/Library/Application Support/ToReview",
    "~/Library/Containers/com.ya-makariy.toreview",
    "~/Library/Containers/com.ya-makariy.toreview.widget",
  ]

  caveats <<~EOS
    ToReview is ad-hoc signed and not notarized, so macOS blocks the first launch.
    Either approve it once (open the app, dismiss the dialog, then
    System Settings > Privacy & Security > Open Anyway), or remove the quarantine flag:
      xattr -dr com.apple.quarantine "#{appdir}/ToReview.app"
    Later `brew upgrade` runs carry the approval forward.
  EOS
end
