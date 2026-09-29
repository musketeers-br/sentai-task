# Research: Demo Media and Community Article

## R-1 Recording with Playwright

- Playwright records a WebM per page when `video: 'on'` (size set by `video.size`). The file is
  finalised when the context closes. The existing e2e config records nothing and uses 1440×900 @2×;
  a separate config keeps both unaffected.
- `slowMo` makes clicks visible. A fake cursor is not needed: the captions and the running states
  carry the story.
- **Alternative rejected**: screen recording with an OS tool. Not reproducible, and it captures the
  desktop.

## R-2 GIF within 30 s and 8 MB

- A 45 s WebM at 1280×720 converted at 960 px and 12 fps with `palettegen`/`paletteuse`
  (`stats_mode=diff`, `dither=bayer`) is typically 4–7 MB for UI footage with large flat areas.
  The canvas is dark, with small moving regions. **To measure in T004**: if the full GIF exceeds
  8 MB, drop to 10 fps before reducing the width.
- Speed-up: `setpts=PTS/F`, where `F = max(1, duration/28)`. The captions must state a time-lapse
  when `F > 1.5`, so the recorder runs once to measure the duration and once more with
  `SENTAI_MEDIA_TIMELAPSE=F` to render the caption. The showcase usually runs in about 20–60 s, so
  `F` is often ≤ 1.5 and one pass is enough; the script decides.
- ffmpeg image: `jrottenberg/ffmpeg:7-alpine` (includes `ffprobe`). On Git Bash, paths are passed
  with `MSYS_NO_PATHCONV=1` (known repository convention).

## R-3 Where the article and media are allowed

- Developer Community posts accept embedded animated GIFs and YouTube links. The size limit for
  uploads is not documented; the light variant (≤ 3 MB) is the fallback (spec edge case).
- Open Exchange: the listing's description is Markdown from the README or edited in the portal,
  with images by URL. `raw.githubusercontent.com` URLs of `assets/media/` work for both.
- Contest rules on promotion: the team confirms before publishing (spec assumption). The checklist
  has that as its first item.

## R-4 Honest claims

- Each claim in the article maps to proof: README sections (anchors), `specs/00x/evidence/`,
  test counts from the latest evidence README. The checker cannot judge truth; the publishing
  checklist asks a second team member to review claims against the merged README.
