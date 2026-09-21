# The stock BMAD profile

`bmad-stock.sh` reads a BMAD planning tree exactly as BMAD's own templates emit
one. `default.sh` reads a tree that adopted an identifier discipline on top of
them. Neither is better than the other, and which one a corpus wants is settled
by one question: does its coverage map sit in a table, or in the flat list the
template writes?

Every override below cites the template that forces it. The templates are
installed under `.claude/skills/bmad-*/` in a repository that has BMAD, and
`_bmad/_config/files-manifest.csv` carries a SHA-256 for each, so a citation is
checkable rather than remembered.

## What the overrides are

| Key | Value | Template |
|---|---|---|
| `map_line` | `^(NFR[0-9]+\|FR[0-9]+): Epic ([0-9]+).*$` | `bmad-create-epics-and-stories/steps/step-02-design-epics.md:160-167` |
| `probe_map` | `^#+ FR Coverage Map` | `bmad-create-epics-and-stories/templates/epics-template.md:30-32` |
| `map_col_req`, `map_col_epic` | empty | the same two |
| `req_epic_decl` | `^### (Epic [0-9]+)` | `steps/step-02-design-epics.md:133-145` |
| `start_epic_decl` | `^## Epic List` | the same |
| `stop_epic_decl` | `^## Epic [0-9]+` | `templates/epics-template.md:34-42` |
| `req_epic_story` | `^### (Epic [0-9]+\|Story [0-9]+\.[0-9]+)` | `templates/epics-template.md:44-59` |
| `start_epic_story` | `^## Epic List` | as above |

## The coverage map is a list, so it is read as one

The template writes the map as one line per requirement under a level-3
heading:

    ### FR Coverage Map

    FR1: Epic 1 - [Brief description]
    FR2: Epic 1 - [Brief description]

There is no table anywhere in `bmad-create-epics-and-stories`, so a reader that
resolved columns by name would find none. `map_line` is a whole-line pattern
whose first capture is the identifier and whose second is the epic number, and
the anchor is what keeps it off the `**FRs covered:**` lines, which name
identifiers mid-line rather than at a line start.

The pattern is built with `rq_ids` rather than `rq_alt`. `map_line` is read as
a POSIX extended regular expression, which has no non-capturing group, so an
alternation that opened a group of its own would push the epic number into
capture 3 and leave capture 2 holding a namespace name. Every row's epic would
then evaluate as zero, every row would pass the written-epic test, and the map
would parse clean and wrong. The engine counts the groups and refuses a third,
and `rq_ids` is what keeps the namespace ordering right without the author
meeting either trap.

## One document holds everything, so the graph is cut out of it

BMAD writes the coverage map, the epic index and every epic body into a single
`epics.md`. Three consequences follow.

The declaration graph reads the index rather than the bodies. An epic states
what it delivers once, as a `**FRs covered:** FR1, FR2` line under a level-3
index entry. The bodies further down carry no identifier at all, so a graph
built from them is empty and `verify` then reports every requirement missing.
So `req_epic_decl` captures the index entries.

The graph needs a start as well as a stop. The coverage map sits above the
index, and its own identifiers would otherwise read as citations belonging to
no epic, which reqflow reports as `Reference without requirement` and this tool
prints as `UNATTRIBUTED`. `start_epic_decl` cuts above the index and
`stop_epic_decl` cuts below it, at the first level-2 `## Epic N:` body heading.
`## Epic List` is level 2 as well but carries a word where a digit is needed,
so it does not match the stop.

The story graph captures level-3 headings only. Capturing `## Epic 1:` as well
would declare `Epic 1` twice in one document, once from the index entry and
once from the body.

## What a stock tree cannot answer

`uncited` needs an architecture-requirement register to bridge a decision into
the story graph, and BMAD writes decisions as unnumbered prose under topic
headings (`bmad-create-architecture/steps/step-04-decisions.md:205-246`). No
identifier exists to trace, so the `adr`, `ar` and `dc` roles all resolve to
nothing and every check reading one prints `SKIPPED`.

`stale` derives nothing, because no BMAD template states a count of the corpus
in frontmatter or in a sentence.

What remains is `counts`, `partition`, `verify`, `orphans` and `dangling`, and
those are the checks the coverage map and the epic index can support.

## Where a monolith reads differently from a sharded tree

`written_through` is the highest epic number carrying a story file. A tree with
one file per epic drops an unwritten epic's file entirely, so its requirements
fall out of the declaration graph and out of the map comparison together. A
monolith keeps the unwritten epic's index entry, so the declaration graph
claims a requirement the map restricts away, and `verify` reports it as
`EPIC-CLAIMS-NOT-IN-MAP`.

That is the true reading rather than a defect. An index entry claiming delivery
with no body behind it is a claim the corpus makes and cannot yet support, and
naming it is the answer. A tree that would rather not hear about it sets
`WRITTEN_THROUGH` to the epic it has actually written.
