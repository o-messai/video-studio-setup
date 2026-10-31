# Instructions for AI agents

You (the agent reading this) can turn this machine into a complete video-editing studio, then use it to
make videos yourself. This file is the entry point for any agent — ChatGPT/Codex, Gemini, Grok, Cursor,
aider and friends. (Claude Code users: this repo is also a native skill; `SKILL.md` is the same playbook
in its native format.)

## 1. Set the studio up

Read **`SKILL.md`** and follow it. In short:

1. Pick the installer for this OS: `scripts/setup.ps1` (Windows) or `scripts/setup.sh` (macOS/Linux).
2. Run it with `-CheckOnly` / `--check-only` first and report what's missing
   (Node 22.18+, Python 3.10+, FFmpeg with the `subtitles` filter, Google Chrome).
3. **Ask the user before installing any system software.** On Windows, `-InstallPrereqs` lets winget do it.
4. Ask where the studio should live (suggest `~/reelmimic`; on Windows the path must be ≤ 60 characters),
   then run the installer without `-CheckOnly`. It is idempotent — rerunning skips finished steps.
5. Verify the installer's final report yourself before telling the user it worked.

The installer unpacks pinned archives from `payload/`, builds the ReelMimic web app, creates a private
Python venv, and installs 104 project skills into `<InstallRoot>/.claude/skills/` plus 2 user skills
(OpenFilm, youtube-clipper) into `~/.claude/skills/`.

## 2. Become a video editor

The skills are plain markdown playbooks. Before any video job, find the matching skill and **read it
fully, then follow it exactly** — they encode hard-won rules about rendering, timing, verification and
output quality:

- `<InstallRoot>/.claude/skills/` — 104 project skills: style cloning, motion graphics engines,
  Remotion, TikTok/Reels, explainers, data animation, kinetic typography, lower thirds, b-roll, maps,
  WebGL, Manim, web animation, director-level shot planning.
- `~/.claude/skills/openfilm/` and `~/.claude/skills/youtube-clipper/` — films as web pages, and
  YouTube clipping with bilingual subtitles. (In this repo their playbooks are stored as
  `payload/skills/*/_SKILL.md`.)

Working rules:

- Work **inside the ReelMimic install folder** so relative paths in the skills resolve.
- Use the venv's Python (`<InstallRoot>/.venv`) for OpenCV/Whisper/yt-dlp work — never the global Python.
  `~/.reelmimic/secrets.json` records its path.
- Render, then **verify the output** (probe the file, inspect frames) before declaring success. The iart
  packs ship `scripts/probe-mp4.sh`, `seek-shot.sh`, `contact-sheet.sh` helpers for exactly this.
- Some skills call paid APIs (`talking-head` needs `FAL_KEY`, `ELEVENLABS_API_KEY`). Never enable or
  spend on a paid service without the user's explicit OK.

## 3. Prove it works

A good first job after setup: ask the user for a topic and make them a 15–30 second animated title video,
rendered to MP4. The `media/demo.mp4` in this repo shows the ceiling — a 70-second 4K launch film made
entirely by an agent in this studio.
