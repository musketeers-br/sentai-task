# Feature Specification: Demo Media and Community Article

**Feature Branch**: `014-demo-media-article`

**Created**: 2026-09-28

**Status**: In Progress

**Status note**: 11/14 tasks. T008 waits for 011–013 to merge (refresh numbers, set the article ready). T013 (publish) and T014 (record page views on 2026-10-04) are team actions, marked [external].

**Input**: Competitor analysis (2026-09-28): SentaiTask has 40 page views against about 83–100 for
the most-viewed entries, and it is the only entry whose core is visual orchestration. Its fifth
recommendation is to publish a Developer Community article with an animated capture of the canvas
(three checks converging into a join). The team chose (clarification Q4) an English article with a
Portuguese version. The README picture placed by spec 011 is a still that this feature replaces.

## Context and Problem

Voters decide from what they see in a few seconds: a README, an Open Exchange page, a community
post. Today SentaiTask shows one still picture and a long README. The product's differentiator
(flows that run in waves, converge at a join, span servers and gate maintenance on checks) is
motion, and a still does not show it. There is also no article that explains the idea to the
community, while rival entries are promoted by their authors.

## Objective

The team has, reproducibly and from the repository, an animated capture and a short video of
SentaiTask doing what no rival does, a set of still screenshots, and a ready-to-publish article in
English and in Portuguese that explains the product, links to the demo and the repository, and
asks for the vote. The same media appear on the README, the Open Exchange page and the articles.

## Clarifications

### Session 2026-09-28

- Q: Which languages? → A: English (main, Developer Community) and Portuguese (Portuguese
  Developer Community), adapted for each audience, not a literal translation.
- Q: Who publishes? → A: The team, from their own community accounts. The repository holds the
  ready-to-paste texts and media; publishing and editing the Open Exchange page are team actions.
- Q: Must the media be reproducible? → A: Yes. One command records them from a running instance, so
  they can be refreshed when the product changes during voting, and they never show a password,
  token or private data.
- Q: What does the capture show? → A: The showcase flow: parallel checks on the primary and on a
  second server, a join, and a final step, running live to completion; then a step result with
  findings; then the run history. If the area report steps (spec 013) are merged, the capture uses
  them; otherwise it uses the steps available.
- Q: What may the article claim? → A: Only what is merged on the default branch when it is
  published, with links to the proof (specs, tests, evidence). Planned work is named as planned.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One command records the animated capture and the stills (Priority: P1)

A team member runs one documented command against a running instance. It produces an animated
capture of the showcase flow running to completion (small enough for the README and community
posts), a short video of the same sequence at higher quality, and a set of still screenshots in
light and dark themes.

**Why this priority**: The media feed every other channel. Being reproducible means they can be
refreshed after each improvement during the voting week.

**Independent Test**: With the dev stack and the target server running, run the command; it ends
successfully and writes the animated capture, the video and the stills; the capture is under the
size limit and shows the run reaching "completed".

**Acceptance Scenarios**:

1. **Given** a running instance with the target server, **When** the command runs, **Then** it
   creates or reuses the showcase flow, runs it, and records: the flow on the canvas, *Run now*,
   steps moving from queued to running to completed in parallel waves, the join releasing the
   final step, the run completed, a step's result, and the run history.
2. **Given** the recording, **Then** the animated capture lasts at most 30 seconds, is at most 8 MB,
   and is readable at 800 px wide; the video lasts at most 90 seconds at 1280×720 or more.
