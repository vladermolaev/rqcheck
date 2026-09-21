# The default profile

`default.sh` is the profile `rqcheck.sh` loads when neither `RQ_PROFILE` nor a
repository-local `.rqcheck-profile.sh` names another. It is not BMAD's
default, and the table below is what proves it: of the eleven conventions it
reads, four are what BMAD writes and seven are additions a corpus has to make.

It is not a description of what BMAD emits. Stock BMAD numbers functional
requirements and nothing else, and a traceability graph needs more than that,
so this profile describes the smallest identifier discipline a BMAD tree has to
adopt before the checks have anything to read. A tree that adopted none fails
loudly on the first role that matches nothing.

This document covers what the profile knows. The portable half, meaning what
each check answers and how discovery works, is in `SKILL.md`. How to write a
profile of your own is in `AUTHORING.md`. `bmad-stock.md` covers the sibling
profile that reads a tree which adopted none of these additions.

## What BMAD writes, and what this profile asks for

Each row cites the template the verdict comes from, under
`.claude/skills/bmad-*/`.

| Convention | In BMAD | Source |
|---|---|---|
| `## Epic N: Title`, level 2 | yes | `bmad-create-epics-and-stories/templates/epics-template.md:38-42` |
| `### Story N.M: Title`, level 3 | yes | same file, `:44-59` |
| `**FRs covered:** FR1, FR2` | yes, in the `## Epic List` index | `bmad-create-epics-and-stories/steps/step-02-design-epics.md:133-145` |
| `_bmad-output/planning-artifacts` | yes, the installer's default | `_bmad/config.toml:19-21` |
| `- FR1: …` in the PRD | yes | `bmad-create-prd/steps-c/step-09-functional.md:94-98,141-156` |
| a numbered `NFR` register | no, NFRs are prose under category headings | `bmad-create-prd/steps-c/step-10-nonfunctional.md:123-145` |
| a release phase beside each requirement | no, and inventing one is a named failure | `bmad-create-prd/steps-c/step-08-scoping.md:16,251` |
| a coverage table with `Requirement` and `Epic` columns | no, a flat `FR1: Epic 1 - …` list | `bmad-create-epics-and-stories/steps/step-02-design-epics.md:160-167` |
| `ADR-N` decision records | no, decisions are unnumbered prose under topic headings | `bmad-create-architecture/steps/step-04-decisions.md:205-246` |
| an `AR` or `DC` register | no, neither identifier exists in any template | — |
| counter blocks in frontmatter | no, and no template states a count of the corpus | — |

The first four rows are why the profile's epic and story patterns, its epic
coverage line and its artifact path are what they are. The rest are additions,
and each one is a thing a corpus has to do before a check can read it.

Three of the additions change what a role can promise, which is why `ar`, `dc`
and `adr` are optional: a tree carrying none of them still answers every
question except the decision half of `uncited`.

The coverage map is the one addition with no optional form. `verify` diffs
declared coverage against a per-requirement epic assignment, and a corpus that
records that assignment nowhere leaves the check nothing to diff against.

The shape of the map is a different question from whether one exists. This
profile reads a table, by the two column names below. A flat
`FR1: Epic 1 - …` list is read by `map_line` instead, and `bmad-stock.sh` is
the profile that sets it. So a tree keeping its map flat changes profile rather
than losing the check, and a tree keeping no map at all gets a fatal unresolved
`map` role under either.

## Namespaces

| Prefix | Declared in | Declaration form | Role |
|---|---|---|---|
| FR, NFR | the PRD | `- FR1: …` or `- **FR1** …` | `prd`, required |
| AR | the additional-requirements register | `AR1: …` at line start | `ar`, optional |
| DC | the decomposition-constraints register | `DC1: …` at line start | `dc`, optional |
| ADR | the architecture registers | `#### ADR-1 — …` | `adr`, optional |

Every alternation over these is built by `rq_alt`, which orders the names
longest first. A name that is a suffix of another swallows it when the shorter
one comes first: a bare `ADR` matches inside `DEVOPS-ADR` and a bare `FR`
inside `NFR`, and each mistake yields a confident wrong answer rather than an
error. A profile introducing a prefixed namespace passes both names to `rq_alt`
and gets the ordering without meeting the trap.

## Resolving the PRD, and what nothing can resolve

The probe matches a requirement declaration in either the plain form BMAD's
template writes or the bolded form a tree that numbers its NFRs tends to adopt.
It carries no further discrimination, and none is available: a subsidiary
register restating a condensed requirement list writes those restatements in
exactly the shape the PRD writes its declarations, so no probe over the line
can tell an original from a restatement.

