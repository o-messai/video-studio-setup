# Third-party notices

This kit bundles pinned snapshots of other people's open-source work so that setup doesn't depend on GitHub.
Each bundled component keeps its own license; the license files travel inside the archives listed below.
Nothing here is modified beyond removing files the installer doesn't use (demo GIFs, screenshots, CI configs).
The kit's own MIT [LICENSE](LICENSE) covers only its own scripts and docs, not these components.

## Bundled in this repository

| Component | Upstream (pinned commit) | Archive / path | License | Copyright |
|---|---|---|---|---|
| ReelMimic | [edenfunf/reelmimic](https://github.com/edenfunf/reelmimic) `1be183e` | `payload/archives/edenfunf__reelmimic@1be183e.zip` (without `docs/assets/`) | MIT | © 2026 ReelMimic contributors |
| ReelMimic's bundled skills and fonts | HeyGen HyperFrames, Anthropic skills, painted-animation, ClaudeAnimationBase, Digital Samba, Google Fonts, Excalidraw | inside the ReelMimic archive | Apache-2.0 / MIT / SIL OFL 1.1; see `THIRD_PARTY_NOTICES.md` and `LICENSES/` in that archive | respective authors |
| 18 iart-ai motion-skill packs: ad-video, b-roll, data-animation, ecommerce-video, explainer-video, freelance-motion, javascript-animation, kinetic-typography, lower-thirds, manim, map-animation, motion-design, talking-head, text-message-video, tiktok-video, web-animation, webgl-animation, youtube-video | `github.com/iart-ai/<pack>-skills` (commits in `lock/versions.json`) | `payload/archives/iart-ai__*.zip` | MIT | © 2026 iart.ai |
| cinematic-director | [wuwangzhang1216/DirectorSKILL](https://github.com/wuwangzhang1216/DirectorSKILL) `c65ae0d` | `payload/archives/wuwangzhang1216__DirectorSKILL@c65ae0d.zip` | MIT | © 2026 wangzhang-wu |
| youtube-clipper skill | [op7418/Youtube-clipper-skill](https://github.com/op7418/Youtube-clipper-skill) | `payload/skills/youtube-clipper/` | MIT | © 2026 op7418 |
| OpenFilm skill (a 4-line `SKILL.md` that runs `npx openfilm`) | [openfilm/openfilm](https://github.com/openfilm/openfilm) (npm `openfilm`, MIT) | `payload/skills/openfilm/` | MIT (per the npm package; the skill file has no license file of its own) | OpenFilm authors |

## Not redistributed here (downloaded during setup)

These upstream repositories publish **no license**, so this repository does not include them (see `.gitignore`).
The installer downloads them from GitHub at the pinned commit. A local copy of the kit built with
`scripts/build-bundle.ps1` has them bundled for your own use.

| Component | Upstream (pinned commit) | Why not bundled |
|---|---|---|
| 12 Remotion agent skills | [remotion-dev/skills](https://github.com/remotion-dev/skills) `30d4553` | No license file; ReelMimic doesn't redistribute them either |
| generative-illustration skill | [iart-ai/generative-illustration-skills](https://github.com/iart-ai/generative-illustration-skills) `e7d6243` | No license file in this pack (its sibling packs are MIT) |

## Installed from package registries (not redistributed)

Python packages (PyPI) and npm packages (npm registry) are installed at the versions pinned in
`lock/requirements.lock.txt` and `lock/editing-libs/package-lock.json`, under their own licenses. Notable ones:
Remotion, which uses the [Remotion License](https://www.remotion.dev/license) (free for individuals and small
teams; companies above the threshold need a license), plus Motion Canvas, GSAP, anime.js, three.js,
faster-whisper, OpenCV and librosa.
