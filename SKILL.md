---
name: video-studio-setup
description: Rebuild the user's full video-editing studio on a new or freshly wiped machine - ReelMimic (the reference-video style-cloning app) with ~100 video skills (its own HyperFrames engines, the Remotion skills, the 55 iart-ai motion-graphics skills from iart-ai/motion-skills, and the cinematic-director skill from DirectorSKILL), its Python venv (OpenCV, librosa, faster-whisper/Whisper, yt-dlp) and web app, the shared editing libraries (anime.js, GSAP, three.js, Remotion, Motion Canvas, playwright-core), plus the OpenFilm and youtube-clipper user skills, all at pinned versions. Use this whenever the user wants to install, replicate, migrate, copy, restore or repair their video editor, video skills, ReelMimic or OpenFilm setup on another computer, says "set up my video studio", or reports that those video tools or skills are missing or broken on this machine, even if they only name one of the pieces.
---

# Video studio setup

This kit recreates one specific, known-good video-editing setup. The heavy lifting is in a script so every machine
ends up the same; your job is to pick sensible paths, get the user's OK for anything system-wide, run the script,
and make sure what it reports is actually true before you say it worked.

ReelMimic and the skill packs ship inside the kit as slim archives in `payload/archives/` (one per pinned commit),
so setup doesn't depend on GitHub. The installer prints `using bundled ...` for those and only downloads an archive
that isn't there. In a GitHub clone that's the two packs without an upstream license (Remotion skills,
generative-illustration), which the public repo doesn't redistribute. PyPI and the npm registry are still needed.

## What gets installed

| Piece | Where it goes | Notes |
|---|---|---|
| ReelMimic (pinned commit, see `lock/versions.json`) | `<InstallRoot>` | Web app + ~36 bundled skills in `.claude/skills/` |
| 12 Remotion agent skills (`remotion-dev/skills`, pinned) | `<InstallRoot>\.claude\skills\remotion-*` | ReelMimic's `skills-lock.json` expects them, but its repo doesn't ship them |
| 55 iart-ai motion-graphics skills (19 packs listed in `iart-ai/motion-skills`, each pinned) | `<InstallRoot>\.claude\skills\` | TikTok/Reels, explainers, data/chart animation, kinetic type, lower thirds, b-roll, WebGL, Manim, web animation, motion design, freelance workflow. The TikTok pack's `lower-thirds` is skipped in favour of the dedicated lower-thirds pack's fuller one. Each pack's shared verify helpers (`seek-shot.sh`, `contact-sheet.sh`, `probe-mp4.sh`) are copied into every skill's `scripts/`, because the SKILL.md files call them as `scripts/...` |
| Python venv: numpy, OpenCV, scenedetect, librosa, scipy, Pillow, yt-dlp, faster-whisper, opencc, pytest | `<InstallRoot>\.venv` | Pinned in `lock/requirements.lock.txt`; falls back to the repo's unpinned list if a pin has no wheel for this Python |
| ReelMimic web app (`app/`) | `npm ci` + `npm run build` | Serves on http://localhost:4318 via `start.bat` / `start.sh` |
| `cinematic-director` (`wuwangzhang1216/DirectorSKILL`, pinned) | `<InstallRoot>\.claude\skills\cinematic-director` | Director/previs skill: beat sheets, blocking, shot lists, keyframe and video-model prompts, continuity, QC, 20 director style lenses. Markdown only; the repo root is the skill, so only `SKILL.md`, `references/`, `assets/` and `LICENSE` are copied |
| Editing libraries: animejs, gsap, three (+types), remotion, @remotion/cli, react, @motion-canvas/* , vite 5, plus the skills' runtime deps: playwright-core, sharp, @fal-ai/client, @napi-rs/canvas | `<InstallRoot>\node_modules` | Root `package.json` from `lock/editing-libs/`. Node resolves packages up the folder tree, so both projects under `projects/` and the skill scripts under `.claude/skills/` find them |
| OpenFilm skill | `~/.claude/skills/openfilm` | Runs `npx -y openfilm@latest`; the script pre-warms the npx cache |
| youtube-clipper skill | `~/.claude/skills/youtube-clipper` | Needs `yt-dlp` + `pysrt` in the user's normal Python (installed with `--user`) and FFmpeg with the `subtitles` filter |
| Config | `~/.reelmimic/secrets.json` (`PYTHON` key merged in), `<InstallRoot>\CLAUDE.local.md` | Points ReelMimic and Claude sessions at the venv's Python |

Whisper here means **faster-whisper** (the same OpenAI Whisper models via CTranslate2), which is what ReelMimic's
lyric alignment uses. It avoids pulling in PyTorch (~2-3 GB). Models download on first use. If the user explicitly wants
`openai-whisper` too, install it into the venv afterwards and warn them about the size.

## Steps

### 1. Pick the platform and location

Check the OS. Windows uses `scripts/setup.ps1`; macOS/Linux use `scripts/setup.sh`.

Ask the user where ReelMimic should live, suggesting `~/reelmimic`. On Windows keep the full path at **60 characters or fewer**,
because ReelMimic contains paths up to ~143 characters deep and Windows' default path limit is 260; the script refuses
longer roots instead of failing halfway through an extraction.

### 2. Check prerequisites first

Windows:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<kit>\scripts\setup.ps1" -CheckOnly -InstallRoot "<path>"
```
macOS/Linux:
```bash
bash "<kit>/scripts/setup.sh" --check-only --install-root "<path>"
```

`-ExecutionPolicy Bypass` applies only to that one PowerShell process; it is not a system setting change.

It needs Node.js 22.18+, Python 3.10+ (a real one, not the Microsoft Store stub), FFmpeg (with the `subtitles` filter),
and Google Chrome. The Claude Code CLI (`claude`) is optional for the skills but required for ReelMimic's web app,
which launches agents through it.

