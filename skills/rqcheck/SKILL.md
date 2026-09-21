---
name: rqcheck
description: Answer requirement-traceability questions over a planning-artifact tree by extracting its identifier graph with reqflow, instead of reading the registers or improvising search patterns over them. Use when the user says "rqcheck", "check traceability", "what cites this requirement", "which requirements are uncovered/orphaned", "verify the coverage map", or when a planning workflow needs the requirement-to-epic-to-story graph.
---

# Requirement traceability (rqcheck)

**Goal:** answer questions about the identifier graph in a planning-artifact
tree by running `rqcheck.sh`, rather than by reading the registers or
improvising search patterns over them.

Run `./rqcheck.sh doctor` first, and read which profile loaded and which file
each role resolved to. Then `./rqcheck.sh all`.

`./rqcheck.sh` means the script beside this file. It derives its own directory,
so a terminal can run it by that path from anywhere, and `${CLAUDE_SKILL_DIR}`
names the directory when this skill is installed as part of a plugin.

## Why this exists

Answering a traceability question by reading the registers costs the whole
corpus, and answering it by grep costs every line a search pattern hits. Both
scale with the prose. The identifier graph does not, so on a graph of
non-trivial size extracting it is cheaper than reading around it by orders of
magnitude, and the gap widens as the registers grow.

Cost is not the only reason. Grep reports lines, and the question is almost
always which story or decision a citation belongs to. A reference belongs to the
heading that encloses it, which is positional, and reqflow tracks position where
a search pattern cannot.

## Commands

    ./rqcheck.sh all                 every check below
    ./rqcheck.sh counts              register sizes
    ./rqcheck.sh stale               declared counters, frontmatter and prose
    ./rqcheck.sh partition           a requirement declared by two epics
    ./rqcheck.sh verify              declared coverage against the coverage map
    ./rqcheck.sh orphans             requirements no written epic declares
    ./rqcheck.sh uncited             AR/DC no story cites, ADR no AR rests on
    ./rqcheck.sh dangling            citations of an id declared nowhere
    ./rqcheck.sh impact <ID>         what cites one id
    ./rqcheck.sh doctor              which profile loaded, what discovery
                                     resolved, every candidate, and what the
                                     filters removed
    ./rqcheck.sh emit [decl|story|arch]  print a generated reqflow config
    ./rqcheck.sh report [outfile]    forward and reverse HTML matrices

`verify` is the highest-value check. It reconstructs from the epic files alone
whatever part of the coverage map those files cover, and diffs it, reporting
`EPIC-CLAIMS-NOT-IN-MAP` and `MAP-CLAIMS-NOT-IN-EPIC` on divergence. The map is
authored by hand, so this is what keeps it honest.

`partition` and `verify` are complementary rather than redundant. `verify`
compares sets, so a requirement claimed by two epics leaves the covered set
unchanged and only `partition` catches it.

The map itself comes in two shapes and the profile says which. A table is
located by its header and its columns are resolved from that header by name, so
re-ordering them changes nothing. A flat list of one line per requirement is
read by a whole-line pattern capturing the identifier and the epic number. A
profile owes one shape or the other, never both and never neither.

`stale` guards the rule below. A document stating a register's size holds a copy
of a fact the corpus already carries, and the copy drifts the moment the
register moves. The check recomputes every counter it has a probe for and diffs
it against every declaration of that counter. A counter no probe reaches is
reported `UNCHECKED` rather than passed silently, and a document declaring only
such counters is passed over.

Four verdicts. `STALE` is a declaration the corpus contradicts. `RECOUNT` is a
declaration falling inside bounds a probe can bracket but outside anything it
can derive. It is advisory, and it names the cells to re-read. `UNCHECKED` is a
declaration no probe reaches at all. Silence is a match.

A declaration takes either of two forms, and both land in one key namespace. A
frontmatter counter block is a parsable leaf, matched by `probe_idx` in any
document that carries one. A sentence asserting a count is the same duplication
without the leaf, and it hides the harder drift. An acceptance criterion stating
a table's row count goes stale the moment that table grows, and no other word in
the document changes to show it. The profile's `inline_counters_table` is what
lets a prose assertion diff against the same computed probes as a frontmatter
leaf and report with a line number rather than with a key alone. Inline
declarations are read from the registers only. A report states what it found on
a day and a change proposal quotes the text it replaced, so a figure in either
is a record rather than a claim.

