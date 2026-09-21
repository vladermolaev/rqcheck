# Portability: what this resolves on corpora it has never seen

The README claims no more than the evidence carries, and this is the evidence.
Six public repositories carrying BMAD planning trees were shallow-cloned and
read with both shipped profiles, `doctor` first and then `all`.

The headline: **neither shipped profile resolved any of the six without an
override.** One pair reached `all` with exit 0, and its answer was wrong for a
reason the section on that repository gives. Six hand-written profiles, one per
corpus, brought all six to exit 0, and the minimum change each needed is named
below.

## The six corpora

| Repository | FR | NFR | Epics | Stories | Licence |
|---|---|---|---|---|---|
| [mqgama/study-league-bmad](https://github.com/mqgama/study-league-bmad) | 24 | 7 | 7 | 26 | MIT |
| [AnthonyMarcelin/QuoiJouer](https://github.com/AnthonyMarcelin/QuoiJouer) | 10 | 9 | 3 | 12 | none |
| [MohamedAdelEid/delivai-bmad](https://github.com/MohamedAdelEid/delivai-bmad) | 32 | 10 | 7 | 48 | none |
| [leandrobrando-dev/commerce-tools-research](https://github.com/leandrobrando-dev/commerce-tools-research) | 82 | 23 | 7 | 89 | none |
| [mibrahim2007/email-engine](https://github.com/mibrahim2007/email-engine) | 57 | 25 | 8 | 46 | MIT, in the README |
| [bdebon/bmad-poc](https://github.com/bdebon/bmad-poc) | 7 | 5 | 3 | 12 | none |

Five of the six carry no licence file, so none of them can be vendored here as
a fixture. The runs below are reproducible from a clone.

## Results

| Corpus | `default.sh` | `bmad-stock.sh` | With its own profile |
|---|---|---|---|
| study-league | `prd` and `map` unresolved | `prd` unresolved, map parses 0 of 24 | exit 0 |
| QuoiJouer | `prd` and `map` unresolved | `prd` unresolved, map parses 0 of 10 | exit 0 |
| delivai | `prd` and `map` unresolved | `prd` unresolved, map parses 0 of 32 | exit 0 |
| commerce-tools | `map` unresolved | exit 0, and wrong | exit 0, `verify` exact 82/82 |
| email-engine | `map` unresolved, `epic` wrong | `map` unresolved | exit 0 |
| bmad-poc | `prd` ambiguous, `map` unresolved | the same | exit 0, needs `RQ_EXCLUDE` |

`doctor` exited 0 in all twelve baseline runs and named the unresolved role
each time, which is what it is for.

## Three findings that are about the tool rather than the corpora

**Resolving a role and reading it are separate failures, and only the first is
loud.** `bmad-stock.sh` locates the coverage map by the heading
`### FR Coverage Map`, which three of these corpora carry above a map its flat
reader takes no row from. The role resolves, `verify` reports `SKIP`, and
nothing says the reader found the document and could not read it. `doctor`
prints the parsed entry count beside the map document for exactly this, so
`map epics.md (0 entries parsed)` is what a reader sees rather than a resolved
path.

**A probe matching exactly one document resolves, whether or not it is the
right one.** In email-engine the `epic` role took `docs/stories/index.md`,
whose `## Epic 1 — Foundation and tenancy` headings are the only level-2 epic
lines in the tree, while the real epic documents are `docs/prd/epic-*.md` using
level 3. In commerce-tools it took `stories.md` and missed `epics.md`, which
uses level 3 for its epic list. Both look like clean resolutions. Nothing
mechanical separates one document matching a probe from the right document
matching it, which is why every consuming workflow is told to read `doctor`'s
resolved paths before acting on a check.

**A green exit is not an answer.** commerce-tools under `bmad-stock.sh` exits
0. Its `epic` role resolves to `stories.md`, which carries no `## Epic List`
heading, so `start_epic_decl` cuts away the whole document and the declared
coverage graph is empty. Every requirement then reads as both
`MAP-CLAIMS-NOT-IN-EPIC` and orphaned, which is a complete-looking report of a
graph that was never built.

## The single most common change: the hyphen

Three of six corpora spell their identifiers `FR-1` rather than `FR1`, and all
three fail the `prd` role on it before anything else is tested. Neither shipped
profile tolerates the hyphen, and neither should: `FR-1` and `FR1` are two
vocabularies, and a default matching both would let one corpus spell its
namespace two ways and see `orphans` conflate them. It is a one-line override:

    id_req="$(rq_alt NFR FR)-[0-9]+"

with `probe_prd`, `req_prd`, `ref_epic_decl` and `ref_epic_story` rebuilt from
it.

## Per corpus

### study-league-bmad

Declarations are `- **FR-1:** …` in a monolithic `epics.md`. The PRD writes its
requirements as `#### FR-1: …` headings, so it is not a candidate for a
list-shaped probe at all, and the `prd` role lands on the epics document.

The coverage map is a table headed `| FR | Epic | Descrição breve |`, so the
column name is `FR` rather than `Requirement`, and the epic cell reads
`Epic 2` rather than `2`.

Needs: the hyphen, `map_col_req='FR'`, `probe_map` for the `FR` column name,
and the monolith epic wiring `bmad-stock.sh` carries.

Two findings survive under its own profile, both corpus properties. Epic 3
writes its coverage as the range `FR-5–FR-13`, so the requirements inside the
range read as uncited. And a roll-up line `- **NFR-1/3/5/7** — …` matches the
declaration probe a second time, which reqflow reports as a duplicate.

### QuoiJouer

Declarations are `- **FR-1 — …** : …`. The coverage map is flat, one bulleted
line per requirement: `- **FR-1** : Epic 2 — …`.

Needs: the hyphen, and a `map_line` matching the bulleted bolded form. The
declaration probe has to be anchored on the em-dash, because without it the
coverage-map rows match the declaration probe too and every requirement is
declared twice.

Under its own profile the only finding is that the epics claim NFRs the
FR-only coverage map does not list.

### delivai-bmad

Declarations are bare lines, `FR-1: …`, with no list marker, inside fenced
blocks in `epics.md`. The fences make no difference, since both this tool and
reqflow read lines rather than markdown structure. The coverage map is a table
headed `| FR | Epic | Story |` whose epic cell reads
`Epic 1: Platform & Multi-Tenant Foundation`.

Needs: the hyphen, `probe_prd="^$id_req:"`, `map_col_req='FR'`, `probe_map` for
it, and the monolith epic wiring.

The cleanest of the six under its own profile: exit 0 with empty stderr. Its
findings are all corpus-level, seven requirements declared by more than one
epic and ten NFRs the map does not carry.

### commerce-tools-research

The largest, and the only one with numbered decision records. It splits the
graph across three documents: `prd.md` declares, `epics.md` holds the coverage
map and the epic list at level 3, and `stories.md` holds the epic bodies at
level 2 and the stories. `probe_derived` correctly dropped its four research
write-ups, which is the filter doing its job on a corpus it has never seen.

Needs: `probe_epic` and `epic_heading` widened to `^#{2,3} Epic [0-9]+` so both
epic documents join the set, a `stop_epic_decl` matching what follows the epic
list in `epics.md`, and a `start_epic_story` that keeps `epics.md` out of the
story graph so the two documents do not declare the same epics.

With those it reports `verify ok: exact match, 82/82`, which is the strongest
single result here: a coverage map of 82 rows, maintained by hand, agreeing
exactly with what the epic documents declare. Its remaining findings are nine
requirements declared twice and 23 NFRs no epic claims.

### email-engine

A `docs/` tree rather than `_bmad-output/`, sharded. Epics are
`### Epic 1 — Foundation and tenancy`, with an em-dash where the template uses
a colon, and stories are bold paragraphs rather than headings.

It carries no epic-keyed coverage map. `docs/prd/traceability.md` maps each
requirement to a story and an acceptance criterion, and says so itself: the
epics cite no requirement numbers, so the mapping lived in the author's
reasoning rather than in the artifact. The honest minimum is to declare the
`map` role optional. A profile can also read the epic number out of the leading
digit of the story number, and doing so makes `verify` report what the document
already admits.

### bmad-poc

The smallest, and the one that fails in the most interesting way. `docs/prd.md`
is a monolith and `docs/prd/requirements.md` is a verbatim shard of its
requirements section. Both declare 12 requirements, neither carries a
frontmatter marker, and the `prd` role refuses the tie:

    role 'prd' does not resolve: prd/requirements.md has 12 matches and
    prd.md has 12, too close to call. One is likely a copy of the other.

That is the near-tie guard working exactly as intended. No probe over the line
can separate an original from a verbatim shard, so the resolution is the
caller's: `RQ_EXCLUDE` naming the shard.

It carries no coverage map at all, so `map` has to be optional, and `verify`
then reports that it parsed no rows.

## What this says about the claim

The engine reads its conventions from a profile. Six corpora it had never seen,
in four declaration dialects, across two directory layouts, all resolve under a
profile of twenty-odd lines, and the engine was not changed for any of them.

What it does not say is that a shipped profile fits an unmodified tree. One
did, on one corpus, and gave a wrong answer while exiting 0. Point this at a
new corpus, run `doctor`, and read the resolved paths and the map entry count
before believing a check.
