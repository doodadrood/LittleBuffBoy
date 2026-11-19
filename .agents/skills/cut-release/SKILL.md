---
name: cut-release
description: >-
  Run tests, bump version in LittleBuffBoy.toc and LittleBuffBoy_Camelot.toc,
  commit, tag, and push to origin to trigger the GitHub Actions CurseForge
  release packager. Use when the user asks to "cut a release" or "publish an update".
---

# Release Protocol

Follow these steps whenever the user asks to cut a release or publish an update:

1. Run the test suite and confirm every spec passes:
   ```bash
   ./scripts/run_tests.sh
   ```
2. If there are uncommitted feature/bugfix changes, commit them first with descriptive Conventional Commit messages (`feat: ...`, `fix: ...`) so `BigWigsMods/packager` includes them in the CurseForge changelog.
3. Bump `## Version:` in BOTH `LittleBuffBoy.toc` and `LittleBuffBoy_Camelot.toc` (preserving line endings).
4. Stage and commit the version bump:
   ```bash
   git add LittleBuffBoy.toc LittleBuffBoy_Camelot.toc
   git commit -m "chore: bump version to <version>"
   ```
5. Create the annotated/lightweight release tag matching `v<version>`:
   ```bash
   git tag v<version>
   ```
6. Push `main` and the new tag to `origin` (triggers `.github/workflows/release.yml` -> Busted tests -> CurseForge upload):
   ```bash
   git push origin main --tags
   ```
7. Verify the triggered GitHub Actions workflow completes with `conclusion: success`.
