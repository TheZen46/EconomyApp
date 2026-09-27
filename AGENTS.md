# Workspace Operational Rules

## 1. Git Author Attribution & Identity
* All Git commits in this repository MUST be authored using the user's specific credentials:
  `ash
  git commit --author="The Zen <116784625+TheZen46@users.noreply.github.com>" -m "<message>"
  `
* Never author commits under generic agent identities.

## 2. Staging and Push Payload Safeguards
* **Heavy Asset Prevention**: NEVER stage or commit machine learning datasets (	ool/vlm_training/data/, 	raining_dataset/, raw images), virtual environments (.venv/), model checkpoints (*.safetensors, *.pt, output_lora/), or compiled binaries (*.dll, *.exe, *.so, *.dylib).
* **Pre-commit Verification**: Before committing updates, always inspect git diff --cached --name-only and confirm the staged file count and extensions are proportional to source changes.
* Ensure local .gitignore files contain rules for .venv/, output_lora/, data/, and compiled artifacts before bulk git add operations.

## 3. Environment & Asset Bundling Integrity
* When adding assets to pubspec.yaml, never declare gitignored secrets (e.g., .env) without:
  1. Bundling tracked fallback templates (e.g., .env.example).
  2. Providing CI pipeline initialization steps (cp .env.example .env).
  3. Providing resilient 	ry/catch fallbacks in main.dart.

## 4. Communication & Documentation Style
* Maintain a professional, technical, and precision-driven tone.
* The use of emojis is strictly forbidden in documentation, commit messages, changelogs, and responses.
