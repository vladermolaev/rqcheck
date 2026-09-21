# Writing a profile

A profile is the whole of what `rqcheck.sh` knows about a corpus. The engine
names no identifier namespace, no heading shape and no counter key, so pointing
it at a new tree is a matter of writing one file.

Start by extending a shipped profile. `default.sh` reads a BMAD tree that
numbers its requirements, its decisions and its constraints, and keeps its
coverage map as a table. `bmad-stock.sh` reads the tree BMAD's templates emit,
whose map is a flat list. A repository profile opens with `rq_extend default`
and holds only its differences.

## The bootstrap loop

1. Write a file that extends the closest shipped profile and changes nothing.
2. Run `rqcheck.sh doctor` with `RQ_PROFILE` naming it and `RQ_ARTIFACTS`
   naming the tree.
3. Read the faults. A profile with holes names every one of them in a single
   run, so one pass over the list is one edit pass over the file.
4. Read the resolved documents, then the candidate table under
   `## candidates per role`. That table ranks every role's probe over every
   candidate, including the roles that resolved to nothing, so a probe matching
   the wrong document and a probe matching none look different there.
5. Read `## filtered out of discovery`. A document missing from the ranking was
   removed by `probe_derived` or by `RQ_EXCLUDE`, and this is where it says so.
6. Repeat until every role names the document you expect. Then run `all`, and
   read stderr as carefully as stdout.

`doctor` survives an unresolved role, so it reaches step 4 on a profile that no
check would run under. A separate mode that ranked probes without requiring
resolution would therefore answer a question `doctor` already answers. What
`doctor` cannot survive is a profile that fails to load, which is why loading
collects every fault rather than raising the first.

`emit decl`, `emit story` and `emit arch` print the reqflow configuration a run
would use. When a check reports something you did not expect, the config is
where the patterns are visible as reqflow will read them, after every shell
expansion and every backslash.

## The keys a profile owes

Missing or empty is a fault for the first group. Missing is a fault for the
second, and empty is an answer.

| Key | What it holds |
|---|---|
| `rq_artifacts_default` | the artifact tree, relative to the repository root |
| `id_req` | a requirement identifier, for grep |
| `id_arch` | an architecture-decision identifier, for grep |
| `probe_idx` | a frontmatter counter block |
| `probe_derived` | a frontmatter key marking a document as being about others |
| `probe_<role>` | one per role the profile declares |
| `req_prd` | the PRD's requirement declarations, for reqflow |
| `req_adr` | the architecture registers' decision declarations |
| `req_epic_decl`, `ref_epic_decl` | the delivery graph's headings and citations |
| `req_epic_story`, `ref_epic_story` | the citation graph's headings and citations |
| `stop_epic_decl` | where the declared-coverage block ends |
| `epic_heading` | the heading whose digits are an epic's number |

| Key | Empty means |
|---|---|
| `map_line` | the coverage map is a table, read by `map_col_req` and `map_col_epic` |
| `start_epic_decl` | the delivery graph starts at the top of each epic document |
| `start_epic_story` | so does the citation graph |
| `counters_table` | no document states a derivable count |
| `inline_counters_table` | no sentence asserts a count |
| `bounded_table` | no document enumerates a set in a bracketed table |

A profile declaring an `ar` role also owes `req_ar` and `ref_adr`, one
declaring a `dc` role owes `req_dc`, and one declaring either owes `id_dec`.
`ref_adr` belongs to `ar` rather than to `adr`, because the ADR registers
declare and the bridge register is what cites them.

A profile setting `bounded_table` owes `bt_col_id`, `bt_col_key`, `bt_id`,
`bt_key_rows`, `bt_key_ids` and `bt_note`. One leaving it empty owes none of
them, and no check mentions the facility at all.

Four roles are the floor: `prd`, `map`, `epic` and `adr`. The checks name those
directly, so a profile omitting one leaves the engine with no reading rather
than a narrowed one.

## Roles

    rq_role <name> <single|unique|set> <required|optional> [skip note]

`single` takes the best-ranked candidate and refuses a near tie, for a probe
counting declaration lines. A copy of a register declares as many lines as the
register, so two comparable candidates is a corpus that carries the document
twice and cannot say which is the original.

`unique` requires exactly one match, for a probe matching a table header. Such
a probe counts a line or two per document, so ranking one candidate against
another at 1 to 1 carries no information.

`set` takes every match. The counter probe works this way too: any document may
state counts in its frontmatter, so `stale` reads every match instead of
picking a winner.

A required role matching nothing is fatal. An optional role matching nothing
resolves to nothing, and every check reading it prints `SKIPPED <role>: <note>`
and omits the part of its answer that depended on it. Ambiguity is fatal either
way. Absence is a corpus that does not carry the document, two candidates is a
corpus that does and cannot say which, and no amount of optionality resolves
that.

Re-declaring a role in an extending profile replaces the base's entry in place
rather than adding a second.

## Counters

`counters_table` rows are `key<TAB>kind<TAB>argument...`, over five kinds.