Report counts from `counts` and `doctor` rather than from this document. Naming
a register's size in prose remains the thing to avoid. A guarded count is one an
editor must be told to re-derive, not one that maintains itself.

## The profile

Every convention the checks read — the document roles, the probe locating each
one, the identifier namespaces, the reqflow `-req` and `-ref` patterns, the
counter tables and the default artifact path — lives in a profile file.
`rqcheck.sh` itself names no namespace, no heading shape and no counter key.

Resolution order, reported by `doctor` on the same terms discovery reports a
resolved document:

1. `$RQ_PROFILE`, which is an error rather than a fallback when it names no file
2. `<repo>/.rqcheck-profile.sh`, where `<repo>` is the git root above the
   working directory, and which is skipped outside a repository
3. the skill's own `profiles/default.sh`

Two profiles ship. `default.sh` reads a tree that numbers its requirements, its
decisions and its constraints and keeps its coverage map in a table.
`bmad-stock.sh` reads the tree BMAD's own templates emit, whose map is a flat
list. Each carries a `.md` beside it naming what it knows, and `AUTHORING.md`
in the same directory is how to write a third.

The profile is sourced as shell rather than parsed as data. The rationale in a
role table is worth more than the patterns themselves, and only a shell file
keeps that reasoning beside what it explains. The cost is executing code from a
file found by search, which is the same trust this skill already asks for when
it runs a binary over the repository's contents. A profile calls `rq_role`,
`rq_alt`, `rq_alt_nc`, `rq_ids` and `rq_extend`, and assigns variables. Nothing
in one reads a file or runs a command.

A profile with holes names every one of them in a single run. Authoring one is
a loop of running the tool and fixing what it names, and raising the first
fault alone would make that loop as long as the profile has holes.

A profile that omits a pattern fails at load rather than inside a check, because
a pattern expanding to the empty string matches every line and would report
confidently on the whole corpus. Which patterns are owed follows from which
roles the profile declares, so a corpus with no architecture-requirement
register owes neither `req_ar` nor the `ref_adr` its bridge would have cited
with, and one that turns the bounded table off owes none of the six names that
facility reads.

Four roles are the floor: `prd`, `map`, `epic` and `adr`. The checks name those
directly, so a profile omitting one leaves the engine with no reading at all
rather than with a narrowed one, and loading it is an error. Declaring one is
not the same as requiring the document: a profile may declare `adr` optional,
and a corpus recording its decisions as unnumbered prose then loses the
decision half of `uncited` and keeps every other answer.

### Namespaces, and the alternation nothing should have to order by hand

A profile names its identifier namespaces through `rq_alt`, which orders them
longest first, and builds every probe and pattern from the result. A name that
is a suffix of another swallows it when the shorter one comes first: a bare
`ADR` matches inside `DEVOPS-ADR` and a bare `FR` inside `NFR`. Each mistake
yields a confident wrong answer rather than an error, so the ordering is the
engine's job. `rq_alt` writes the grep form and `rq_alt_nc` the non-capturing
form a reqflow pattern needs to keep its own capture at group 1.

### Extending a profile rather than copying one

`rq_extend <name|path>` loads a base profile and lets the rest of the file
override what it assigned. A bare name resolves against the skill's own
profiles directory, so a repository profile opens with
`rq_extend default` and then holds only its differences. Re-declaring a
role replaces the base's entry in place rather than adding a second.

The alternative is a repository profile that copies the default and diverges
from it, which is the drift this whole skill exists to refuse one level up: a
copy of a register is the failure discovery is built against, and a copy of a
profile is the same failure applied to the thing doing the discovering.

What extending costs is that the patterns a run used are spread over two files,
and a change to the base reaches every profile extending it without anyone
editing those. `doctor` prints every file the chain loaded, in load order, so
the resolution stays as loud as a one-file one, and the resolved documents it
prints beside them are what a reader checks. A base change that still resolves
to the same documents changed nothing that matters, and one that does not shows
up as a different path or as a hard error.

