#!/usr/bin/env bash
# Rebuilds the video-editing studio on macOS/Linux; mirrors scripts/setup.ps1 (see SKILL.md). Safe to rerun.
# Usage: bash setup.sh [--check-only] [--install-root DIR] [--skills-dir DIR] [--secrets FILE] [--python EXE] [--force-skills]
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="$HOME/reelmimic"
SKILLS_DIR="$HOME/.claude/skills"
SECRETS="$HOME/.reelmimic/secrets.json"
PY_ARG=""
CHECK_ONLY=0
FORCE_SKILLS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=1 ;;
    --install-root) INSTALL_ROOT="$2"; shift ;;
    --skills-dir) SKILLS_DIR="$2"; shift ;;
    --secrets) SECRETS="$2"; shift ;;
    --python) PY_ARG="$2"; shift ;;
    --force-skills) FORCE_SKILLS=1 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$INSTALL_ROOT" in /*) ;; *) INSTALL_ROOT="$PWD/$INSTALL_ROOT" ;; esac

PROBLEMS=()
say()  { printf '\n== %s\n' "$1"; }
info() { printf '  ..   %s\n' "$1"; }
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$1"; PROBLEMS+=("WARN $1"); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; PROBLEMS+=("FAIL $1"); }
die()  { fail "$1"; summary; exit 1; }
summary() {
  say 'Summary'
  if [ ${#PROBLEMS[@]} -eq 0 ]; then echo '  everything checked out'; else printf '  %s\n' "${PROBLEMS[@]}"; fi
}
jget() { node -p "const v = require(process.argv[1]); $1" "$KIT/lock/versions.json"; }

# ---------- prerequisites ----------

find_python() {
  local c out
  for c in ${PY_ARG:+"$PY_ARG"} python3 python; do
    command -v "$c" >/dev/null 2>&1 || continue
    out="$("$c" -c 'import sys; print(sys.executable if sys.version_info >= (3, 10) else "")' 2>/dev/null)" || continue
    [ -n "$out" ] && { echo "$out"; return 0; }
  done
  return 1
}

find_chrome() {
  local c
  [ -n "${CHROME_PATH:-}" ] && [ -x "$CHROME_PATH" ] && { echo "$CHROME_PATH"; return 0; }
  [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ] && { echo "/Applications/Google Chrome.app"; return 0; }
  for c in google-chrome google-chrome-stable chromium chromium-browser; do
    command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return 0; }
  done
  return 1
}

MISSING=()
say 'Prerequisites'
if command -v node >/dev/null 2>&1 && [ "$(node -p "const [a, b] = process.versions.node.split('.').map(Number); a > 22 || (a === 22 && b >= 18)")" = true ]; then
  ok "Node.js $(node -v)"
else
  fail 'Node.js 22.18+ not found (macOS: brew install node; Linux: nvm or NodeSource)'; MISSING+=(node)
fi
if PY="$(find_python)"; then
  if "$PY" -c 'import venv, ensurepip' >/dev/null 2>&1; then ok "Python $("$PY" -c 'import platform; print(platform.python_version())') at $PY"
  else fail "Python at $PY has no venv/ensurepip (Debian/Ubuntu: sudo apt install python3-venv)"; MISSING+=(python); fi
else
  fail 'Python 3.10+ not found (macOS: brew install python@3.12; Linux: sudo apt install python3 python3-venv)'; MISSING+=(python)
fi
if command -v ffmpeg >/dev/null 2>&1; then
  # captured first: with pipefail, grep -q closing the pipe early would make ffmpeg's SIGPIPE look like a failure
  FILTERS="$(ffmpeg -hide_banner -filters 2>/dev/null)"
  if grep -qE '[[:space:]]subtitles[[:space:]]' <<<"$FILTERS"; then ok 'FFmpeg (with subtitles filter)'
  else warn 'FFmpeg has no subtitles filter (libass): youtube-clipper cannot burn subtitles (macOS: brew install ffmpeg-full)'; fi
else
  fail 'FFmpeg not found (macOS: brew install ffmpeg; Linux: sudo apt install ffmpeg)'; MISSING+=(ffmpeg)
fi
if CHROME="$(find_chrome)"; then ok "Chrome at $CHROME"; else fail 'Google Chrome not found (macOS: brew install --cask google-chrome)'; MISSING+=(chrome); fi
if command -v claude >/dev/null 2>&1; then ok 'Claude Code CLI'
else warn 'Claude Code CLI (claude) not on PATH: the skills work, but the ReelMimic web app needs it (npm i -g @anthropic-ai/claude-code)'; fi
ok "InstallRoot $INSTALL_ROOT"

if [ "$CHECK_ONLY" = 1 ]; then summary; [ ${#MISSING[@]} -eq 0 ]; exit $?; fi
[ ${#MISSING[@]} -eq 0 ] || { echo; echo "Missing: ${MISSING[*]}. Install them (hints above), then rerun."; exit 1; }

# ---------- install steps ----------

WORK="$(dirname "$INSTALL_ROOT")/_vk"
rm -rf "$WORK"; mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# Extracts a pinned commit and prints its top folder. Uses the kit's bundled archive (payload/archives, made by
# build-bundle.ps1) when it matches the pin, so setup needs no GitHub; otherwise downloads it.
pinned_zip() {
  local repo="$1" commit="$2" tag="$3" zip
  zip="$KIT/payload/archives/${repo//\//__}@${commit:0:7}.zip"
  if [ -f "$zip" ]; then info "using bundled $repo@${commit:0:7}" >&2
  else
    zip="$WORK/$tag.zip"
    info "downloading $repo@${commit:0:7}" >&2
    curl -fsSL "https://codeload.github.com/$repo/zip/$commit" -o "$zip" || return 1
  fi
  if command -v unzip >/dev/null 2>&1; then unzip -q "$zip" -d "$WORK/$tag" || return 1
  else "$PY" -m zipfile -e "$zip" "$WORK/$tag" || return 1; fi
  local d
  for d in "$WORK/$tag"/*/; do echo "${d%/}"; return 0; done
  return 1
}

RM_COMMIT="$(jget 'v.reelmimic.commit')"
say "ReelMimic ${RM_COMMIT:0:7} -> $INSTALL_ROOT"
if [ -f "$INSTALL_ROOT/app/package.json" ]; then ok 'already present, reusing it'
else
  if [ -d "$INSTALL_ROOT" ] && [ -n "$(ls -A "$INSTALL_ROOT")" ]; then die "$INSTALL_ROOT is not empty and is not a ReelMimic folder; choose another --install-root"; fi
  SRC="$(pinned_zip "$(jget 'v.reelmimic.repo')" "$RM_COMMIT" rm)" || die 'ReelMimic download failed'
  rmdir "$INSTALL_ROOT" 2>/dev/null; mv "$SRC" "$INSTALL_ROOT" || die 'could not move ReelMimic into place'
  chmod +x "$INSTALL_ROOT"/*.sh 2>/dev/null
  ok "$(find "$INSTALL_ROOT" -type f | wc -l | tr -d ' ') files"
fi

say 'Skill packs (Remotion + iart-ai motion skills) -> project skills'
DST="$INSTALL_ROOT/.claude/skills"
NPACKS="$(jget 'v.skillPacks.length')"
for ((i = 0; i < NPACKS; i++)); do
  REPO="$(jget "v.skillPacks[$i].repo")"
  TODO=()
  for n in $(jget "v.skillPacks[$i].skills.join(' ')"); do [ -d "$DST/$n" ] || TODO+=("$n"); done
  if [ ${#TODO[@]} -eq 0 ]; then ok "$REPO: all already present"; continue; fi
  SRC="$(pinned_zip "$REPO" "$(jget "v.skillPacks[$i].commit")" "p$i")" || die "$REPO download failed"
  INCLUDE="$(jget "(v.skillPacks[$i].include || []).join(' ')")"
  for n in "${TODO[@]}"; do
    if [ -n "$INCLUDE" ]; then
      # the repo root is the skill: copy only the listed parts, leaving CI, evals and changelogs behind
      mkdir -p "$DST/$n"
      for item in $INCLUDE; do cp -R "$SRC/$item" "$DST/$n/" || die "could not copy $item for $n"; done
    else
      cp -R "$SRC/skills/$n" "$DST/$n" || die "could not copy $n"
    fi
    # iart packs keep their verify helpers at the pack root, while each SKILL.md calls them as scripts/...
    if [ "$(jget "!!v.skillPacks[$i].sharedScripts")" = true ] && [ -d "$SRC/scripts" ]; then
      mkdir -p "$DST/$n/scripts"
      for f in "$SRC/scripts"/*; do
        [ -f "$f" ] && [ ! -e "$DST/$n/scripts/$(basename "$f")" ] && cp "$f" "$DST/$n/scripts/"
      done
      chmod +x "$DST/$n/scripts/"*.sh 2>/dev/null
    fi
  done
  rm -rf "$WORK/p$i" "$WORK/p$i.zip"
  ok "$REPO: installed ${#TODO[@]}"
done

say 'Python venv (OpenCV, librosa, faster-whisper, yt-dlp, ...)'
VPY="$INSTALL_ROOT/.venv/bin/python"
[ -x "$VPY" ] || "$PY" -m venv "$INSTALL_ROOT/.venv" || die 'venv creation failed'
"$VPY" -m pip install --upgrade pip --quiet --disable-pip-version-check || die 'pip upgrade failed'
if ! "$VPY" -m pip install --disable-pip-version-check -r "$KIT/lock/requirements.lock.txt"; then
  warn 'pinned Python packages did not install on this Python; used the unpinned list from ReelMimic instead'
  "$VPY" -m pip install --disable-pip-version-check -r "$INSTALL_ROOT/requirements.txt" || die 'pip install failed'
fi
ok "venv at $INSTALL_ROOT/.venv"

say 'ReelMimic web app'
if [ -d "$INSTALL_ROOT/app/node_modules" ] && [ -f "$INSTALL_ROOT/app/dist/index.html" ]; then ok 'already built'
else
  (cd "$INSTALL_ROOT/app" && npm ci --no-fund --no-audit && npm run build) || die 'web app install/build failed'
  ok 'built app/dist'
fi

say 'Editing libraries (anime.js, GSAP, three.js, Remotion, Motion Canvas)'
if [ -f "$INSTALL_ROOT/package.json" ] && [ "$(node -p "require('$INSTALL_ROOT/package.json').name")" != reelmimic-editing-libs ]; then
  warn "$INSTALL_ROOT/package.json belongs to something else; skipped the editing libraries"
else
  # .npmrc carries legacy-peer-deps: npm 11 otherwise loops forever on @motion-canvas/vite-plugin's vite peer
  cp "$KIT/lock/editing-libs/package.json" "$KIT/lock/editing-libs/package-lock.json" "$KIT/lock/editing-libs/.npmrc" "$INSTALL_ROOT/"
  (cd "$INSTALL_ROOT" && npm ci --no-fund --no-audit) || die 'npm ci (editing libs) failed'
  ok "node_modules at $INSTALL_ROOT"
fi

say 'Config'
mkdir -p "$(dirname "$SECRETS")"
# merge PYTHON into secrets.json without touching other keys; refuse to rewrite a file that does not parse
node -e '
  const fs = require("fs"), [p, py] = process.argv.slice(1);
  let o = {};
  if (fs.existsSync(p)) { try { o = JSON.parse(fs.readFileSync(p, "utf8")); } catch { console.error(p + " is not valid JSON; fix it, then rerun"); process.exit(1); } }
  if (o.PYTHON && o.PYTHON !== py) console.log("  ..   PYTHON was " + o.PYTHON);
  o.PYTHON = py; fs.writeFileSync(p, JSON.stringify(o, null, 2) + "\n");' "$SECRETS" "$VPY" || die "could not update $SECRETS"
ok "PYTHON set in $SECRETS"
node -e '
  const fs = require("fs"), [tpl, out, py] = process.argv.slice(1);
  const text = fs.readFileSync(tpl, "utf8").split("{{VENV_PY}}").join(py);
  if (!fs.existsSync(out)) { fs.writeFileSync(out, text); console.log("wrote CLAUDE.local.md"); }
  else if (!fs.readFileSync(out, "utf8").includes(py)) { fs.appendFileSync(out, "\n" + text); console.log("added the venv note to CLAUDE.local.md"); }
  else console.log("CLAUDE.local.md already points at the venv");' "$KIT/payload/CLAUDE.local.md.template" "$INSTALL_ROOT/CLAUDE.local.md" "$VPY" | sed 's/^/  OK   /'
node -e '
  const fs = require("fs"), [kit, out] = process.argv.slice(1), v = require(kit + "/lock/versions.json");
  const skillPacks = v.skillPacks.map(({ repo, commit }) => ({ repo, commit }));
  fs.writeFileSync(out, JSON.stringify({ installed: new Date().toISOString(), reelmimic: v.reelmimic, skillPacks }, null, 2) + "\n");' "$KIT" "$INSTALL_ROOT/.studio-kit.json"

say "User skills -> $SKILLS_DIR"
mkdir -p "$SKILLS_DIR"
for s in "$KIT"/payload/skills/*/; do
  s="${s%/}"; name="$(basename "$s")"; dst="$SKILLS_DIR/$name"
  if [ -e "$dst" ]; then
    if [ "$FORCE_SKILLS" != 1 ]; then ok "$name already installed, left as is"; continue; fi
    bak="$dst.bak-$(date +%Y%m%d%H%M%S)"; mv "$dst" "$bak" || die "could not move the old $name aside"; info "moved the old $name to $bak"
  fi
  cp -R "$s" "$dst" || die "could not install $name"
  # bundled as _SKILL.md so they don't load as extra skills inside this kit
  mv "$dst/_SKILL.md" "$dst/SKILL.md" || die "could not finish installing $name"
  ok "installed $name"
done
# youtube-clipper runs with the user's normal Python, not the venv
if "$PY" -m pip install --user --quiet --disable-pip-version-check yt-dlp pysrt; then ok 'yt-dlp + pysrt for youtube-clipper'
else warn "could not pip install yt-dlp + pysrt for youtube-clipper (an externally managed Python? try: $PY -m pip install --user --break-system-packages yt-dlp pysrt)"; fi
if npx -y openfilm@latest >/dev/null 2>&1; then ok 'OpenFilm cached'; else warn 'npx openfilm@latest did not run; OpenFilm will fetch itself on first use'; fi

# ---------- verification ----------

say 'Verification'
if "$VPY" -I -c 'import numpy, cv2, scenedetect, librosa, scipy, PIL, yt_dlp, faster_whisper, opencc'; then
  ok 'venv imports: numpy cv2 scenedetect librosa scipy PIL yt_dlp faster_whisper opencc'
else fail 'venv imports failed (see the error above)'; fi
LIBS=""
for m in animejs gsap three remotion @remotion/cli @motion-canvas/core @motion-canvas/2d vite; do
  pj="$INSTALL_ROOT/node_modules/$m/package.json"
  if [ -f "$pj" ]; then LIBS="$LIBS  $m@$(node -p "require('$pj').version")"; else fail "node module $m missing"; fi
done
[ -n "$LIBS" ] && ok "editing libs:$LIBS"
if (cd "$INSTALL_ROOT/app" && PYTHON="$VPY" node scripts/doctor.mjs); then ok 'ReelMimic doctor passed'
else warn 'ReelMimic doctor reported problems, see above'; fi
ABSENT=""
for n in $(jget 'v.skillPacks.flatMap((p) => p.skills).join(" ")'); do [ -f "$INSTALL_ROOT/.claude/skills/$n/SKILL.md" ] || ABSENT="$ABSENT $n"; done
if [ -n "$ABSENT" ]; then fail "pack skills missing:$ABSENT"
else ok "$(find "$INSTALL_ROOT/.claude/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') ReelMimic project skills (all pinned pack skills present)"; fi
for s in "$KIT"/payload/skills/*/; do
  name="$(basename "$s")"
  if [ -f "$SKILLS_DIR/$name/SKILL.md" ]; then ok "user skill $name"; else fail "user skill $name missing"; fi
done

summary
cat <<EOF

Next:
  - Open Claude Code in $INSTALL_ROOT to use ReelMimic's skills (they are project skills).
  - Web app: $INSTALL_ROOT/start.sh, then http://localhost:4318 (needs the claude CLI, logged in).
  - Optional API keys: $SECRETS (format: $INSTALL_ROOT/secrets.example.json).
EOF
# ${arr[@]+...}: macOS's bash 3.2 treats an empty array as unbound under set -u
for p in ${PROBLEMS[@]+"${PROBLEMS[@]}"}; do case "$p" in FAIL*) exit 1 ;; esac; done
exit 0