Three things stand between that and a wrong answer, and they are ordered.
`probe_derived` removes the documents whose frontmatter says they are about
other documents, which is where copies mostly live. Ranking then takes the
document declaring the most, which a subsidiary list by construction is not.
A near tie is fatal, because two comparable candidates is a corpus that carries
the document twice and cannot say which is the register.

What that leaves uncovered is a corpus whose subsidiary register declares
*more* requirements than the PRD. Discovery resolves it silently and wrongly.
`doctor`'s candidate table is the only thing that catches it, which is why
every consuming skill runs `doctor` first and reads the resolved paths.

A profile can close the gap on a corpus whose PRD marks its requirements in a
way no subsidiary list copies: a release phase, a priority, a status. That is a
vocabulary a corpus chose, so it belongs in that corpus's own profile and not
here.

## Which roles are optional, and what a corpus loses without them

| Role | Absent means | What reports SKIPPED |
|---|---|---|
| `ar` | no architecture-requirement register | `counts`, `stale`, `uncited`, `impact` |
| `dc` | no decomposition-constraints register | `counts`, `stale`, `uncited` |
| `adr` | no numbered architecture decisions | `counts`, `uncited` |

`uncited` loses the most. The AR register is what bridges a decision into the
story graph, so without it every ADR reads as cited by nothing, which is the
shape of a complete answer and the content of none. The check says SKIPPED and
omits that half rather than reporting the whole decision set. Without an ADR
register there is nothing on the far side of the bridge either, so the
architecture graph is left unbuilt rather than emitted to cite a namespace no
document declares.

Absence is tolerated. Ambiguity is not, for an optional role exactly as for a
required one: no candidate means a corpus that does not carry the document, two
candidates means a corpus that does and cannot say which.

## Declared counters

Both counter tables are empty here, because no BMAD template states a count of
the corpus in frontmatter or in a sentence. A tree that keeps such counts by
hand fills them in, and the keys it uses are its own: `stale` matches a
declaration to a derivation by key, so the key vocabulary belongs to the corpus
that writes it and never to the engine.

`counters_table` rows are `key<TAB>kind<TAB>argument...`, over five kinds
`rqcheck.sh` documents above `computed_counters`. `lines` counts matching lines
across a role's documents, `docs` counts the documents, `maxnum` takes the
highest integer any match holds, `minus` subtracts one already-computed key
from another, and `perdoc` writes one key per document of a role. A row naming
an unknown kind, or a role the profile does not declare, fails at load.

`inline_counters_table` pairs a key with the pattern selecting a sentence that
asserts a count and the pattern taking its digits. The scope pattern carries
the specificity and the value pattern carries none: a bare `([0-9]+) rows`
matches a dozen unrelated tables across a corpus, so the value pattern is only
ever applied to a line the scope pattern already selected. The table is
tab-separated, so an editor expanding tabs to spaces silently empties it and
`stale` then reports the prose side as clean.

## The bounded table

`bounded_table` names a role whose document enumerates, in a table, how each of
a set of requirements is discharged. It is empty here, since no BMAD template
produces such a table. A profile that turns it on owes the two column names
that identify the table, the identifier pattern its cells carry, the two keys
the counts are declared under, and the sentence a recount is reported with.

A count is derivable when the thing it counts has one mechanical shape. The
row count qualifies: locate the table by the header naming its columns, read
the column positions from that header by name, count the data rows.

The count of distinct requirements such a table reaches does not qualify. A
cell opens with the identifiers its row is about, then may reach a further
identifier inside a clause, and whether that one is a second subject of the row
or scenery explaining the first is a reading of the row's own prose. That prose
carries no mechanical proxy for the reading, because a row may discharge a
requirement through the name of its obligation rather than through the
identifier, so an identifier the prose never spells can still be a subject. A
probe deciding this from the text is wrong on such a row, and wrong with the
confidence it brings to every other row.

So the facility brackets the figure instead of deriving it. The identifiers a
cell opens with are a floor, those plus every clause-embedded one a ceiling,
and both bounds are mechanical. A declared figure outside the bracket is
`STALE`. One inside it is `RECOUNT`, reported with the clause identifiers
named, so a recount reads those few cells rather than the whole table.

Recording the reading itself, as a profile list of which clause identifiers
count, is the tempting alternative and the wrong one. A profile holds
conventions, which survive any edit that keeps the authoring style. Such a list
would hold contents, and survive only while a handful of cells keep their
present wording. Rewording one cell would then break a tool rather than a
document, and under `all` it would take `verify`, `partition`, `orphans`,
`uncited` and `dangling` down with it.

That line divides this document from the corpus too. Both describe the shapes a
probe reads, and neither names a requirement. The tool reports the instances at
runtime instead, `doctor` printing the bracket and `RECOUNT` naming the cells
inside it, so an example written down here would be a copy that drifts exactly
as a copied count does.