### Counters are a vocabulary, so they live in the profile

`stale` matches a declaration to a derivation by key, so the key names are a
convention of whatever corpus writes them. `counters_table` is where a profile
states both: one row per key, naming the kind of derivation and its arguments,
over five kinds `rqcheck.sh` documents above `computed_counters`. A row naming
an unknown kind, or a role the profile does not declare, fails at load rather
than inside the check, because `computed_counters` runs inside a pipeline and a
failure there would leave `stale` reporting on the rows it had already read.

`bounded_table` names the role whose document enumerates something in a table
the engine can count rows of and bracket identifiers in. A profile that turns
it on owes the column names, the identifier pattern, the two keys and the
recount sentence. One that leaves it empty owes none of them, and no check
mentions the facility at all.

## Required and optional roles

Each role declares whether the corpus must carry it.

    rq_role <name> <single|unique|set> <required|optional> [skip note]

A required role matching no document is fatal. An optional role matching none
resolves to nothing, and every check that reads it prints
`SKIPPED <role>: <note>` and omits the part of its answer that depended on it.
A check that silently narrowed its answer instead would be a new way to produce
a green wrong answer, which is the exact failure this skill is built to refuse.

Ambiguity is fatal either way. Absence is a corpus that does not carry the
document. Two candidates is a corpus that does and cannot say which, and no
amount of optionality resolves that.

The three resolution modes:

`single` takes the best-ranked candidate, for a probe counting declaration
lines. A near-tie does not resolve, because a copy of a register declares as
many lines as the register.

`unique` requires exactly one match, for a probe matching a table *header*.
Such a probe counts a line or two per document, so ranking one candidate
against another at 1 to 1 carries no information at all.

`set` takes every match. The counter probe works this way too: any candidate may
state counts in its frontmatter, so `stale` reads every match instead of picking
a winner, and a second register declaring counters is ordinary rather than the
ambiguity the other roles refuse.

`doctor` prints one line per role the profile declares, named as the profile
names it. A facility a profile leaves off is absent from the report rather than
reported as a document the corpus owes.

## Documents are found by content, not by filename

Nothing in the harness names a file. Each role is located by a probe describing
what the document *contains*, so a rename, a move or a re-shard changes nothing.
`doctor` prints what every role resolved to, every candidate each role ranked
with its match count, and every document the filters below removed.

Probes fail loudly. The alternative failure — analyzing the wrong document and
reporting `ok` — is the one worth engineering against, and it is the one a
warning does not prevent, because a warning leaves the run to continue on a
guess.

### A copy of a register outranks nothing, so copies never reach the ranking

A probe counts declaration lines, and a document quoting a register's
declarations carries as many as the register. Ranking cannot tell an original
from a copy at all, so the copies have to be gone before ranking starts.

Two filters remove them, and `doctor` lists what each one took.

`probe_derived` drops a document whose frontmatter marks it as being *about*
other documents: a report, a validation, a review, a research write-up or a
change proposal. `inputDocuments` cannot serve as that marker, because a PRD, an
architecture register and an epics index may each carry one. Consuming a source
is not the same as being a report on it.

The keys it names are a profile's, because which workflows a tree runs and what
those workflows write in their frontmatter is a property of the tree.

`RQ_EXCLUDE` takes colon-separated paths, absolute or relative to
`$RQ_ARTIFACTS`. A workflow that appends to a document under the artifact tree
and then runs a check reads its own writing back, and the writing skill is the
only thing that knows its output file is not a register. A path naming no file
is an error rather than a no-op, since an exclusion that silently excludes
nothing recreates the failure the filter exists to prevent.

The two are not redundant. `probe_derived` tracks BMAD's report templates rather
than any one corpus's contents, so a template inventing a new frontmatter key
slips past it, and it slips past silently. The hard error on an unresolved role
is what keeps that miss from becoming a green wrong answer, and `RQ_EXCLUDE` is
what a caller uses to clear the error without waiting for the probe to learn the
new key.

`WRITTEN_THROUGH` derives from the highest epic number carrying a story file.
Set it explicitly only to override that.

