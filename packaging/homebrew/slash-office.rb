# Homebrew formula for Slash Office. Lives in github.com/egekolSlash/homebrew-tap as Formula/slash-office.rb.
# Builds from source: a locally built app is not quarantined, so Gatekeeper does not block it.
# scripts/release.sh prints the sha256 of the release tarball to put below.
class SlashOffice < Formula
  desc "Mac workspace for parallel Claude Code agents, with a little office view"
  homepage "https://github.com/egekolSlash/slash-office"
  url "https://github.com/egekolSlash/slash-office/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "RELEASE_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/egekolSlash/slash-office.git", branch: "main"

  depends_on xcode: ["26.0", :build]
  depends_on macos: :tahoe

  def install
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox"
    ENV["CODESIGN_IDENTITY"] = "-"
    system "scripts/make-app.sh", "build/SlashOffice.app"
    prefix.install "build/SlashOffice.app"
  end

  def caveats
    <<~EOS
      Slash Office was installed to:
        #{opt_prefix}/SlashOffice.app
      Homebrew can't write to /Applications. Open it with:
        open #{opt_prefix}/SlashOffice.app
      and keep it in the Dock (right-click its icon › Options › Keep in Dock).
    EOS
  end

  test do
    assert_predicate prefix/"SlashOffice.app/Contents/MacOS/AgentOffice", :executable?
  end
end
