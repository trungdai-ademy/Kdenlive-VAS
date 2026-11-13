# Kdenlive-VAS

[Kdenlive](https://kdenlive.org) **26.08.2** with a small live-control module used by **Vietnews AI Studio (VAS)**, so that the user and the
AI assistant can edit the *same* open timeline: the AI reads the timeline model held in memory (no need to save) and sends edits that go
through Kdenlive's own timeline model, each one a normal undo step the user can revert with Ctrl+Z.

This repository does **not** contain a copy of Kdenlive. It contains:

| Path | What |
|---|---|
| `patches/` | Changes on top of the upstream tag `v26.08.2` of https://invent.kde.org/multimedia/kdenlive (applied in order) |
| `patches/mlt/` | Changes on top of MLT (https://github.com/mltframework/mlt), at the exact commit KDE Craft builds for Kdenlive (`7a3319f`, pinned in the workflow) |
| `craft/CraftConfig.ini` | KDE Craft configuration, adapted from KDE's own CI (`sysadmin/craft-ci`, `qt6/CraftConfig.ini`) |
| `.github/workflows/build-windows.yml` | Builds the Windows package the same way KDE's CI does (CraftMaster), publishes it as a pre-release |

## The VAS module (`patches/0001-vas-live-control-bridge.patch`)

- **Inactive unless VAS starts Kdenlive** with the environment variables `VAS_KDENLIVE_PIPE` and `VAS_KDENLIVE_TOKEN`. Started any other
  way, this build behaves exactly like upstream Kdenlive.
- Local server (`QLocalServer::UserAccessOption`, the same mechanism as Kdenlive's `RenderServer`): only processes of the same OS user can
  connect, and every request must carry the per-launch secret (removed from the environment right after start, so render jobs and other
  child processes never see it).
- Fixed operation list: `state`, `move`, `cut`, `resize`, `delete`, `insert` (clip already in the project bin), `effect` (Kdenlive effect
  id), `seek`, `save`. Every argument is type- and range-checked; no file path, script or expression is ever accepted. VAS Desk validates
  every AI request again before forwarding it.
- Edits use the timeline model's `request*` functions with undo logging, so they behave exactly like edits made with the mouse.

## MLT patch (`patches/mlt/0001-melt-windows-exit-without-teardown.patch`)

On Windows, `melt` crashes at exit (access violation in `Qt6Core.dll`, `QSystemLocale::query`) after every render that loaded the Qt
module (`qtext`, `kdenlivetitle`, ...): the module creates a `QApplication` and never destroys it, and since #1175 melt returns without
closing services, so the DLL teardown destroys Qt's locale data first. The output is complete and the exit status is 0, but each run
raises an APPCRASH report and Windows Error Reporting delays the exit by seconds (measured on a real VAS machine: 1,636 crashes in 7 days).
The patch (Windows only) wraps melt's `main`: on every path out of it (render, `-query`, `-version`, errors) streams are flushed and
the process ends, skipping the teardown. Output is already complete at that point (a started consumer has been stopped: the avformat
thread wrote the trailer and closed the file; the xml consumer writes synchronously). To be proposed upstream.

## Licence

Kdenlive is free software released under the GNU General Public License, version 3 (see `LICENSE`, copied from Kdenlive's
`LICENSES/GPL-3.0-only.txt`). The Kdenlive patches in this repository are released under the same terms
(`GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL`, as upstream). MLT is released under the GNU LGPL 2.1 (framework, modules) and the
melt command-line program (`src/melt/`) under the GNU GPL 2.0 or later; the MLT patch changes `src/melt/melt.c` only and is released under
the GPL 2.0 or later, as that file. Binaries built by the workflow are built from the upstream tag plus these
patches only; the exact commit of this repository is recorded in each release.

Kdenlive is a trademark of KDE e.V.; this is an unofficial build and is not endorsed by the Kdenlive team. Bugs found with this build should
first be reproduced with the official Kdenlive before being reported upstream.

## Building

Push to `main` (or run the workflow manually). The job:
1. clones `v26.08.2` from invent.kde.org and applies `patches/*.patch` (fails if a patch does not apply cleanly);
2. installs dependencies from KDE's public Craft binary cache, builds Kdenlive from the patched source, packages it (NSIS + 7z);
3. publishes the package and `SHA256SUMS.txt` as a pre-release `build-<run>`; on failure, the Craft logs as `logs-<run>`.

Builds are **unsigned test builds**. VAS verifies them (hash, contents, antivirus) before use and renders its frame-exact golden test suite
with them before they can replace the official Kdenlive in VAS.