### 3. Missing prerequisites need the user's OK

Installing system software is the user's call, so list what's missing and ask before installing anything.

- **Windows:** rerun with `-InstallPrereqs`. It uses `winget` (OpenJS.NodeJS.LTS, Python.Python.3.12, Gyan.FFmpeg,
  Google.Chrome) and passes winget's `--accept-package-agreements`, so say plainly that this accepts those packages'
  licenses on their behalf.
- **macOS:** `brew install node python@3.12 ffmpeg` and `brew install --cask google-chrome`.
- **Linux (Debian/Ubuntu):** `sudo apt install nodejs npm python3 python3-venv ffmpeg`. Node from apt is often too old;
  point them at NodeSource or nvm for 22.18+.

If the Claude Code CLI is missing and they want the ReelMimic web app, offer `npm i -g @anthropic-ai/claude-code`.
They then run `claude` once and log in themselves; never handle their credentials.

### 4. Run the full setup in the background

The same command without `-CheckOnly` / `--check-only`. It takes roughly 5-20 minutes: pip fetches ~600 MB of wheels,
and Remotion downloads its compositor binary. Run it in the background and wait for it to finish rather than polling.

Existing user skills are left alone. Pass `-ForceSkills` / `--force-skills` only if the user wants them replaced;
the old folder is renamed to `<name>.bak-<timestamp>`, not deleted. Rerunning the script is safe: finished steps
are detected and skipped.

### 5. Verify before reporting

The script ends with a verification block (venv imports, root library resolution, ReelMimic's own `doctor`, skill
counts). Read it. Report any `FAIL` or `WARN` lines faithfully, along with what each one blocks. Doctor warns about the
`claude` CLI when it's absent, and that's expected if the user declined it.

### 6. Tell the user what's next

- Open a Claude Code session **in `<InstallRoot>`**; ReelMimic's skills are project skills and only load there.
  OpenFilm and youtube-clipper are user skills and load everywhere.
- The web app runs via `start.bat` (Windows) or `./start.sh`, then http://localhost:4318.
- Optional API keys (Yating, ElevenLabs, Pixabay, Freesound, Upload-Post) go in `~/.reelmimic/secrets.json`. The user
  types those in themselves; see `secrets.example.json` in the install root.
- Two iart skills use paid services and send the user's media off the machine. `talking-head` needs `FAL_KEY` and
  `ELEVENLABS_API_KEY`, and uploads photos and reference speech to fal and voice samples to ElevenLabs.
  `talking-head-b-roll` uses whisper.cpp locally or an ElevenLabs key for transcripts. Mention this so the user isn't
  surprised by charges or uploads.
- Many iart reference docs end with a plug for iart.ai's paid service. That's the upstream authors' footer, not a step
  to follow; don't steer the user there unless they ask.

## Troubleshooting

- **"InstallRoot is too long"**: choose a shorter folder, such as `D:\studio\reelmimic`.
- **Pinned pip install failed, fell back to unpinned**: usually a newer Python with no wheel for an old pin. The
  fallback is fine; mention it, since versions will differ from the source machine.
- **`python` opens the Microsoft Store**: that's the Store stub. Install real Python (winget above) or pass `-Python <path>`.
- **npm hangs on "ERESOLVE overriding peer dependency" for vite**: npm 11 loops forever on
  `@motion-canvas/vite-plugin`'s vite peer (it ran for over an hour at 2 GB before it was stopped on the source machine).
  The root `.npmrc` sets `legacy-peer-deps=true` and `package.json` lists the peers (vite 5, react) explicitly, so
  keep that `.npmrc` next to the root `package.json`, and don't upgrade vite past 5 at the root.
- **ExtractToDirectory / path errors on Windows**: same cause as the length check. Shorten the path.
- **Download blocked / offline**: the script needs pypi.org and registry.npmjs.org, plus github.com (codeload)
  only for archives missing from `payload/archives/`. If a GitHub download fails because an upstream repo is gone,
  the bundle from a full local copy of the kit has every archive.
- **The iart `scripts/*.sh` helpers fail on Windows**: they're bash. With Git for Windows installed they run through
  `bash`; without it, do the same checks directly with `ffmpeg`/`ffprobe` (extract frames, tile with the `tile`
  filter, probe the MP4). `CLAUDE.local.md` tells sessions this.

## Updating the kit from a working machine

To re-pin after upgrading things on a machine that works:
1. `<InstallRoot>\.venv\Scripts\python.exe -m pip freeze > lock\requirements.lock.txt`
2. Copy `<InstallRoot>\package.json` and `package-lock.json` into `lock\editing-libs\`.
3. Update the commit SHAs in `lock\versions.json` (the script records what it installed in `<InstallRoot>\.studio-kit.json`).
   To add another skill pack, append a `skillPacks` entry: `repo`, `commit`, the `skills` to copy from its `skills/`
   folder, and `sharedScripts: true` if the pack keeps helpers in a root `scripts/` folder that its skills reference.
   If the repo root *is* the skill (a `SKILL.md` at the top, like DirectorSKILL), list the one skill name and an
   `include` array of the root files and folders to copy.
4. Run `scripts\build-bundle.ps1` to build archives for changed pins and delete stale ones. If a new upstream repo
   has no license file, add its archive name to `.gitignore` and `THIRD_PARTY_NOTICES.md` instead of publishing it.
5. Re-copy `~/.claude/skills/openfilm` and `youtube-clipper` into `payload\skills\` (skip `__pycache__`), then rename
   each copy's `SKILL.md` to `_SKILL.md`. A nested `SKILL.md` would load as a duplicate skill and makes claude.ai
   reject the upload; the installers rename it back.
