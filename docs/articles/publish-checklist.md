# Publishing checklist (spec 014)

Team actions, in order. Each outward-facing step is confirmed by the team before it is done.

1. **Rules.** Confirm the contest rules allow posting about your own entry and asking for votes.
2. **Merged.** Specs 011–013 are merged to `master` (the articles only claim merged work, and the
   GIF and evidence links point at `master`).
3. **Media.** `bash scripts/media/make-media.sh` on a machine with the dev stack and
   `iris-target` up; review the GIF frame by frame
   (`docs/articles` quickstart, spec 014) and the 12 stills; commit `assets/media/` (the MP4 is
   git-ignored).
4. **Texts.** Remove every `<!-- after … -->` marker, set `status: ready` in both front matters, and
   run `node --use-system-ca scripts/media/check-articles.mjs docs/articles/en/*.md docs/articles/pt-br/*.md`:
   both PASS.
5. **Second reader.** Another team member reads each claim against the merged README.
6. **Video.** Upload `assets/media/sentai-run.mp4` (narration from `video-script.md` if recorded)
   to the team's video channel; note the URL.
7. **English article.** Publish on community.intersystems.com with the contest tag; paste the URL
   into its front matter (`published:`).
8. **Portuguese article.** Replace its first-line marker with a link to the English article,
   publish on the Portuguese community, paste its URL into its front matter.
9. **Channels.** Add the video and both article links to the README *Try it* block and to the Open
   Exchange description, whose picture becomes `assets/media/sentai-run.gif`.
10. **Record.** Dates and URLs go in `specs/014-demo-media-article/evidence/README.md`; on
    2026-10-04 add the Open Exchange page views (SC-004).
