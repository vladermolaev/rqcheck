# rqcheck

Answer requirement-traceability questions over a planning-artifact tree by
extracting its identifier graph, instead of reading the registers or
improvising search patterns over them.

    rqcheck.sh doctor      which profile loaded, what discovery resolved
    rqcheck.sh all         every check
    rqcheck.sh impact FR7  what cites one identifier

Every convention of the corpus — the document roles, the probe locating each
one, the identifier namespaces, the coverage-map shape, the counter keys —
lives in a profile file. The engine names none of them.

## Why extract the graph

Answering a traceability question by reading the registers costs the whole
corpus, and answering it by grep costs every line a search pattern hits. Both
scale with the prose. The identifier graph does not, so on a graph of
non-trivial size extracting it is cheaper by orders of magnitude, and the gap
widens as the registers grow.

Cost is not the only reason. Grep reports lines, and the question is almost
always which story or decision a citation belongs to. A reference belongs to
the heading that encloses it, which is positional, and a traceability engine
tracks position where a search pattern cannot.

## Install

Three ways, and a plain copy is one of them.

A per-project or per-user skill directory, with no tooling at all:

    cp -R skills/rqcheck ~/.claude/skills/rqcheck        # per user
    cp -R skills/rqcheck <repo>/.claude/skills/rqcheck   # per project

As a plugin, which makes the install a versioned one. This repository is its
own marketplace:

    /plugin marketplace add <owner>/rqcheck
    /plugin install rqcheck@rqcheck

A plugin install is pinned to the `version` in `.claude-plugin/plugin.json`, so
a change reaches an installed copy only when that version moves. That is the
property to want from a shared tool and the thing to remember while developing
one.

Checked into a repository so every clone gets the same version, in
`.claude/settings.json`:

    {
      "extraKnownMarketplaces": {
        "rqcheck": { "source": { "source": "github", "repo": "<owner>/rqcheck" } }
      }
    }

Adding the marketplace does not install the plugin. Each person still runs
`/plugin install rqcheck@rqcheck` once.

Nothing is stripped on install. The tests and fixtures travel with the skill,
so an installed copy can be verified where it sits.

## What a consuming repository writes

A skill installed as a plugin is namespaced, so it is listed and invoked as
`rqcheck:rqcheck`. A plain skill directory is invoked as `rqcheck`. A workflow
that calls it should name both, since it cannot know which install the reader
has:

> Invoke the `rqcheck` skill, which a plugin install lists as `rqcheck:rqcheck`,
> and run `./rqcheck.sh doctor` first. Read the `prd`, `map` and `epic` lines
> and confirm each names the document you expect. A check reports on whatever
> discovery handed it.

`./rqcheck.sh` means the script beside `SKILL.md`. The script derives its own
directory, so a terminal can run it by that path from anywhere.

A repository keeps its own profile at `.rqcheck-profile.sh` in its root, which
`rqcheck.sh` finds through git. It opens with `rq_extend default` and holds
only its differences. Copying a shipped profile and diverging from it is the
drift this whole tool refuses one level up: a copy of a register is the failure
discovery is built against, and a copy of a profile is the same failure applied
to the thing doing the discovering.

A repository that carries a planning tree also keeps its own test cases beside
that tree. The suite in `skills/rqcheck/test/` reads its own fixtures and
nothing else, because a published suite that read a host repository would pass
only where one happened to be checked out.

## Prerequisites

