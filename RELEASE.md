# Buffer Release Workflow Guide

This guide outlines the step-by-step process to bump the version, build, notarize, and publish a new release of Buffer.

---

## Step 1: Pre-Release & Version Check

1. **Verify Git Status**:
   Ensure your working directory is clean and you are on the release branch (typically `main`).
   ```bash
   git status
   ```

2. **Inspect Previous Releases**:
   List existing release tags to identify the next version number.
   ```bash
   git tag --sort=-v:refname -n10
   ```

3. **Check Remote Status**:
   ```bash
   gh release list
   ```

---

## Step 2: Version Configuration Bumps

1. **Update Info.plist**:
   Open `Info.plist` and update the following values:
   - `CFBundleShortVersionString` $\rightarrow$ Target Version (e.g., `2.5.0`)
   - `CFBundleVersion` $\rightarrow$ Increment the Build Number integer (e.g., `7`)

2. **Update README.md**:
   Open `README.md` and update all references to the version string in the download badges and download URLs:
   - Update version strings in Shields.io badges.
   - Update direct download URLs for both **Silicon** and **Intel** DMGs to point to the new tag.

---

## Step 3: Compile, Sign & Notarize

Run the automated compilation and packaging script:
```bash
sh build_dmg.sh
```

**What this script automates:**
- Cleans build folders and temporary assets.
- Compiles the Swift application for `arm64` (Apple Silicon) and `x86_64` (Intel) architectures.
- Codesigns the `.app` packages with the Developer ID Application certificate.
- Creates `.zip` and `.dmg` archives for both architectures.
- Submits the DMGs to the Apple Notarization Service (`notarytool`) and waits for approval.
- Staples the notarization tickets to the DMGs.

Verify that the output files are present in the project root:
- `Buffer_Silicon.dmg` & `Buffer_Silicon.zip`
- `Buffer_Intel.dmg` & `Buffer_Intel.zip`

---

## Step 4: Update Homebrew Cask

Generate the updated `Casks/buffer.rb` with verified SHA256 checksums from the newly built DMGs:
```bash
./scripts/generate_homebrew_cask.sh
```

---

## Step 5: Publish to GitHub

1. **Commit and Push Changes**:
   ```bash
   git add Info.plist README.md Casks/buffer.rb
   git commit -m "release: bump version to v3.0.0"
   # Push explicitly using refs/heads/main to avoid conflict with any 'main' tag
   git push origin refs/heads/main
   ```

2. **Create GitHub Release**:
   Prepare a markdown file `release_notes.md` containing the release description, then run:
   ```bash
   gh release create buffer-v3.0.0 \
     Buffer_Silicon.dmg Buffer_Silicon.zip \
     Buffer_Intel.dmg Buffer_Intel.zip \
     --title "Buffer v3.0.0" \
     --notes-file release_notes.md
   ```
   *(Add `--prerelease` if publishing a pre-release).*

   > [!TIP]
   > Feature screenshots for release notes should be stored in `Assets/` and embedded with responsive centered tags:
   >
   > <p align="center">
   >   <img width="500" alt="History Size Tiers" src="Assets/history-size-tiers.png" />
   > </p>

---

## Step 6: Modifying or Updating an Existing Release

If you need to update an existing release (e.g., retagging to a newer commit, replacing binary assets, or promoting a pre-release):

1. **Update and Force Push Git Tag** (if re-targeting commit):
   ```bash
   git tag -fa buffer-v<version> -m "release: v<version>"
   git push origin refs/tags/buffer-v<version> --force
   ```

2. **Re-upload Asset Binaries** (overwrites existing files):
   ```bash
   gh release upload buffer-v<version> \
     Buffer_Silicon.dmg Buffer_Silicon.zip \
     Buffer_Intel.dmg Buffer_Intel.zip \
     --clobber
   ```

3. **Update Release Metadata & Notes**:
   ```bash
   gh release edit buffer-v<version> \
     --title "Buffer v<version>" \
     --notes-file release_notes.md \
     --prerelease=false \
     --latest
   ```

