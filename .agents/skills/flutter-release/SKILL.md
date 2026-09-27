---
name: flutter-release
description: >-
  Standard operating procedure for preparing, validating, and publishing Flutter/Dart releases for EconomyApp.
  Use when the user requests a new version bump, changelog generation, or release tagging.
---

# Flutter Release & Tagging Workflow

## Release Preparation Procedure

### 1. Version Bumping
Synchronize the new version identifier across:
1. `pubspec.yaml`: Update `version: x.y.z+b`.
2. `package.json`: Update `"version": "x.y.z"`.
3. `CHANGELOG.md`: Prepend the release notes section with technical highlights.

### 2. Pre-Commit Payload Validation
Verify that no heavy binary or dataset artifacts are staged:
```bash
git diff --cached --name-only | Select-String "\.(dll|exe|so|dylib|a|lib|safetensors|pt|pth|bin|gguf|jpg|png|zip)$"
```
Ensure total staged file count is verified before committing.

### 3. Execution & Push
```bash
git commit --author="The Zen <116784625+TheZen46@users.noreply.github.com>" -m "chore(release): release version x.y.z - <summary>"
git tag -a vx.y.z -m "Release version x.y.z"
git push origin main
git push origin vx.y.z
```