reqflow does the parsing, and none of it is shipped here. Build it from
[github.com/goeb/reqflow](https://github.com/goeb/reqflow), which is GNU
Autotools rather than CMake:

    git clone https://github.com/goeb/reqflow.git
    cd reqflow && ./bootstrap.sh
    mkdir build && cd build && ../configure && make

It needs `libzip`, `libxml-2.0`, `poppler-cpp` and `libpcre`, all four of them
hard requirements. Then put the binary on `PATH` or set `REQFLOW`.

bats-core runs the suite. `shellcheck -S warning` is clean on every `.sh` here.

## The reqflow interface, and why the check is not optional

This tool reads four shapes of reqflow's output, and none is a promised
interface. reqflow ships no man page, its own documentation lists the output
formats by name without specifying a column, and every shape is a `printf` in
`main.cpp`. An upstream that reformatted one would not be breaking a contract.

The failure would be silent. A `stat -v` whose status column moved reports
every requirement covered, and `orphans` then prints nothing, which is the
shape of a clean corpus.

So the shapes are asserted against a four-line corpus the script writes itself,
once per run, before any answer rests on them. The assertions are behavioural
and no version is compared, since a consumer builds reqflow from source and a
version test would fail a build that still behaves. A failure names the shape
that moved and the version the assertions were written against, Reqflow 1.6.0.
There is no way to switch the check off, because a reqflow whose output moved
does not produce a worse answer, it produces a confident wrong one.

## The name

The project does not lead with reqflow's name, for three reasons. It would
imply an affiliation with a GPL project that this only invokes across a process
boundary. It would put this repository's issues and reqflow's in the same
search results, to neither project's benefit. And reqflow is an implementation
detail behind a capability check rather than the contract, so a name built on
it would have to change if the backend did.

`rqcheck` is the script's own name. The one thing to know about it is that a
Python job queue and a JSON command-line tool both answer to `rq`.

## Licensing

This project is MIT. See `LICENSE`.

reqflow is GPL-2.0-or-later, by Frederic Hoerni, at
[github.com/goeb/reqflow](https://github.com/goeb/reqflow). Nothing of it is
shipped, vendored, linked or derived from here. `rqcheck.sh` is a shell script
that runs the `reqflow` binary as a separate process and reads its standard
output, which imposes no licence condition on the caller. You build reqflow
yourself, under its own terms.

## What this knows about BMAD, and what BMAD actually writes

The `default.sh` profile is not BMAD's default. Stock BMAD numbers functional
requirements and nothing else. Every claim below cites the template it comes
from, under `.claude/skills/bmad-*/` in a repository that has BMAD installed,
and `_bmad/_config/files-manifest.csv` carries a SHA-256 for each so a citation
is checkable.

| Convention | In stock BMAD | Template |
|---|---|---|
| `## Epic N: Title`, level 2 | yes | `bmad-create-epics-and-stories/templates/epics-template.md:38-42` |
| `### Story N.M: Title`, level 3 | yes | same file, `:44-59` |
| `**FRs covered:** FR1, FR2` in the `## Epic List` index | yes | `bmad-create-epics-and-stories/steps/step-02-design-epics.md:133-145` |
| `- FR1: …` in the PRD | yes | `bmad-create-prd/steps-c/step-09-functional.md:94-98,141-156` |
| `_bmad-output/planning-artifacts` | yes, the installer's default | `_bmad/config.toml:19-21` |
| a coverage map as a flat `FR1: Epic 1 - …` list | yes | `bmad-create-epics-and-stories/steps/step-02-design-epics.md:160-167` |
| a coverage map as a table | no | the same, and no markdown table exists anywhere in that skill |
| numbered `NFR` identifiers | no, NFRs are prose under category headings | `bmad-create-prd/steps-c/step-10-nonfunctional.md:123-145` |
| a release phase beside each requirement | no, and inventing one is a named failure | `bmad-create-prd/steps-c/step-08-scoping.md:16,251` |
| `ADR-N` decision records | no, decisions are unnumbered prose under topic headings | `bmad-create-architecture/steps/step-04-decisions.md:205-246` |
| an `AR` or `DC` register | no, neither identifier exists in any template | — |
| counter blocks in frontmatter | no, and no template states a count of the corpus | — |

Two profiles ship against that. `bmad-stock.sh` reads the tree those templates
emit, and answers `counts`, `partition`, `verify`, `orphans` and `dangling`.
`default.sh` reads a tree that adopted an identifier discipline on top of them,
and answers `stale` and `uncited` as well. `profiles/AUTHORING.md` is how to
write a third.

## How far this has actually been proven

Not as far as "works with BMAD". The evidence is:

- Two synthetic fixture corpora under two vocabularies, in
  `skills/rqcheck/test/fixtures/`. Both were written by the author of the
  engine, so they can only fail the ways that author thought of.
- One private corpus of 130 requirements, 141 architecture requirements and 54
  decisions, which is not public and cannot be cited.
- Six public repositories carrying BMAD planning trees, run under both shipped
  profiles. `PORTABILITY.md` reports what resolved, what did not, and what each
  corpus would have to change. The short version is that neither shipped
  profile resolved any of the six without an override, and the report says
  which key each one needed.

A corpus with a different heading convention, a different namespace shape or a
much larger register may hit a case the probes silently mishandle even where
every check reports clean. Treat the output as a fast first pass, not as proof.

## What CI cannot assert

The matrix runs bats on Linux and macOS, which is what catches BSD against GNU
divergence in `sort -V`, `paste -sd`, `xargs -0`, `grep -o`, `sed -E`
backreferences and bash 3.2 semantics. It also runs the whole suite once from
outside any git repository, which is the shape of a per-user install.

What it does not reach:

- Any real corpus. Every fixture is synthetic and small, so no CI run exercises
  a register of a few hundred requirements, a sharded tree, or the 4096-byte
  line that ends a reqflow parse and takes the rest of the file with it.
- Whether a probe resolved the right document. A probe matching exactly one
  document resolves, and CI has no way to know that document was the wrong one.
  `PORTABILITY.md` records two public corpora where this happened.
- Whether an answer is true. The checks report on the identifier graph, and
  whether a story delivers what its requirement states is not in that graph.
- The skill's behaviour as a skill. CI runs `rqcheck.sh`, not a model reading
  `SKILL.md` and deciding what to do with it.
- reqflow's future output. The `reqflow-master` job builds upstream's head and
  is allowed to fail, so it warns rather than gates.