## The three graphs

`decl` reads only what each epic's preamble claims it delivers, cutting capture
at the implementation note. It is the delivery graph, and it is what `verify`
diffs against the coverage map.

`story` reads every requirement and decision citation anywhere in an epic and
attributes it to the enclosing story. It is the citation graph, and it is richer
but conflates two senses of citation: an epic that names a requirement to say it
does *not* deliver it reads as coverage. Scope disclaimers naming a requirement
another epic owns are the usual source, so prefer `decl` wherever the question
is who delivers something.

`arch` declares every ADR and reads the bridge register's citations of them, so
the architecture requirements carry decisions into the story graph. `impact`
spans the story and architecture graphs together.

So `verify`, `partition` and `orphans` read `decl`, `uncited` and `dangling`
read `story` and `arch`, and `impact` reads both.

## What it cannot answer

reqflow sees identifier citations and nothing else. It cannot judge whether an
acceptance criterion is testable, whether a story delivers what its requirement
states, or anything the editorial rules cover. Read the prose for those.

It also has no phase or scope awareness, which shows up in two places.

`orphans` mixes "the epic is not written yet" with "genuinely dropped". An epic
can hold a coverage-map row before it holds a story file, and a requirement
owned by such an epic is indistinguishable here from one nobody claimed.
Separating the two needs the map's phase and epic columns.

`uncited` reports decisions that are correctly uncited. A register records
decisions about what is deliberately absent, and about phases no story has
reached, and neither kind is meant to be cited by a story. Read each before
treating it as a gap.

## How much to trust it

The engine is exercised by `test/rqcheck.bats` against two synthetic corpora
under two vocabularies: a generic fixture keeping its coverage map in a table
and its counters under keys the engine does not know, and a stock fixture
shaped as BMAD's templates emit one, keeping its map as a flat list and
carrying no numbered decision at all. A check passing on one and not the other
is reading a convention from the script. That is evidence the engine reads its
conventions from a profile, and it is not evidence that any profile's probes
are right about a corpus nobody has run them against.

Both fixtures are synthetic, so they can only fail the ways their author
thought of. A corpus with a different heading convention, a different namespace
shape or a much larger register may hit a case the probes silently mishandle
even where every check reports clean. `PORTABILITY.md` in the repository root
names the public corpora this has actually been run against and what each one
resolved.

The economics still favor using it. A mechanical pass over the identifier
graph costs a few seconds and no extra context beyond its summary, where the
manual alternative costs the whole corpus in reasoning. That asymmetry holds
even when the tool is imperfect, provided its output is treated as a fast
first pass and not as proof.

A consuming skill should:

- Run `./rqcheck.sh doctor` first and read the profile line and the resolved
  paths, before running any check whose answer it will act on. A check reports
  on whatever documents discovery handed it, and every other item on this list
  passes when discovery picked a faithful copy of the right register. Reading
  which file each role resolved to is the only thing that catches that.
- Pass its own output file in `RQ_EXCLUDE` whenever it writes into the artifact
  tree and then runs a check. A workflow that appends to a document in the tree
  and reads the tree afterwards is reading its own writing.
- Treat `SKIPPED` as an unanswered question rather than a pass. The role it
  names is a document this corpus does not carry, and the part of the check that
  needed it did not run.
- Spot-check at least one entry from a check's output against the source
  documents before using that check to gate a HALT, a required item, or a
  final assessment. An `ok` or an empty list is the result most worth
  spot-checking, because nothing else in the workflow catches it if it is
  wrong.
- Fall back to reading the documents directly for that one check, rather
  than proceeding on faith, when `rqcheck.sh` errors, reports an unresolved
  role, or returns something that contradicts what the workflow already knows
  about the corpus.
- Tell the user what looked wrong when a spot check or a fallback disagrees
  with `rqcheck.sh`: the command run, the expected result, the actual one.
  The same gap recurs on the next corpus that exercises it, so it belongs in
  front of the person who can fix the probe.

## Editing the patterns

Every probe and every reqflow pattern lives in the profile, and `AUTHORING.md`
beside the profiles is what covers writing one: the required keys, the three
role modes, the five counter kinds, the alternation helpers and the traps that
yield a wrong answer rather than an error.