3. **Given** the recording, **Then** short captions name what is happening ("3 checks in parallel,
   2 servers", "join: all must succeed", "report with findings").
4. **Given** the recording, **Then** no password, token, secret or personal data is visible in any
   frame (passwords are typed into masked fields only, and no API response is shown raw).
5. **Given** a step fails during recording, **Then** the command fails and writes no media, so a
   broken capture is never published by accident.
6. **Given** the stills, **Then** they include the showcase run completed, the palette with the
   step groups, a report result, the run history, the targets screen and the task catalog, each in
   light and dark.

---

### User Story 2 - A ready-to-publish article in English (Priority: P1)

A team member opens the English article in the repository, pastes it into the Developer Community
editor with its media, and publishes. The article explains the maintenance-orchestration problem,
shows the capture, walks through a flow, covers the contest areas, explains the security posture
(the platform decides every permission), links to the idea it implements (DPI-I-588), to the demo,
the repository and the Open Exchange page, and ends with a call to try it and vote.

**Why this priority**: The article is the main lever for community votes and views.

**Independent Test**: A reviewer who has never seen the product reads the article in under 8
minutes, can say what SentaiTask does differently from a task list, and finds working links to the
demo, the repository, the Open Exchange page and the idea.

**Acceptance Scenarios**:

1. **Given** the article, **Then** it has a title, an opening paragraph that states the problem and
   the answer, the animated capture near the top, sections for "how a flow runs", "the six areas",
   "distributed work (DPI-I-588)", "security by delegation", "how it was built (specs and tests)",
   and "try it", and a closing call to vote with the contest name and dates.
2. **Given** the article, **Then** it is between 900 and 1,600 words and every claim links to its
   proof (README section, spec, or evidence) or is phrased as planned.
3. **Given** the links, **Then** every link resolves (checked automatically).
4. **Given** the article, **Then** it contains no confidential name, credential or private address.

---

### User Story 3 - The Portuguese version (Priority: P2)

A team member publishes the Portuguese version on the Portuguese Developer Community, adapted for
that audience (same facts, same media, natural Brazilian Portuguese), with a link to the English
article.

**Why this priority**: The team is Brazilian and the Portuguese community is active; it doubles the
reach at little cost. It follows the English text.

**Independent Test**: A Portuguese-speaking reviewer reads it and confirms it reads naturally, has
the same sections, facts and links as the English one, and links to it.

**Acceptance Scenarios**:

1. **Given** the Portuguese article, **Then** it has the same sections, claims, media and links as
   the English one, plus a link to the English article.
2. **Given** product terms (flow, step, join, target server), **Then** they are used consistently
   and match the product's English UI labels where the reader will see them on screen.

---

### User Story 4 - Same media everywhere (Priority: P2)

The README's top picture is replaced by the animated capture; the Open Exchange page's description
and images use the same capture and stills; the video is linked from the README and the articles.

**Why this priority**: Consistency makes the product recognisable across channels; the README
change is immediate.

**Independent Test**: The README shows the animated capture at the top; the Open Exchange page
(checked by the team after editing) shows the capture and links the video.

**Acceptance Scenarios**:

1. **Given** the README, **Then** the still from spec 011 is replaced in place by the animated
   capture, with a text alternative describing it.
2. **Given** the video, **Then** it is published by the team on a public video platform and linked
   from the README "Try it" block and both articles.
3. **Given** the Open Exchange page, **Then** the team updates its description with the capture
   and the article links (team action, confirmed before doing it).

---

### User Story 5 - A narrated video script (Priority: P3)

A team member records a voice-over for the video from a script in the repository: at most 90
seconds, one sentence per scene, matching the captions.

**Why this priority**: A narrated video helps experts who judge from the Open Exchange page, but a
captioned video without narration is acceptable.

**Independent Test**: Reading the script aloud over the video fits its length, scene by scene.

**Acceptance Scenarios**:

1. **Given** the script, **Then** each scene has its start time, the caption and one or two
   sentences of narration, in English, with a Portuguese version.

### Edge Cases

- The target server is down at recording time: the command stops before recording (a capture
  without the distributed step would undersell the product).
- The instance is slow and the run takes longer than the capture's budget: the idle stretches are
  sped up in the animated capture, and the captions say "time-lapse".
- Spec 013 is not merged when recording: the capture shows the showcase without the report steps;
  the article does not mention them.
- The community editor does not accept an animated image of that size: the capture is also produced
  in a lighter variant (smaller width, fewer frames).
- Dark and light themes: the animated capture uses dark (the product's default look in the
  evidence); stills come in both.

## Requirements *(mandatory)*

### Functional Requirements

**Media**

- **FR-001**: The repository MUST provide one documented command that, against a running instance
  with the target server, produces an animated capture, a video and a set of stills of the
  sequence in US1-1.
- **FR-002**: The animated capture MUST last ≤ 30 s and weigh ≤ 8 MB; a lighter variant ≤ 3 MB MUST
  also be produced; the video MUST last ≤ 90 s at ≥ 1280×720.
- **FR-003**: Captions MUST describe each phase in English; no frame may show a password, token,
  secret or personal data.
- **FR-004**: The command MUST fail without writing media when the showcase run does not complete,
  or the target server is unavailable.
- **FR-005**: Stills MUST cover the screens listed in US1-6 in both themes.
- **FR-006**: The command MUST need no tool beyond what the repository already requires (Docker and
  the frontend's toolchain).

**Articles**

- **FR-007**: The repository MUST contain the English article and the Portuguese article as
  ready-to-paste texts with their media references, following the structure of US2-1.
- **FR-008**: Every factual claim MUST link to its proof or be labelled as planned; every link MUST
  be checked automatically before publishing.
- **FR-009**: The articles MUST NOT contain confidential names, credentials or private addresses.
- **FR-010**: The Portuguese article MUST carry the same facts, media and links, plus a link to the
  English article.

**Channels**

- **FR-011**: The README's top picture MUST be the animated capture, with a text alternative.
- **FR-012**: The README and both articles MUST link the published video once it exists.
- **FR-013**: A narration script (English and Portuguese) aligned with the video's scenes MUST be
  in the repository.
- **FR-014**: Publishing the articles and the video, and editing the Open Exchange page, are team
  actions outside the product; the repository MUST provide a checklist for them.

### Key Entities

- **Media set**: animated capture (full and light), video, stills (per screen and theme), each with
  the date and product version it was recorded from.
- **Article**: language, title, body, media references, link list, word count, publication URL once
  published.
- **Narration script**: scenes with start time, caption, narration (EN and PT).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The media command runs end to end in under 5 minutes on the team's machine and
  succeeds on 3 consecutive runs.
- **SC-002**: 0 frames of the capture and video contain a password, token or secret (checked by
  review of the stills and of the capture's frames at 1 fps).
- **SC-003**: Both articles have 0 broken links at publication.
- **SC-004**: During the voting week, the application's Open Exchange page views at least double
  from the 40 recorded in the analysis (measured on 2026-10-04 by the team).
- **SC-005**: The English article is published by 2026-09-30, and the Portuguese one by 2026-10-01.

## Assumptions

- Specs 011 (showcase flow, still picture, demo address), 012 (run history, run log) and 013
  (report steps, result panel) are merged before the final recording; the command still works
  without 012 and 013, showing less.
- The team has Developer Community accounts and edit rights on the Open Exchange listing.
- Posting about one's own contest entry and asking for votes is allowed by the contest rules (the
  team confirms before publishing).
- A public video platform account (for example the team's YouTube channel) is available.
- Music, logos of third parties and paid assets are not used.
