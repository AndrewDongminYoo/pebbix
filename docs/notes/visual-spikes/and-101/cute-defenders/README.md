# AND-101 cute defenders approval packet

Status: **9:16 gameplay prototype approved by the operator on 2026-08-08; minimal spike packet complete and awaiting PR review.**

This folder is the visual authority for the revised AND-101 direction.
This self-contained folder is the only AND-101 visual evidence retained on this branch and does not replace current runtime assets.
AND-102 remains blocked until AND-101 is merged.

## Approved direction

Pebbix follows four small alien neighbors led by Cosmo as they try to protect their home with equipment they barely know how to repair.
They are a cohesive invented species with tiny bean-shaped bodies, simple facial marks, mismatched antennae, and different reactions to the same crisis.
Their appeal comes from looking gentle, ordinary, and comically unqualified rather than heroic, armed, or infant-like.

The rendering language uses thin consistent indigo-brown outlines, flat saturated fills, almost no shading, and only restrained hard highlights on bubbles.
The supplied casual-game screenshots informed the high-level mood of a harmless ensemble only.
Characters, silhouettes, poses, launcher, planet, bubble layout, UI, palette mapping, typography, and composition are independently authored.

## 13+ general-casual guardrails

The small rounded cast is an operator-approved emotional direction, not a change to the fixed audience declaration.
Gameplay screenshots keep the defenders subordinate to the board, score pressure, and aiming lane rather than presenting a character-only storybook surface.
AND-102 and release marketing must exclude infant props, nursery patterns, educational prompts, parent-directed copy, toy-like sound cues, and other explicit child-directed signals.
Store copy and screenshots foreground endless survival, score chasing, deterministic aiming, and bank-shot mastery.
If those surrounding surfaces drift toward child-directed marketing, the product decision must be reopened before art production continues.

## Visual authority

[The approved gameplay prototype](prototype-gameplay.png) is a `941 × 1672` portrait image, within integer rounding of a `9:16` ratio.
It establishes the four-neighbor scale, the non-Earth home planet, the arched bubble field, the open aiming lane, and the small repaired-telescope launcher.
The launcher barrel, loaded bubble, and dotted preview share one aim axis.

## Approval surface

- [Approval board](and-101-approval-board.png) presents the complete packet in one view.
- [Gameplay prototype](prototype-gameplay.png) is the operator-approved style authority created before individual assets.
- [Background concept](background-concept.png) reserves the central aiming lane while concentrating decoration at the upper and outer edges.
- [Star bubble](bubble-star.png) and [ring bubble](bubble-ring.png) are transparent representative sprites with non-color symbols.
- [Defender squad body](defender-squad-body.png) and [launcher arm](cosmo-launcher-arm.png) are equal-size transparent layers.
- [Aim-angle proof](cosmo-aim-angles.png) rotates only the launcher arm through `-35`, `0`, and `+35` degrees.
- [Game-over composition](game-over-comp.png) applies the approved language to the Continue and Skip result state.
- [App-icon thumbnails](app-icon-thumbnails.png) compare four mask-safe character crops.
- [22-pixel accessibility proof](bubble-accessibility-22px.png) compares color, grayscale, and grayscale over bright effects.
- [Prompt manifest](PROMPTS.md) records generation briefs, source hashes, processing fallback, and output provenance.

## Layer contract

The mascot evidence uses one `1254 × 1254` squad body canvas and one equal-size launcher-arm canvas.
Cosmo and the neighbors never rotate with the aim.
The launcher arm rotates around the measured hub center `(627, 925)`.
The arm orientation remains visible when trajectory assistance is hidden.

## Scope boundary

This packet stops at one background, two representative bubble sprites, one defender pose split into body and launcher layers, one game-over composition, four app-icon thumbnails, one aim-angle proof, one 22-pixel accessibility proof, and one approval board.
It does not produce the complete six-bubble set, animation states, production icons, localized UI, renderer integration, or shipping assets.

## Acceptance status

| Requirement                                  | Evidence                                            | Status                         |
| -------------------------------------------- | --------------------------------------------------- | ------------------------------ |
| Harmless original defender squad             | Approved gameplay prototype                         | Approved                       |
| Cute but not overtly toddler-styled          | Approved gameplay prototype                         | Approved                       |
| Separate permanent launcher cue              | Equal-size transparent layers and three-angle proof | Demonstrated                   |
| Non-color bubble identities                  | Star and ring representative sprites                | Demonstrated                   |
| 22-pixel grayscale readability               | Exact-size grayscale and bright-effect proof        | Passed for two representatives |
| Cohesive gameplay, result, and icon language | Prototype, game-over composition, and icon sheet    | Awaiting PR review             |
