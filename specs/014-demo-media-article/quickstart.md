# Quickstart: Demo Media and Community Article

## 1. Record the media

Dev stack up with `iris-target` (`docker compose up -d`), canvas published.

```bash
bash scripts/media/make-media.sh            # SENTAI_MEDIA_PASSWORD defaults to SYS (local stack)
cat assets/media/manifest.json | jq '.timelapse, .files.gif, .files.gifSmall'
```

Expected: exit 0; `sentai-run.gif` ≤ 8 MB and ≤ 30 s, `sentai-run-small.gif` ≤ 3 MB, 12 stills,
`sentai-run.mp4` (gitignored) ≤ 90 s. Stop `iris-target` and run again: the script fails before
recording and `assets/media/` is unchanged.

Frame review (SC-002):

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "$PWD/assets/media:/m" jrottenberg/ffmpeg:7-alpine \
  -i /m/sentai-run.gif -vf fps=1 /m/review-%02d.png   # look at every frame, then delete review-*.png
```

## 2. Check the articles

```bash
node scripts/media/check-articles.mjs docs/articles/en/sentaitask-orchestration.md
node scripts/media/check-articles.mjs docs/articles/pt-br/sentaitask-orquestracao.md
```

Expected: word count in range, required sections present, all links 2xx/3xx, no forbidden
content, and no `<!-- after … -->` marker when the front matter says `status: ready`.

## 3. Publish (team)

Follow `docs/articles/publish-checklist.md`: confirm the contest rules allow the post → second
reviewer checks the claims against the merged README → upload the video → publish EN → publish PT
with the link to EN → paste the article URLs into the README and the front matter → update the
Open Exchange description.