Two things belong here rather than there, because they are about reading the
output rather than writing the patterns.

reqflow emits two diagnostics that read alike and mean different things.
`Undefined requirement, referenced by: X` is a citation of an id declared
nowhere, which is a real defect. `Reference without requirement` is a citation
with no enclosing heading, which is a configuration gap and shows up here as
`UNATTRIBUTED`.

A parse reqflow abandoned still produces a coverage table, and every
requirement in the part it never read reads as uncovered, so the diagnostic is
warned on rather than discarded. The line-length ceiling is the one that bites:
a line of 4096 characters or more ends the file's parse, and everything after
it vanishes. So an empty stderr is worth asserting alongside an exit code.

## Two strings in the output name namespaces rather than roles

`uncited`'s heading and the `ADR=` label `counts` prints for the architecture
graph's total spell `FR/NFR/AR/DC/ADR`, which is the vocabulary the shipped
profiles use. A corpus spelling its identifiers differently reads a heading
that does not describe it.

Both are output rather than matching, so neither can produce a wrong answer.
They are the last of the vocabulary the engine carries, and they are named here
so a reader of a differently-spelled corpus knows to read past them.

## Tests

`bats test/` runs the suite, and it needs no corpus but its own. Every check
runs against the generic fixture under `test/fixtures/generic-profile.sh` and
against the stock fixture under `profiles/bmad-stock.sh`. The two share no
vocabulary: a different declaration form, a different coverage-map shape,
different counter keys and a different document layout. Cases skip rather than
fail where reqflow is not built.

A repository that carries a planning tree of its own keeps its cases beside
that tree rather than here. A published suite reading a host repository would
pass only where one happened to be checked out.

## The root, and running from outside a repository

`RQ_ARTIFACTS` names the tree to read. Left unset, it comes from the profile's
default path resolved against the git root above the working directory, and
outside a repository there is no root, so it becomes mandatory and the error
says so.

Nothing derives a root from this script's own location. That derivation is
right for a copy vendored beside the tree it reads and wrong for one installed
once under a home directory or unpacked into a plugin cache, where it names the
home and the run then reads a profile and an artifact tree from there. Reading
the wrong tree and reporting `ok` is the failure this whole harness is
engineered against, so the derivation is absent rather than guarded.

The repository-profile step is skipped outside a repository for the same
reason. `doctor` prints `root (none)` and names the tree in full.

## The reqflow interface

The checks read four shapes of reqflow's output, and none is a promised
interface. reqflow ships no man page, its own docs list the output formats by
name without specifying a column, and each shape is a `printf` in `main.cpp`.
An upstream that reformatted one would not be breaking a contract, and the
failure would be silent: a `stat -v` whose status column moved reports every
requirement covered, and `orphans` then prints nothing, which is the shape of a
clean corpus.

So the shapes are asserted against a four-line corpus the script writes itself,
once per run, before any answer rests on them. The assertions are behavioural
and no version is compared, since a consumer builds reqflow from source and a
version test would fail a build that still behaves. A failure names the shape
that moved and the version the assertions were written against. There is no way
to switch the check off, because a reqflow whose output moved does not produce
a worse answer, it produces a confident wrong one.

## Prerequisites

reqflow is not vendored, and nothing of it is shipped here. Build it from
`github.com/goeb/reqflow`, which is GNU Autotools rather than CMake:
`./bootstrap.sh`, then `../configure && make` from a build directory. It needs
`libzip`, `libxml-2.0`, `poppler-cpp` and `libpcre`. Then put the binary on
`PATH` or set `REQFLOW`. There is no third place the script looks, since a
build directory under some particular home is one machine's layout.

`RQ_ARTIFACTS` points the checks at an artifact tree, which is how the fixture
and mutation tests run against a copy. `RQ_PROFILE` selects a profile.
`RQ_EXCLUDE` drops named paths from discovery. `WRITTEN_THROUGH` overrides the
highest epic number carrying a story file. `./rqcheck.sh help` prints all five,
and answers outside a repository and with no artifact tree, since a reader with
neither is who runs it first.