| Kind | Arguments | What it derives |
|---|---|---|
| `lines` | `<role> <ERE>` | matching lines across the role's documents |
| `docs` | `<role>` | how many documents the role resolved to |
| `maxnum` | `<role\|*> <ERE>` | the highest integer any match holds |
| `minus` | `<keyA> <keyB>` | one already-computed key less another |
| `perdoc` | `<role> <idERE> <ERE>` | one key per document, `{n}` becoming the digits of the first `idERE` match |

`minus` reads the rows above it, so a table states its operands first. A row
naming an unknown kind, or a role the profile does not declare, is a fault at
load rather than a miscount inside `stale`.

`maxnum` over `*` reads every candidate rather than one role's documents. A
report enumerating what it found would otherwise raise the ceiling.

`inline_counters_table` rows are `key<TAB>scope pattern<TAB>value pattern`. The
scope pattern selects the sentence and carries all the specificity. The value
pattern takes the digits and carries none, because it is only ever applied to a
line the scope pattern already selected.

The key names belong to the corpus. `stale` matches a declaration to a
derivation by key, so a tree that names its counters differently changes this
table and nothing else.

## Namespaces, and the alternation nothing should order by hand

A name that is a suffix of another swallows it when the shorter one comes
first. A bare `ADR` matches inside `DEVOPS-ADR` and a bare `FR` inside `NFR`,
and each mistake yields a confident wrong answer rather than an error. Three
helpers keep the ordering out of the author's hands.

`rq_alt NFR FR` gives `(NFR|FR)`, a capturing group of namespace names, for a
grep probe.

`rq_alt_nc NFR FR` gives `(?:NFR|FR)`, the non-capturing form, for a reqflow
pattern whose own capture must stay group 1. reqflow reads PCRE, so `(?:` is
available there.

`rq_ids '[0-9]+' NFR FR` gives `(NFR[0-9]+|FR[0-9]+)`, one group holding a
whole identifier. `map_line` needs this. It is read as a POSIX extended regular
expression, which has no non-capturing group, so a nested `rq_alt` would open a
second group and push the epic number into capture 3. The engine counts the
groups and refuses a pattern carrying a third, because that mistake makes every
row's epic evaluate as zero and the map parse clean and wrong.

## Extending rather than copying

`rq_extend <name|path>` loads a base profile and lets the rest of the file
override what it assigned. A bare name resolves against this directory.

The alternative is a profile that copies a base and diverges from it, which is
the drift this whole tool refuses one level up. A copy of a register is the
failure discovery is built against, and a copy of a profile is the same failure
applied to the thing doing the discovering.

What extending costs is that the patterns a run used are spread over two files,
and a change to the base reaches every profile extending it without anyone
editing those. `doctor` prints every file the chain loaded, in load order, and
the resolved documents beside them are what a reader checks. A base change that
still resolves to the same documents changed nothing that matters, and one that
does not shows up as a different path or as a hard error.

## The traps

Each of these yields a wrong answer rather than an error.

The config parser consumes backslashes, so every reqflow pattern is written in
doubled form. A literal asterisk is `\\*`, and `^- \\*\\*(FR[0-9]+)` is what
reaches reqflow as `^- \*\*(FR[0-9]+)`. A probe read by grep is written once,
undoubled, and a key serving both is written twice.

The counter tables are tab-separated. An editor expanding tabs to spaces
empties them silently, and `stale` then reports the prose side as clean.

`define NAME value` in a reqflow config substitutes textually and unanchored,
so `define P <path>` rewrites the `P` inside `DEVOPS` and corrupts the pattern.
The generator writes absolute paths and uses no `define`.

A document may declare a namespace or cite it, never both. Giving a document a
`-ref` matching its own `-req` makes its declarations vanish, which is why the
ADR registers declare and the bridge register cites.

A reference binds to the enclosing captured requirement. A citation appearing
before the first `-req` match is reported `UNATTRIBUTED` rather than attributed
to the document, which is what `start_epic_decl` and `start_epic_story` exist
to cut above.

`-stop-after` excludes the matching line onward, so a boundary is the line that
follows the covered block rather than the last covered line.

An unanchored `map_line` matches any line naming an identifier, and a coverage
map that sits in a document alongside an epic index will then read the index
entries as map rows.

`probe_derived` reads a document's frontmatter alone, so a register quoting one
of its keys in prose or inside a fenced block keeps its candidacy. Widening it
to the whole file would retire whichever register mentioned a report key, and
the role it held would then resolve to something else.

reqflow abandons a file's parse at a line of 4096 characters or more, and every
requirement after that line vanishes. The parse still produces a coverage
table, so the loss reads as a corpus whose later requirements are uncovered.
The diagnostic goes to stderr and this tool warns on it rather than discarding
it, which is why an empty stderr is worth asserting alongside an exit code.

## A profile is code, and it is sourced

`rqcheck.sh` sources the profile rather than parsing it as data. The rationale
in a role table is worth more than the patterns themselves, and only a shell
file keeps that reasoning beside what it explains. The cost is executing code
from a file found by search, which is the same trust this tool already asks for
when it runs a binary over a repository's contents.

A profile calls `rq_role`, `rq_alt`, `rq_alt_nc`, `rq_ids` and `rq_extend`, and
assigns variables. Nothing in one should read a file or run a command.
