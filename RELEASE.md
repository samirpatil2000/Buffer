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
   - `CFBundleShortVersionString` $\rightarrow$ Target Version (e.g., `2.3.0`)
   - `CFBundleVersion` $\rightarrow$ Increment the Build Number integer (e.g., `5`)

2. **Update README.md**:
   Open `README.md` and update all references to the version string in the download badges and download URLs:
   - For Shields.io badges, escape dashes with a double dash (e.g. `v2.3.0` stays normal, but a hyphenated suffix like `v2.3.0-beta.1` must be formatted as `v2.3.0--beta.1`).
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

## Step 4: Publish to GitHub

1. **Commit and Push Changes**:
   ```bash
   git add Info.plist README.md
   git commit -m "release: bump version to v2.3.0"
   # Push explicitly using refs/heads/main to avoid conflict with any 'main' tag
   git push origin refs/heads/main
   ```

2. **Create GitHub Release**:
   Prepare a markdown file `release_notes.md` containing the release description, then run:
   ```bash
   gh release create buffer-v2.3.0 \
     Buffer_Silicon.dmg Buffer_Silicon.zip \
     Buffer_Intel.dmg Buffer_Intel.zip \
     --title "Buffer v2.3.0" \
     --notes-file release_notes.md \
     --prerelease
   ```
   *(Omit `--prerelease` if publishing a stable production release).*
