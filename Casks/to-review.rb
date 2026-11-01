# Homebrew cask template. Lives in the tap repository (ya-makariy/homebrew-tap) as
# Casks/to-review.rb; bump version/sha256 from dist/ToReview-<version>.zip.sha256.
cask "to-review" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/ya-makariy/to-review/releases/download/v#{version}/ToReview-#{version}.zip"
  name "ToReview"
  desc "Menu-bar app and widgets for GitHub and GitLab pull requests waiting for your review"
  homepage "https://github.com/ya-makariy/to-review"

  depends_on macos: ">= :tahoe"

  app "ToReview.app"

  # The app is ad-hoc signed and not notarized.
  caveats <<~EOS
    ToReview is not notarized. Install with:
      brew install --cask --no-quarantine ya-makariy/tap/to-review
    or remove the quarantine flag manually:
      xattr -d com.apple.quarantine "#{appdir}/ToReview.app"
  EOS

  zap trash: [
    "~/Library/Application Support/ToReview",
    "~/Library/Containers/com.ya-makariy.toreview",
    "~/Library/Containers/com.ya-makariy.toreview.widget",
  ]
end
