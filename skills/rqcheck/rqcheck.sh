#!/usr/bin/env bash
#
# Curated reqflow queries over a planning-artifact tree.
#
# Output is compact and deterministic. Extracting the identifier graph costs a
# fraction of reading the registers it is drawn from, and the gap grows with
# them, so on a corpus of non-trivial size this is the cheap way to ask.
# Each subcommand answers one question a BMAD skill would otherwise answer by
# improvising a search pattern over the corpus.
#
# The document roles, the probes locating them and the reqflow patterns read
# from them all live in a profile file. `doctor` prints which profile loaded
# and from where, and the profile beside it documents the namespaces it knows.
#
# Usage:  rqcheck.sh [counts|stale|partition|verify|orphans|uncited|dangling|all]
#         rqcheck.sh impact <ID>          a requirement or decision identifier
#         rqcheck.sh report [outfile]     forward and reverse HTML matrices
#         rqcheck.sh doctor              what discovery resolved, and drift
#         rqcheck.sh emit [decl|story|arch]  print a generated reqflow config
#
# Documents are located by what they CONTAIN rather than by filename, so a
# rename, a move or a re-shard does not break the harness. `doctor` reports
# what each role resolved to, and every candidate it ranked. Every probe fails
# loudly: a required role matching no file, or any role matching two files
# comparably well, is an error rather than a silently wrong answer. An optional
# role the corpus does not carry leaves the checks reading it printing SKIPPED,
# which is neither an error nor an ok.
#
# Environment:
#   RQ_ARTIFACTS the artifact tree to read. Default comes from the profile,
#                resolved against the git root above the working directory.
#                Outside a repository there is no root, so it is mandatory.
#   RQ_PROFILE   the profile to load. Default <repo>/.rqcheck-profile.sh, then
#                the skill's own profiles/default.sh.
#   RQ_EXCLUDE   colon-separated paths that are not registers, absolute or
#                relative to $RQ_ARTIFACTS. A workflow that writes into the tree
#                and then runs a check reads its own writing back, and it is the
#                only thing that knows its output file is not a register.
#   REQFLOW      the reqflow binary. Otherwise the first `reqflow` on PATH.
#   WRITTEN_THROUGH  override the highest epic number carrying a story file.

# Every probe and every reqflow pattern here is assigned by the profile this
# script sources, and shellcheck resolves that only under -x or when the
# profile is passed on the same command line. `set -u` below is what catches a
# misspelled reference instead, and it catches it as a runtime error rather
# than as a pattern expanding to nothing and matching every line. The directive
# is file-level, so it has to precede the first command.
# shellcheck disable=SC2154

set -uo pipefail

D="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'rqcheck: %s\n' "$*" >&2; exit 1; }
warn() { printf 'rqcheck: %s\n' "$*" >&2; }

# The command line is read before the environment is. A misspelled subcommand
# and a missing identifier are the caller's to fix and say nothing about any
# corpus, so answering either with "planning artifacts not found" would name
# the wrong problem. `help` describes this script rather than a tree, and a
# reader running it first has neither a profile nor an artifact tree yet, so it
# answers here and exits before anything looks for one.
#
# The dispatch at the foot of the file repeats these names. It is what actually
# routes a command, and this is only what refuses one, so the two lists are
# checked against each other by the case that runs every subcommand.
case "${1:-all}" in
    all|counts|stale|partition|verify|orphans|uncited|dangling|doctor|emit|report) ;;
    impact)
        [ $# -ge 2 ] || die "usage: rqcheck.sh impact <ID>   a requirement or decision identifier, as the profile's namespaces spell one" ;;
    -h|--help|help)
        # The header block, from the first line of prose to the last
        # environment variable. Located rather than numbered, so an edit to the
        # comment above does not silently truncate what help prints.
        sed -n '3,/^#   WRITTEN_THROUGH /p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0 ;;
    *)  die "unknown command '$1'. Try: all, counts, stale, partition, verify, orphans, uncited, dangling, doctor, emit, impact <ID>, report" ;;
esac

# The repository under the working directory, which is the tree whose artifacts
# and whose profile are being asked about. git is the only thing that names it,
# and outside a repository it stays empty.
#
# Deriving it from this script's own location instead assembles a path from
# wherever the skill happens to sit. That is right for a copy vendored beside
# the tree it reads and wrong for one installed once under a home directory or
# unpacked into a plugin cache, where it names the home and the run then
# resolves a profile and an artifact tree from there. Reading the wrong tree
# and reporting `ok` is the failure this whole harness is engineered against,
# so the derivation is absent rather than guarded.
#
# What the root supplied is supplied another way when there is none. The
# repository-profile step is skipped, because there is no repository, and
# RQ_ARTIFACTS becomes mandatory rather than defaulted. `doctor` prints the
# artifact tree in full rather than relative to the root, since stripping the
# root hides the one part of a path that can be wrong.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || ROOT=""

TAB="$(printf '\t')"

# ---------------------------------------------------------------------------
# Profile
#
# Everything corpus-shaped -- the document roles, their probes, the reqflow
# req/ref patterns, the inline-counter table and the default artifact path --
# comes from here. The engine below names no convention of its own.
#
# The profile is sourced rather than parsed as data. The rationale in a role
# table is worth more than the patterns themselves, and only a shell file keeps
# it beside what it explains. `rq_role` below is the whole of the interface a
# profile calls, and nothing in a profile reads a file or runs a command.
# ---------------------------------------------------------------------------

RQ_ROLES=""

# rq_role <name> <single|unique|set> <required|optional> [skip note]
#
# Re-declaring a role replaces its entry in place rather than adding a second,
# so an extending profile overrides the base's declaration where it sits and
# the order a reader sees is the base's order.
rq_role() {
    case "${2:-}" in single|unique|set) ;; *) die "profile: role '${1:-}' has mode '${2:-}', not single, unique or set." ;; esac
    case "${3:-}" in required|optional) ;; *) die "profile: role '${1:-}' is '${3:-}', not required or optional." ;; esac
    local kept="" line found=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in "$1$TAB"*) line="$1$TAB$2$TAB$3$TAB${4:-}"; found=1 ;; esac
        kept="$kept$line
"
    done <<EOF
$RQ_ROLES
EOF
    [ -n "$found" ] || kept="$kept$1$TAB$2$TAB$3$TAB${4:-}
"
    RQ_ROLES="$kept"
}

# rq_alt <name>... -- an alternation of identifier namespaces, longest name
# first. A name that is a suffix of another swallows it when the shorter one
# comes first: a bare ADR matches inside DEVOPS-ADR and a bare FR inside NFR,
# and both mistakes yield a confident wrong answer rather than an error.
# Ordering is the engine's job rather than each profile's, so a profile that
# introduces a prefix gets the property without knowing about the trap.
#
# rq_alt     the grep -E form, for a probe.
# rq_alt_nc  the non-capturing form, for a reqflow pattern whose own capture
#            group must stay group 1.
rq_alt()    { _rq_alt '(' "$@"; }
rq_alt_nc() { _rq_alt '(?:' "$@"; }
_rq_alt() {
    local open="$1"; shift
    [ $# -gt 0 ] || die "profile: rq_alt needs at least one namespace."
    # One name needs no group at all, and a bare name reads better in the
    # pattern a profile author is checking by eye.
    [ $# -eq 1 ] && { printf '%s' "$1"; return; }
    printf '%s%s)' "$open" \
        "$(printf '%s\n' "$@" | awk '{ print length($0) "\t" $0 }' \
           | sort -k1,1nr -k2,2 | cut -f2 | paste -sd'|' -)"
}

# rq_ids <suffix> <name>... -- ONE capturing group matching a whole identifier
# in any of the namespaces, longest namespace first:
#
#     rq_ids '[0-9]+' NFR FR   ->   (NFR[0-9]+|FR[0-9]+)
#
# Where rq_alt groups the namespace alone and leaves the suffix outside it,
# this puts the whole identifier inside one group. A pattern read as a POSIX
# ERE needs that, because POSIX has no non-capturing group: a nested rq_alt
# would open a second group, every later capture would shift by one, and a
# pattern whose second capture is an epic number would read a namespace name
# there instead. That mistake yields an epic number of zero for every row,
# which passes every "is this epic written yet" test and reports a coverage
# map the corpus does not carry.
rq_ids() {
    local suffix="${1:-}"; shift
    [ $# -gt 0 ] || die "profile: rq_ids needs a suffix and at least one namespace."
    printf '(%s)' \
        "$(printf '%s\n' "$@" | awk -v s="$suffix" '{ print length($0) "\t" $0 s }' \
           | sort -k1,1nr -k2,2 | cut -f2 | paste -sd'|' -)"
}

# rq_extend <name|path> -- load a base profile, then let the rest of this file
# override what it assigns. A bare name resolves against the skill's own
# profiles directory, so a repository profile says `rq_extend default`.
#
# The alternative is a repository profile that copies the default and diverges
# from it, which is the drift this whole skill exists to refuse: a copy of a
# register is the failure discovery is built against, and a copy of a profile
# is the same failure one level up. `doctor` prints every file the chain loaded
# so the resolution stays as loud as a one-file one.
RQ_PROFILE_CHAIN=""
rq_extend() {
    local base="${1:-}"
    [ -n "$base" ] || die "profile: rq_extend needs a profile name or path."
    case "$base" in
        /*)  ;;
        */*) base="$(cd -- "$(dirname -- "$base")" 2>/dev/null && pwd)/$(basename -- "$base")" ;;
        *)   base="$D/profiles/$base.sh" ;;
    esac
    [ -f "$base" ] || die "profile: rq_extend names '$base', which is not a file."
    case "$TAB$RQ_PROFILE_CHAIN" in
        *"$TAB$base$TAB"*) die "profile: rq_extend loops back to '$base'." ;;
    esac
    RQ_PROFILE_CHAIN="$RQ_PROFILE_CHAIN$base$TAB"
    # shellcheck source=/dev/null
    . "$base" || die "base profile '$base' failed to load."
}

if [ -n "${RQ_PROFILE:-}" ]; then
    RQ_PROFILE_PATH="$RQ_PROFILE"; RQ_PROFILE_FROM="RQ_PROFILE"
    [ -f "$RQ_PROFILE_PATH" ] || die "RQ_PROFILE names '$RQ_PROFILE_PATH', which is not a file."
elif [ -n "$ROOT" ] && [ -f "$ROOT/.rqcheck-profile.sh" ]; then
    RQ_PROFILE_PATH="$ROOT/.rqcheck-profile.sh"; RQ_PROFILE_FROM="repo"
else
    RQ_PROFILE_PATH="$D/profiles/default.sh"; RQ_PROFILE_FROM="skill default"
    [ -f "$RQ_PROFILE_PATH" ] || die "no profile: set RQ_PROFILE${ROOT:+, write $ROOT/.rqcheck-profile.sh}, or restore $RQ_PROFILE_PATH."
fi
RQ_PROFILE_CHAIN="$RQ_PROFILE_PATH$TAB"
# shellcheck source=profiles/default.sh
. "$RQ_PROFILE_PATH" || die "profile '$RQ_PROFILE_PATH' failed to load."

[ -n "$RQ_ROLES" ] || die "profile '$RQ_PROFILE_PATH' declares no role. It must call rq_role at least once."

role_declared() {
    printf '%s\n' "$RQ_ROLES" | awk -F"$TAB" -v r="$1" '$1 == r { f = 1 } END { exit (f ? 0 : 1) }'
}

# Everything below validates the loaded profile, and every fault it finds is
# collected rather than raised, so one run names every missing key instead of
# one. A profile is authored by running this script against a tree and fixing
# what it names, and dying on the first fault turns that loop into as many runs
# as the profile has holes.
#
# Collected, not tolerated. A profile with any fault at all loads nothing and
# runs no check, because a pattern expanding to the empty string matches every
# line and would report confidently on the whole corpus.
RQ_FAULTS=""
fault() { RQ_FAULTS="$RQ_FAULTS  $*
"; }

# require_keys <name>... -- each must be set and non-empty.
require_keys() {
    local k
    for k in "$@"; do
        eval "[ -n \"\${$k:-}\" ]" || fault "defines no $k."
    done
}

# Defined, and allowed to be empty. A corpus where no sentence asserts a count
# has nothing to pair a key with, one that declares no counter at all has no
# table to derive, one that enumerates nothing in a bracketed table names no
# role for the facility, and one whose coverage map is a table rather than a
# flat list reads it by column name. An empty value is each of those
# statements. An undefined one is a profile that forgot the question.
require_defined() {
    local k
    for k in "$@"; do
        eval "[ -n \"\${$k+x}\" ]" || fault "defines no $k. Set it empty if the corpus has no such thing."
    done
}

# The roles the checks name directly. A profile omitting one leaves the engine
# with no reading at all rather than with a narrowed one, so these four are the
# floor beneath the required/optional distinction.
for _k in prd map epic adr; do
    role_declared "$_k" || fault "declares no '$_k' role, which every check reads."
done

require_keys rq_artifacts_default probe_idx probe_derived req_prd req_adr \
             req_epic_decl ref_epic_decl req_epic_story ref_epic_story \
             stop_epic_decl id_req id_arch epic_heading

# The coverage map is read one of two ways, and a profile owes exactly one of
# them. `map_line` is a full-line pattern capturing an identifier and an epic
# number, for a flat list of one line per requirement. The two column names are
# for a table, and the engine locates the columns by name inside the file, so
# re-ordering them changes nothing and renaming one is a change in the profile.
#
# Owing both would leave the engine to pick, and whichever it picked would be
# right about half the corpora that set both. Owing neither leaves it with no
# reader at all.
require_defined map_line
# Guarded, because a fault is collected rather than raised and the lines below
# still run with the key that faulted still unset.
if [ -n "${map_line:-}" ]; then
    { [ -n "${map_col_req:-}" ] || [ -n "${map_col_epic:-}" ]; } \
        && fault "sets map_line and also map_col_req or map_col_epic. A coverage map is read as a flat list or as a table, never as both."
    # Exactly two groups, counted rather than trusted. A pattern built from
    # rq_alt carries a third, the engine then reads a namespace name where the
    # epic number belongs, every row's epic evaluates as zero, and the map
    # parses clean and wrong. `rq_ids` is the helper that keeps the identifier
    # alternation inside one group.
    _ng="$(printf '%s' "$map_line" | sed 's/\\\\//g; s/\\(//g' | tr -cd '(' | wc -c | tr -d ' ')"
    [ "$_ng" = 2 ] || fault "sets a map_line with $_ng capture group(s) where the reader needs exactly two, the identifier and the epic number. An alternation built with rq_alt opens one of its own -- use rq_ids for the identifier."
else
    require_keys map_col_req map_col_epic
fi

# Tied to their roles, so a corpus with no such register owes no pattern for
# one. `ref_adr` belongs to `ar` rather than to `adr`: the ADR registers
# declare, and the bridge register is what cites them.
role_declared ar && require_keys req_ar ref_adr
role_declared dc && require_keys req_dc
{ role_declared ar || role_declared dc; } && require_keys id_dec

require_defined inline_counters_table counters_table bounded_table \
                start_epic_decl start_epic_story

# Every counter row names a kind the driver implements, and names a role that
# the profile declares. Checked here rather than where the row runs, because
# `computed_counters` runs inside a pipeline and a failure there would leave
# `stale` reporting on the rows it had already read.
while IFS="$TAB" read -r _k _kind _a1 _ _; do
    [ -n "$_k" ] || continue
    case "$_kind" in
        lines|docs|maxnum|minus|perdoc) ;;
        *) fault "counters_table key '$_k' has kind '$_kind', which is not lines, docs, maxnum, minus or perdoc."; continue ;;
    esac
    case "$_kind" in
        minus) ;;
        maxnum) [ "$_a1" = '*' ] || role_declared "$_a1" || fault "counters_table key '$_k' reads role '$_a1', which the profile does not declare." ;;
        *) role_declared "$_a1" || fault "counters_table key '$_k' reads role '$_a1', which the profile does not declare." ;;
    esac
done <<EOF
${counters_table:-}
EOF

# The bounded-table facility reads one role's document, counts its rows and
# brackets the identifiers its cells reach. Every name it needs is a column
# heading or a key this corpus chose, so a profile that turns it on owes them
# all and a profile that leaves it off owes none.
if [ -n "${bounded_table:-}" ]; then
    role_declared "$bounded_table" || fault "sets bounded_table to '$bounded_table' but declares no such role."
    require_keys bt_col_id bt_col_key bt_id bt_key_rows bt_key_ids bt_note
fi

while IFS="$TAB" read -r _k _ _ _; do
    [ -n "$_k" ] || continue
    eval "[ -n \"\${probe_$_k:-}\" ]" || fault "declares role '$_k' but defines no probe_$_k."
done <<EOF
$RQ_ROLES
EOF

[ -z "$RQ_FAULTS" ] || die "profile '$RQ_PROFILE_PATH' is incomplete, and every fault it carries is named here so one pass fixes them all:
$RQ_FAULTS"

if [ -z "${RQ_ARTIFACTS:-}" ]; then
    # A profile's default artifact path is relative to a repository root, so
    # outside one there is nothing to resolve it against. Guessing a root here
    # is what reads a stranger's tree and reports on it.
    [ -n "$ROOT" ] || die "git names no repository above the working directory, so the profile's default artifact path '$rq_artifacts_default' has no root to resolve against. Set RQ_ARTIFACTS to the tree to read."
    RQ_ARTIFACTS="$ROOT/$rq_artifacts_default"
fi
export RQ_ARTIFACTS

# ---------------------------------------------------------------------------
# reqflow binary
# ---------------------------------------------------------------------------

# REQFLOW, then PATH. A build directory under some particular home would be
# one machine's layout compiled into a script that claims to be portable, so
# there is no third place to look.
RQ="${REQFLOW:-}"
if [ -z "$RQ" ]; then
    command -v reqflow >/dev/null 2>&1 \
        || die "reqflow not found. Build it (see github.com/goeb/reqflow), then put it on PATH or set REQFLOW=/path/to/reqflow."
    RQ="$(command -v reqflow)"
fi
[ -x "$RQ" ] || die "reqflow at '$RQ' is not executable."
[ -d "$RQ_ARTIFACTS" ] || die "planning artifacts not found at '$RQ_ARTIFACTS'."

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

# `doctor` sets this. An unresolved role is fatal everywhere else, and every
# such message points the reader at doctor, so doctor itself has to survive
# reaching one and report it rather than exit on it.
RQ_SOFT=""
resolve_fail() {
    if [ -n "$RQ_SOFT" ]; then warn "$*"; return 1; fi
    die "$*"
}

rel() { printf '%s' "${1#"$RQ_ARTIFACTS"/}"; }

# The caller's own exclusions, one absolute path per line. A path naming
# nothing excludes nothing, and a typo that silently excludes nothing is the
# failure this whole filter exists to prevent, so an unresolvable entry is an
# error rather than a no-op.
excluded_paths() {
    local p
    printf '%s\n' "${RQ_EXCLUDE:-}" | tr ':' '\n' | while IFS= read -r p; do
        [ -n "$p" ] || continue
        case "$p" in
            /*) printf '%s\n' "$p" ;;
            *)  printf '%s\n' "$RQ_ARTIFACTS/${p#./}" ;;
        esac
    done
}

# is_derived <file> -- true when the frontmatter marks the file as a document
# about other documents. Read from the frontmatter alone, so a register that
# quotes one of these keys in its prose or inside a fenced block is untouched.
is_derived() {
    awk -v pat="$probe_derived" '
        NR == 1 && $0 == "---" { fm = 1; next }
        !fm      { exit }
        $0 == "---" { exit }
        $0 ~ pat { hit = 1; exit }
        END { exit (hit ? 0 : 1) }
    ' "$1"
}

# Every document a declaration role may claim, and what the two filters removed.
#
# These live in files rather than in variables because `rank_by_probe` runs
# inside command substitution on almost every call. A subshell's assignment is
# lost on return, so a variable here would rebuild the list on each probe and
# would never carry the drop list back out to `doctor`.
TMP="$(mktemp -d)" || die "cannot create temp dir"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# The reqflow interface check
#
# Every answer below is drawn from reqflow's output, and none of the shapes
# read is a promised interface. reqflow ships no man page, its own docs list
# the output formats by name without specifying a single column, and each shape
# is a printf in main.cpp. An upstream that reformats one would not be breaking
# a contract, because there is no contract.
#
# What that costs is silent. A `stat -v` whose status column moved reports
# every requirement covered, and `orphans` then prints nothing, which is the
# shape of a clean corpus. So the shapes are asserted against a four-line
# corpus this script writes itself, once per run, before any answer rests on
# them.
#
# Tested against Reqflow 1.6.0 (GPL-2.0-or-later, Frederic Hoerni,
# github.com/goeb/reqflow). No version is pinned and none is compared: a
# consumer builds reqflow from source, so a version test would fail a build
# that still behaves and pass one that does not. The assertions are
# behavioural, and the version is named only in what a failure prints.
#
# There is no way to switch this off. A reqflow whose output moved does not
# produce a worse answer, it produces a confident wrong one, and an escape
# hatch here would be a supported route to exactly that.
# ---------------------------------------------------------------------------

RQ_TESTED='Reqflow 1.6.0 (GPL-2.0-or-later, Frederic Hoerni, github.com/goeb/reqflow)'
RQ_VERSION=""
RQ_CHECKED=""

selfcheck_fail() {
    die "reqflow at '$RQ' does not produce the output this script reads: $1.
None of these shapes is a promised interface, so a reqflow whose output moved
reads as a corpus with no findings rather than as an error, which is why this
is fatal. Tested against $RQ_TESTED."
}

selfcheck() {
    [ -z "$RQ_CHECKED" ] || return 0
    RQ_CHECKED=1
    local d="$TMP/selfcheck" out
    mkdir -p "$d" || die "cannot create temp dir"

    # Two requirements, one covered and one not. Then a citation before the
    # first heading, a citation of the covered one, and a citation of an
    # identifier nothing declares -- which is one of each thing the checks
    # below have to tell apart.
    printf '%s\n' '- RQSELF1: cited by the epic below' \
                  '- RQSELF2: cited by nothing' > "$d/prd.txt"
    printf '%s\n' 'RQSELF1, named before any heading in this document' \
                  '## RQEPIC1' \
                  'rests on RQSELF1' \
                  'rests on RQSELF9' > "$d/epic.txt"
    {
        printf 'document PRD -path "%s" -type txt -req "^- (RQSELF[0-9]+):"\n' "$d/prd.txt"
        printf 'document EPI -path "%s" -type txt -nocov -req "^## (RQEPIC[0-9]+)" -ref "(RQSELF[0-9]+)"\n' "$d/epic.txt"
    } > "$d/c.req"

    # `version` exits 1 on success, so the exit status says nothing at all and
    # the string on stdout is the whole of the test.
    RQ_VERSION="$("$RQ" version 2>/dev/null | head -1)"
    case "$RQ_VERSION" in
        Reqflow\ [0-9]*) ;;
        *) selfcheck_fail "'version' printed '$RQ_VERSION' rather than a 'Reqflow <n>' line" ;;
    esac

    # stat -v: column 1 is U for an uncovered requirement and a space for a
    # covered one, column 2 the identifier. `uncovered` reads exactly this, and
    # every caller of it filters the result by namespace, which is why RQEPIC1
    # -- uncovered, and correctly so -- is filtered here too.
    out="$("$RQ" stat -v -c "$d/c.req" 2>/dev/null \
           | awk '$1 == "U" && $2 ~ /^RQSELF/ { print $2 }' | sort | paste -sd' ' -)"
    [ "$out" = "RQSELF2" ] \
        || selfcheck_fail "'stat -v' marked '$out' uncovered where RQSELF2 alone is"

    # stat -s: the register total `counts` reads sits in the field after a
    # lone '/'.
    out="$("$RQ" stat -s -c "$d/c.req" 2>/dev/null \
           | awk '/^PRD /{ for (i = 1; i <= NF; i++) if ($i == "/") { print $(i + 1); exit } }')"
    [ "$out" = "2" ] \
        || selfcheck_fail "'stat -s' put no register total after a '/' field on the PRD line, giving '$out'"

    # trac -x csv: three comma-separated columns, the citing heading in column
    # 2. The rows carry CRLF, so column 3 holds the carriage return and the two
    # columns read here do not.
    out="$("$RQ" trac -c "$d/c.req" -x csv 2>/dev/null \
           | awk -F, '$1 == "RQSELF1" && $2 != "" { print $2 }')"
    [ "$out" = "RQEPIC1" ] \
        || selfcheck_fail "'trac -x csv' names '$out' as citing RQSELF1 where RQEPIC1 does"

    # The two diagnostics `dangling` tells apart, both on stderr. Reading them
    # as one would report a configuration gap as a defect in the corpus.
    out="$("$RQ" stat -s -c "$d/c.req" 2>&1 >/dev/null)"
    case "$out" in
        *"Undefined requirement, referenced by:"*) ;;
        *) selfcheck_fail "a citation of an undeclared identifier raised no 'Undefined requirement, referenced by:' line" ;;
    esac
    case "$out" in
        *"Reference without requirement"*) ;;
        *) selfcheck_fail "a citation before the first heading raised no 'Reference without requirement' line" ;;
    esac
}
CANDF="$TMP/candidates"
DROPF="$TMP/dropped"

build_candidates() {
    [ -s "$CANDF" ] && return 0
    local ex f
    ex="$(excluded_paths | sort -u)"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$f" ] || die "RQ_EXCLUDE names '$f', which is not a file under $RQ_ARTIFACTS. A path matching nothing excludes nothing."
    done <<< "$ex"

    : > "$CANDF"
    : > "$DROPF"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ -n "$ex" ] && printf '%s\n' "$ex" | grep -qxF -- "$f"; then
            printf 'caller%s%s\n' "$TAB" "$f" >> "$DROPF"
        elif is_derived "$f"; then
            printf 'derived%s%s\n' "$TAB" "$f" >> "$DROPF"
        else
            printf '%s\n' "$f" >> "$CANDF"
        fi
    done < <(find "$RQ_ARTIFACTS" -name '*.md' -type f | sort)

    [ -s "$CANDF" ] || die "every document under $RQ_ARTIFACTS was filtered out of discovery. Check RQ_EXCLUDE and probe_derived."
}

# rank_by_probe <pattern> -> "count<TAB>path" lines, highest count first.
rank_by_probe() {
    local pat="$1" f n
    build_candidates
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        n="$(grep -cE "$pat" "$f" 2>/dev/null)" || n=0
        [ "${n:-0}" -gt 0 ] && printf '%s\t%s\n' "$n" "$f"
    done < "$CANDF" | sort -rn
}

# absent <role> <required|optional> <message> -- a role that matched nothing.
# An optional role the corpus does not carry resolves to the empty string and
# says nothing here, because the checks reading it are what report SKIPPED, and
# a run that never reaches one of them has nothing to report.
absent() {
    [ "$2" = optional ] && return 0
    resolve_fail "$3"
}

# one_by_probe <role> <pattern> <required|optional> -> the single best path, for
# a probe counting declarations. A copy of a register declares as many lines as
# the register, so ranking cannot separate the two and a near-tie does not
# resolve. Ambiguity is fatal whether the role is required or optional: absence
# is a corpus that does not carry the document, two candidates is one that does
# and cannot say which.
one_by_probe() {
    local role="$1" pat="$2" req="$3" ranked top_n top_p next_n next_p
    ranked="$(rank_by_probe "$pat")"
    [ -n "$ranked" ] || { absent "$role" "$req" "role '$role' matched no candidate under $RQ_ARTIFACTS. Its document convention may have changed, or a filter removed it: probe was /$pat/"; return 0; }
    top_n="$(printf '%s\n' "$ranked" | head -1 | cut -f1)"
    top_p="$(printf '%s\n' "$ranked" | head -1 | cut -f2)"
    next_n="$(printf '%s\n' "$ranked" | sed -n '2p' | cut -f1)"
    next_p="$(printf '%s\n' "$ranked" | sed -n '2p' | cut -f2)"
    if [ -n "${next_n:-}" ] && [ "$((next_n * 5))" -ge "$((top_n * 4))" ]; then
        resolve_fail "role '$role' does not resolve: $(rel "$top_p") has $top_n matches and $(rel "$next_p") has $next_n, too close to call. One is likely a copy of the other. Run 'doctor' for every candidate, then exclude the copy with RQ_EXCLUDE=<path> or narrow the probe." || return 0
    fi
    printf '%s\n' "$top_p"
}

# unique_by_probe <role> <pattern> -> the only matching path.
# For a probe matching a table HEADER rather than its rows. Such a probe counts
# a line or two per document, so ranking one candidate against another at 1 to 1
# carries no information at all. Exactly one match is the only resolution.
unique_by_probe() {
    local role="$1" pat="$2" req="$3" ranked n
    ranked="$(rank_by_probe "$pat")"
    [ -n "$ranked" ] || { absent "$role" "$req" "role '$role' matched no candidate under $RQ_ARTIFACTS. Its table header may have changed, or a filter removed it: probe was /$pat/"; return 0; }
    n="$(printf '%s\n' "$ranked" | grep -c .)"
    if [ "$n" -ne 1 ]; then
        resolve_fail "role '$role' matched $n documents and a header probe cannot rank them:$(printf '%s\n' "$ranked" | cut -f2 | while IFS= read -r f; do printf ' %s' "$(rel "$f")"; done). Exclude the copies with RQ_EXCLUDE=<path> or narrow the probe." || return 0
    fi
    printf '%s\n' "$ranked" | head -1 | cut -f2
}

# all_by_probe <role> <pattern> -> every matching path, ascending by name.
all_by_probe() {
    local role="$1" pat="$2" req="$3" out
    out="$(rank_by_probe "$pat" | cut -f2 | sort)"
    [ -n "$out" ] || { absent "$role" "$req" "role '$role' matched no candidate under $RQ_ARTIFACTS: probe was /$pat/"; return 0; }
    printf '%s\n' "$out"
}

# Named for the checks that read them. Every other role is reached through
# `role_docs`, which is what a profile-declared role the engine does not know
# about resolves through.
PRD=""; ARREG=""; DCREG=""; MAP=""; EPICS=""; ADRDOCS=""
DISCOVERED=""
discover() {
    [ -z "$DISCOVERED" ] || return 0
    DISCOVERED=1
    # At top level, before the first command substitution below. Building the
    # candidate list inside one would trap its `die` in the subshell, and the
    # roles would then go on resolving against a list nobody vetted.
    build_candidates
    local role mode req pat out
    while IFS="$TAB" read -r role mode req _; do
        [ -n "$role" ] || continue
        eval "pat=\"\$probe_$role\""
        case "$mode" in
            single) out="$(one_by_probe    "$role" "$pat" "$req")" || exit 1 ;;
            unique) out="$(unique_by_probe "$role" "$pat" "$req")" || exit 1 ;;
            set)    out="$(all_by_probe    "$role" "$pat" "$req")" || exit 1 ;;
        esac
        eval "RQV_$role=\$out"
    done <<EOF
$RQ_ROLES
EOF
    PRD="${RQV_prd:-}";  ARREG="${RQV_ar:-}"; DCREG="${RQV_dc:-}"; MAP="${RQV_map:-}"
    EPICS="${RQV_epic:-}"; ADRDOCS="${RQV_adr:-}"
}

# role_docs <role> -- every document the role resolved to, one per line, and
# nothing at all when it resolved to none.
role_docs() {
    local out
    eval "out=\"\${RQV_$1:-}\""
    [ -n "$out" ] || return 0
    printf '%s\n' "$out" | grep -v '^$'
}

# have_role <role> -- true when the role resolved. Otherwise prints one SKIPPED
# line carrying the profile's note for it, so a check that cannot answer says
# which document the corpus is missing. A check answering half its question is
# the one failure mode worth more noise than an ok: nothing downstream
# distinguishes a silently narrowed answer from a complete one.
have_role() {
    local role="$1" out note
    eval "out=\"\${RQV_$role:-}\""
    [ -n "$out" ] && return 0
    note="$(printf '%s\n' "$RQ_ROLES" | awk -F"$TAB" -v r="$role" '$1 == r { print $4; exit }')"
    printf 'SKIPPED %s: %s\n' "$role" "${note:-this corpus carries no such document}"
    return 1
}

# Every document a declared role resolved to, as against every other document
# under the artifact tree. A
# register states what is true now, so a count inside one is a live copy worth
# diffing. A report states what it found on a day and a proposal quotes the text
# it replaced, so a figure in either is a record rather than a claim, and
# `stale` does not read it. `probe_derived` keeps the same distinction for the
# frontmatter counter blocks `stale` reads from every candidate. The set is
# deduplicated by its one caller, which needs each file once.
registers() {
    local role
    while IFS="$TAB" read -r role _ _ _; do
        [ -n "$role" ] || continue
        role_docs "$role"
    done <<EOF
$RQ_ROLES
EOF
}

# Highest epic number carrying a story file. Epics past it exist as
# coverage-map rows only, so their requirements are expected in `orphans`.
written_through() {
    if [ -n "${WRITTEN_THROUGH:-}" ]; then printf '%s\n' "$WRITTEN_THROUGH"; return; fi
    printf '%s\n' "$EPICS" | while IFS= read -r f; do
        [ -n "$f" ] || continue
        grep -ohE "$epic_heading" "$f" | grep -oE '[0-9]+'
    done | sort -n | tail -1
}

# ---------------------------------------------------------------------------
# Config generation
# ---------------------------------------------------------------------------

CFGDIR=""
gen_configs() {
    [ -z "$CFGDIR" ] || return 0
    selfcheck
    discover
    CFGDIR="$TMP/cfg"; mkdir -p "$CFGDIR" || die "cannot create temp dir"

    {
        printf 'document PRD -path "%s" -type txt -req "%s"\n' "$PRD" "$req_prd"
        local i=0 f
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            i=$((i + 1))
            # `-start-after` only when the profile asked for one. A corpus
            # keeping one file per epic needs no start, and a corpus whose
            # single epics document opens with the coverage map needs one --
            # without it the map's own identifiers are read as citations
            # belonging to no epic, and reqflow reports each UNATTRIBUTED.
            printf 'document E%02d -path "%s" -type txt -nocov -req "%s" -ref "%s" -stop-after "%s"%s\n' \
                "$i" "$f" "$req_epic_decl" "$ref_epic_decl" "$stop_epic_decl" \
                "${start_epic_decl:+ -start-after \"$start_epic_decl\"}"
        done <<< "$EPICS"
    } > "$CFGDIR/decl.req"

    {
        printf 'document PRD -path "%s" -type txt -req "%s"\n' "$PRD" "$req_prd"
        # Omitted rather than emitted empty when the corpus carries neither
        # register: a `-path ""` document makes reqflow read nothing and report
        # every citation of the namespace as undefined.
        [ -n "$ARREG" ] && printf 'document AR -path "%s" -type txt -req "%s"\n' "$ARREG" "$req_ar"
        [ -n "$DCREG" ] && printf 'document DC -path "%s" -type txt -req "%s"\n' "$DCREG" "$req_dc"
        local i=0 f
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            i=$((i + 1))
            # As in the declaration graph: a start only where the profile
            # asked for one, for a document whose citations open before its
            # first heading.
            printf 'document E%02d -path "%s" -type txt -nocov -req "%s" -ref "%s"%s\n' \
                "$i" "$f" "$req_epic_story" "$ref_epic_story" \
                "${start_epic_story:+ -start-after \"$start_epic_story\"}"
        done <<< "$EPICS"
    } > "$CFGDIR/story.req"

    {
        # A set role the corpus does not carry emits no document line. A
        # `-path ""` document makes reqflow read nothing and report every
        # citation of the namespace as undefined.
        local i=0 f
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            i=$((i + 1))
            printf 'document A%02d -path "%s" -type txt -req "%s"\n' "$i" "$f" "$req_adr"
        done <<< "$ADRDOCS"
        # The AR register is the bridge: architecture requirements cite the
        # decisions they rest on, and stories cite the AR ids in turn. Without
        # it the graph is declarations alone, so every decision reads as
        # uncited and `uncited` says so rather than reporting the whole set.
        #
        # And without a decision register there is nothing on the far side of
        # the bridge, so the bridge is left out rather than emitted to cite a
        # namespace no document declares. Emitting it would report every such
        # citation undefined, which is a defect in the profile's reading of the
        # corpus rather than in the corpus.
        [ -n "$ARREG" ] && [ -n "$ADRDOCS" ] \
            && printf 'document AR -path "%s" -type txt -nocov -req "%s" -ref "%s"\n' \
                "$ARREG" "$req_ar" "$ref_adr"
    } > "$CFGDIR/arch.req"

    DECL="$CFGDIR/decl.req"
    STORY="$CFGDIR/story.req"
    ARCH="$CFGDIR/arch.req"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

if printf 'b10\nb9\n' | sort -V >/dev/null 2>&1; then SORTU="sort -V -u"; else SORTU="sort -u"; fi
oneline() { $SORTU | paste -sd' ' - ; }

# A parse reqflow abandoned still produces a coverage table, and every
# requirement in the part it never read reads as uncovered. Discarding the
# diagnostic turns that into a confident wrong answer, so it is warned on.
# The line-length ceiling is the one that bites here: a long implementation
# note ends the file's parse, and the epic's citations vanish silently.
uncovered() {
    local out err line
    err="$CFGDIR/uncovered.err"
    out="$("$RQ" stat -v -c "$1" 2>"$err")"
    while IFS= read -r line; do
        [ -n "$line" ] && warn "reqflow: $line"
    done < "$err"
    printf '%s\n' "$out" | awk '$1=="U"{print $2}'
}

all_reqs() { grep -ohE "$probe_prd" "$PRD" | grep -oE "$id_req"; }

# Coverage-map entries whose epic is at or below $1.
#
# Two shapes, and the profile decides which by defining `map_line` or the two
# column names. A flat list is one line per requirement, and the profile's
# pattern captures the identifier and the epic number off that line. A table is
# located by its header, and the two columns are resolved from that header by
# name, so re-ordering them does not break this.
#
# The flat reader runs through sed rather than awk because the pattern carries
# two capture groups and POSIX awk has no way to read one. Which is also why
# the pattern is a whole-line one: sed substitutes what it matched, so a
# pattern that stops at the epic number would leave the rest of the line
# standing in the output.
map_upto() {
    if [ -n "$map_line" ]; then
        sed -nE "s/$map_line/\\1$TAB\\2/p" "$MAP" \
            | awk -F"$TAB" -v max="$1" '$2 + 0 <= max { print $1 }'
        return
    fi
    awk -F'|' -v max="$1" -v rc="$map_col_req" -v ec="$map_col_epic" -v idre="$id_req" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        !ri && $0 ~ ("\\| *" rc " *\\|") {
            for (i = 2; i < NF; i++) {
                if (trim($i) == rc) ri = i
                if (trim($i) == ec) ei = i
            }
            next
        }
        ri && ei && $0 ~ ("^\\| *(" idre ") *\\|") {
            # The first digit run in the cell, rather than the cell coerced to
            # a number. A cell reading "Epic 2", or "Epic 1: Platform", coerces
            # to zero, and zero is at or below every bound, so every row would
            # read as in range and the map would parse clean and wrong.
            cell = trim($ei)
            if (match(cell, /[0-9]+/)) {
                if (substr(cell, RSTART, RLENGTH) + 0 <= max) print trim($ri)
            }
        }
    ' "$MAP"
}

# ---------------------------------------------------------------------------
# The bounded table
#
# A table enumerating how each of a set of requirements is discharged. Its row
# count is mechanical. The count of distinct requirements it reaches rests on a
# judgment, so it is bracketed rather than derived, and the derivation below
# forces that judgment to stay total rather than letting an unclassified clause
# pass. Every column name and every key belongs to the profile, which also
# names the role whose document this reads; a profile leaving `bounded_table`
# empty turns the whole facility off.
# ---------------------------------------------------------------------------

bt_doc() { role_docs "$bounded_table" | head -1; }

# bt_cells -- the identifier column of every data row, one cell per line.
# The header is re-located inside the file by column name, on map_upto's
# pattern, because a document may carry a second table opening on the same
# column and only the second named column tells the two apart. Reading the
# columns by name also survives their re-ordering.
bt_cells() {
    local f; f="$(bt_doc)"
    [ -n "$f" ] || return 0
    awk -F'|' -v idc="$bt_col_id" -v keyc="$bt_col_key" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        !seen && $0 ~ ("^\\| *" idc " *\\|") {
            ri = 0; ti = 0
            for (i = 2; i < NF; i++) {
                if (trim($i) == idc)        ri = i
                if (index(trim($i), keyc))  ti = i
            }
            if (ri && ti) seen = 1
            next
        }
        seen && /^\|[ \t]*-+/ { next }
        seen && /^\|/ { print trim($ri); next }
        seen { exit }
    ' "$f"
}

# bt_ids -- every identifier the column names, tagged by where it sits in its
# cell. A cell opens with the requirements the row is about, written as a bare
# list, and any identifier past that opening arrived inside a clause.
# Consuming the opening list is what separates the two, so a separator is taken
# only when an identifier follows it. The separators are English list
# punctuation rather than anything this corpus chose.
bt_ids() {
    bt_cells | awk -v idre="$bt_id" '
        {
            s = $0
            while (match(s, "^" idre)) {
                head[substr(s, 1, RLENGTH)] = 1
                s = substr(s, RLENGTH + 1)
                if (!match(s, "^(, and | and |, )" idre)) break
                sub(/^(, and | and |, )/, "", s)
            }
            while (match(s, idre)) {
                emb[substr(s, RSTART, RLENGTH)] = 1
                s = substr(s, RSTART + RLENGTH)
            }
        }
        END {
            for (k in head) print "head " k
            for (k in emb) if (!(k in head)) print "clause " k
        }
    ' | sort
}

# bt_counts -- what the table derives outright. The row count and nothing else,
# because the requirement count turns on a reading of the prose.
bt_counts() {
    [ -n "$bounded_table" ] && [ -n "$(bt_doc)" ] || return 0
    printf '%s=%s\n' "$bt_key_rows" "$(bt_cells | grep -c .)"
}

# bt_bounds -- what the table brackets but does not derive.
#
# A cell opens with the requirements its row is about, then may reach a further
# identifier inside a clause. Whether that one is a second subject of the row or
# scenery explaining the first is a reading of the row's own prose, and that
# prose carries no mechanical proxy for the reading: a row may discharge a
# requirement through the name of its obligation rather than through the
# identifier, so an identifier the prose never spells can still be a subject. A
# probe deciding this from the text is wrong on such a row, and wrong with the
# confidence it brings to every other row, so none decides it.
#
# Both bounds are mechanical, and naming the clause identifiers turns a recount
# into a reading of that many cells rather than of the whole table.
bt_bounds() {
    local ids head clause n
    [ -n "$bounded_table" ] && [ -n "$(bt_doc)" ] || return 0
    ids="$(bt_ids)"
    head="$(printf '%s\n' "$ids" | awk '$1 == "head" { print $2 }' | grep -c .)"
    clause="$(printf '%s\n' "$ids" | awk '$1 == "clause" { print $2 }' | oneline)"
    n="$(printf '%s\n' "$ids" | awk '$1 == "clause" { print $2 }' | grep -c .)"
    printf '%s\t%s\t%s\t%s: %s\n' \
        "$bt_key_ids" "$head" "$((head + n))" "$bt_note" "$clause"
}

# ---------------------------------------------------------------------------
# Declared counters
#
# A document that states a register's size in its own frontmatter duplicates a
# fact the corpus already holds, and the copy drifts the moment the register
# moves. These two produce "parent.child=N" lines from each side so the copies
# can be diffed against the originals.
# ---------------------------------------------------------------------------

# declared_counters <file> -- the numeric leaves of every counter block in the
# frontmatter. A non-numeric value is not a count and is skipped, which leaves
# prose settings such as `decisions` alone.
declared_counters() {
    awk '
        NR == 1 && $0 == "---" { fm = 1; next }
        !fm { exit }
        $0 == "---" { exit }
        /^[A-Za-z][A-Za-z0-9_]*:[ \t]*$/ { parent = $1; sub(/:$/, "", parent); next }
        /^[A-Za-z][A-Za-z0-9_]*:/        { parent = ""; next }
        parent != "" && $1 ~ /^[A-Za-z][A-Za-z0-9_]*:$/ && $2 ~ /^[0-9]+$/ {
            k = $1; sub(/:$/, "", k); print parent "." k "=" $2
        }
    ' "$1"
}

# inline_counters <file> -- "line|key|value" for every count the file asserts in
# a sentence. The scope pattern selects the sentence and the value pattern takes
# its digits, so a line asserting two of the keys yields both. Two assertions of
# one key that disagree both surface, since each is diffed on its own.
inline_counters() {
    local f="$1" key scope val hit ln txt num
    while IFS="$(printf '\t')" read -r key scope val; do
        [ -n "$key" ] || continue
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            ln="${hit%%:*}"
            txt="${hit#*:}"
            while IFS= read -r num; do
                [ -n "$num" ] && printf '%s|%s|%s\n' "$ln" "$key" "$num"
            done < <(printf '%s\n' "$txt" | grep -oE "$val" | grep -oE '^[0-9]+')
        done < <(grep -nE "$scope" "$f" 2>/dev/null)
    done <<< "$inline_counters_table"
}

# computed_counters -- the same keys, counted from the documents themselves,
# under the profile's `counters_table`. Every key name and every pattern below
# belongs to the corpus rather than to this script, so the table is what a
# profile writes and this is only the machinery that runs it.
#
# Tab-separated, one row per key: `key<TAB>kind<TAB>argument...`.
#
#   lines  <role> <ERE>            matching lines across the role's documents
#   docs   <role>                  how many documents the role resolved to
#   maxnum <role|*> <ERE>          the highest integer any match holds, over
#                                  the role's documents or over every candidate
#   minus  <keyA> <keyB>           one key less another, both already computed
#   perdoc <role> <idERE> <ERE>    per document of the role: the key's `{n}`
#                                  becomes the digits of the first idERE match,
#                                  the value counts the ERE's lines
#
# `minus` reads the rows above it, so a table states its operands first.
#
# A key derived from a role the corpus does not carry is left unsaid rather
# than printed as zero. `stale` reports an unreachable key UNCHECKED, and a
# zero would instead contradict every declaration of it, which is a STALE
# verdict on an absence.
computed_counters() {
    local out key kind a1 a2 a3 docs f n sum id
    build_candidates
    out="$TMP/computed.raw"
    : > "$out"
    while IFS="$TAB" read -r key kind a1 a2 a3; do
        [ -n "$key" ] || continue
        case "$kind" in
            lines)
                docs="$(role_docs "$a1")"
                [ -n "$docs" ] || continue
                sum=0
                while IFS= read -r f; do
                    [ -n "$f" ] || continue
                    n="$(grep -cE "$a2" "$f" 2>/dev/null)" || n=0
                    sum=$((sum + n))
                done <<EOF
$docs
EOF
                printf '%s=%s\n' "$key" "$sum" >> "$out"
                ;;
            docs)
                printf '%s=%s\n' "$key" "$(role_docs "$a1" | grep -c .)" >> "$out"
                ;;
            maxnum)
                # Over the candidates rather than the whole tree: a report
                # enumerating what it found would otherwise raise the ceiling.
                if [ "$a1" = '*' ]; then docs="$(cat "$CANDF")"; else docs="$(role_docs "$a1")"; fi
                [ -n "$docs" ] || continue
                n="$(printf '%s\n' "$docs" | tr '\n' '\0' \
                     | xargs -0 grep -ohE "$a2" 2>/dev/null \
                     | grep -oE '[0-9]+' | sort -n | tail -1)"
                printf '%s=%s\n' "$key" "${n:-0}" >> "$out"
                ;;
            minus)
                local va vb
                va="$(awk -F= -v k="$a1" '$1 == k { print $2 }' "$out")"
                vb="$(awk -F= -v k="$a2" '$1 == k { print $2 }' "$out")"
                [ -n "$va" ] && [ -n "$vb" ] && printf '%s=%s\n' "$key" "$((va - vb))" >> "$out"
                ;;
            perdoc)
                docs="$(role_docs "$a1")"
                [ -n "$docs" ] || continue
                while IFS= read -r f; do
                    [ -n "$f" ] || continue
                    id="$(grep -ohE "$a2" "$f" 2>/dev/null | grep -oE '[0-9]+' | head -1)"
                    [ -n "$id" ] || continue
                    n="$(grep -cE "$a3" "$f" 2>/dev/null)" || n=0
                    printf '%s=%s\n' "${key/\{n\}/$id}" "$n" >> "$out"
                done <<EOF
$docs
EOF
                ;;
            *)  die "profile '$RQ_PROFILE_PATH': counters_table key '$key' has kind '$kind', which is not lines, docs, maxnum, minus or perdoc." ;;
        esac
    done <<EOF
$counters_table
EOF
    cat "$out"
    bt_counts
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

# or_unresolved <path> <role> -- the path, or why there is none. A required
# role that resolved to nothing is (UNRESOLVED), a defect this run survived
# only because `doctor` is the command that reports defects. An optional one is
# (none), which is a corpus that does not carry the document.
or_unresolved() {
    local req
    if [ -n "$1" ]; then rel "$1"; printf '\n'; return; fi
    req="$(printf '%s\n' "$RQ_ROLES" | awk -F"$TAB" -v r="$2" '$1 == r { print $3; exit }')"
    if [ "$req" = optional ]; then printf '(none)\n'; else printf '(UNRESOLVED)\n'; fi
}

cmd_doctor() {
    RQ_SOFT=1
    discover
    echo "## doctor"
    printf 'artifacts   %s\n' "$RQ_ARTIFACTS"
    if [ -n "$ROOT" ]; then
        printf 'root        %s (git)\n' "$ROOT"
    else
        printf 'root        (none) -- git names no repository above the working directory, so RQ_ARTIFACTS names the tree and no repository profile is read\n'
    fi
    selfcheck
    printf 'reqflow     %s (%s, output shapes verified)\n' "$RQ" "$RQ_VERSION"
    # The profile decides every probe below, so which one loaded is read on the
    # same terms as which document each role resolved to: named, with where it
    # came from, before any check is believed.
    printf 'profile     %s (%s)\n' "$RQ_PROFILE_PATH" "$RQ_PROFILE_FROM"
    # Every file the chain loaded, in load order, so an extending profile is
    # read as loudly as a standalone one.
    local base
    while IFS= read -r base; do
        [ -n "$base" ] && [ "$base" != "$RQ_PROFILE_PATH" ] && printf 'extends     %s\n' "$base"
    done <<< "$(printf '%s' "$RQ_PROFILE_CHAIN" | tr "$TAB" '\n')"
    [ -f "${RQ_PROFILE_PATH%.sh}.md" ] && printf 'namespaces  %s\n' "${RQ_PROFILE_PATH%.sh}.md"

    # One line per role the profile declares, named as the profile names it.
    # Hard-coding a label per role here would put the role vocabulary back in
    # the engine, and would print (UNRESOLVED) for a role no profile declares.
    local role mode
    while IFS="$TAB" read -r role mode _ _; do
        [ -n "$role" ] || continue
        if [ "$mode" = set ] && [ -n "$(role_docs "$role")" ]; then
            printf '%-11s %s\n' "$role" "$(role_docs "$role" | sed "s|$RQ_ARTIFACTS/||" | oneline)"
        elif [ "$role" = map ] && [ -n "$MAP" ]; then
            # The entry count, not just the path. A probe locating the map and
            # a reader parsing it are separate things, and only the first fails
            # loudly: a header probe resolves a document whose rows the reader
            # then takes none of, and `verify` reports SKIP where it would have
            # reported a diff. An author pointing this at a new corpus reads
            # this number against the map they can see.
            printf '%-11s %s (%s entries parsed)\n' "$role" "$(rel "$MAP")" \
                "$(map_upto 999999999 | grep -c .)"
        elif [ "$role" = "$bounded_table" ] && [ -n "$(bt_doc)" ]; then
            printf '%-11s %s (rows=%s, %s %s..%s)\n' "$role" "$(rel "$(bt_doc)")" \
                "$(bt_cells | grep -c .)" "${bt_key_ids##*.}" \
                "$(bt_bounds | cut -f2)" "$(bt_bounds | cut -f3)"
        else
            printf '%-11s %s\n' "$role" "$(or_unresolved "$(role_docs "$role" | head -1)" "$role")"
        fi
    done <<EOF
$RQ_ROLES
EOF
    [ -n "$EPICS" ] && printf 'stories to  %s\n' "$(written_through)"

    # Every candidate each single-best role ranked, not just its winner. The
    # ambiguity message tells the reader to run doctor, so doctor is where the
    # runner-up has to be named.
    echo
    echo "## candidates per role"
    # Every role, set-valued ones included. The resolved line above names a set
    # role's winners but not how many matches each carries, and a probe
    # matching far more of a document than its author expected is the thing an
    # author writing a new profile is looking for.
    local role mode pat
    while IFS="$TAB" read -r role mode _ _; do
        [ -n "$role" ] || continue
        eval "pat=\"\$probe_$role\""
        rank_by_probe "$pat" | while IFS="$TAB" read -r n f; do
            printf '%-11s %4s  %s\n' "$role" "$n" "$(rel "$f")"
        done
    done <<EOF
$RQ_ROLES
EOF

    # What never reached the ranking, and why. A filter that removes the wrong
    # document produces exactly the silence this section breaks.
    echo
    echo "## filtered out of discovery"
    build_candidates
    if [ -s "$DROPF" ]; then
        while IFS="$TAB" read -r why f; do
            [ -n "$f" ] || continue
            printf '%-8s %s\n' "$why" "$(rel "$f")"
        done < "$DROPF"
    else
        echo "(nothing)"
    fi
}

cmd_emit() {
    gen_configs
    case "${1:-decl}" in
        decl)  cat "$DECL" ;;
        story) cat "$STORY" ;;
        arch)  cat "$ARCH" ;;
        *) die "emit takes 'decl', 'story' or 'arch'" ;;
    esac
}

cmd_counts() {
    gen_configs
    echo "## register counts"
    "$RQ" stat -s -c "$STORY" 2>/dev/null | awk '
        /^(PRD|AR|DC) / {
            for (i = 1; i <= NF; i++)
                if ($i == "/") { print $1 "=" $(i + 1); break }
        }'
    [ -n "$ADRDOCS" ] && "$RQ" stat -s -c "$ARCH" 2>/dev/null | awk '
        /^Total / { for (i = 1; i <= NF; i++) if ($i == "/") { print "ADR=" $(i + 1); break } }'
    have_role ar || true
    have_role dc || true
    have_role adr || true
}

# check_counter <where> <key> <declared> -- one verdict line, or none when the
# declaration matches. Returns 1 only for a declaration the corpus contradicts,
# so a bracketed figure inside its bounds is advisory rather than a defect.
# CMPF and BNDF are the derived and the bracketed tables, set by cmd_stale.
check_counter() {
    local where="$1" k="$2" dv="$3" cv b lo hi note
    cv="$(awk -F= -v k="$k" '$1 == k { print $2 }' "$CMPF")"
    if [ -n "$cv" ]; then
        [ "$dv" = "$cv" ] && return 0
        printf 'STALE %s %s: declares %s, corpus has %s\n' "$where" "$k" "$dv" "$cv"
        return 1
    fi

    b="$(awk -F'\t' -v k="$k" '$1 == k { print; exit }' "$BNDF")"
    if [ -z "$b" ]; then
        printf 'UNCHECKED %s %s: no probe derives it\n' "$where" "$k"
        return 0
    fi
    lo="$(printf '%s' "$b" | cut -f2)"
    hi="$(printf '%s' "$b" | cut -f3)"
    note="$(printf '%s' "$b" | cut -f4)"
    if [ "$dv" -lt "$lo" ] || [ "$dv" -gt "$hi" ]; then
        printf 'STALE %s %s: declares %s, corpus admits %s..%s\n' \
            "$where" "$k" "$dv" "$lo" "$hi"
        return 1
    fi
    printf 'RECOUNT %s %s: declares %s, corpus admits %s..%s, %s\n' \
        "$where" "$k" "$dv" "$lo" "$hi" "$note"
    return 0
}

cmd_stale() {
    discover
    echo "## stale declared counters"
    local docs t k f ln dv n checked
    # The keys these registers derive go unchecked without them, so naming the
    # missing document is the difference between "no probe derives it" and "no
    # probe could". Every optional role is named, because which of them a
    # counter needed is the profile's business rather than this script's.
    local r rq
    while IFS="$TAB" read -r r _ rq _; do
        [ -n "$r" ] && [ "$rq" = optional ] && { have_role "$r" || true; }
    done <<EOF
$RQ_ROLES
EOF

    t="$TMP/stale"; mkdir -p "$t" || die "cannot create temp dir"
    CMPF="$t/computed"; BNDF="$t/bounded"
    computed_counters | sort > "$CMPF"
    bt_bounds > "$BNDF"
    { cut -d= -f1 "$CMPF"; cut -f1 "$BNDF"; } | sort -u > "$t/ck"

    n=0
    checked=0

    # Frontmatter blocks, wherever they sit.
    docs="$(rank_by_probe "$probe_idx" | cut -f2 | sort)"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        declared_counters "$f" | sort > "$t/declared"
        cut -d= -f1 "$t/declared" | sort > "$t/dk"
        # A document whose counters this harness cannot reach at all is not
        # evidence of anything, so it is passed over rather than reported as
        # unchecked line by line.
        comm -12 "$t/dk" "$t/ck" | grep -q . || continue
        checked=$((checked + 1))
        while IFS='=' read -r k dv; do
            [ -n "$k" ] || continue
            check_counter "${f#"$RQ_ARTIFACTS"/}" "$k" "$dv" || n=$((n + 1))
        done < "$t/declared"
    done <<< "$docs"

    # Sentences, in the registers only. Every assertion carries its line, since
    # a prose copy has no key to name it by.
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        inline_counters "$f" > "$t/inline"
        [ -s "$t/inline" ] || continue
        checked=$((checked + 1))
        while IFS='|' read -r ln k dv; do
            [ -n "$k" ] || continue
            check_counter "${f#"$RQ_ARTIFACTS"/}:$ln" "$k" "$dv" || n=$((n + 1))
        done < "$t/inline"
    done <<< "$(registers | sort -u)"

    if [ "$checked" -eq 0 ]; then
        echo "ok: nothing declares a counter this harness derives"
    elif [ "$n" -eq 0 ]; then
        printf 'ok: every derivable counter matches, across %s document(s)\n' "$checked"
    fi
    rm -rf "$t"
}

cmd_partition() {
    gen_configs
    echo "## partition (a requirement declared by two epics)"
    "$RQ" trac -c "$DECL" -x csv 2>/dev/null | awk -F, '
        NF >= 2 && $2 != "" { c[$1]++ }
        END {
            n = 0
            for (r in c) if (c[r] > 1) { print "DOUBLE " r " x" c[r]; n++ }
            if (n == 0) print "ok: no requirement declared by more than one epic"
        }'
}

cmd_verify() {
    gen_configs
    local wt; wt="$(written_through)"
    echo "## verify (declared coverage vs coverage map, epics 1-$wt)"
    local t; t="$TMP/verify"; mkdir -p "$t"
    all_reqs | sort -u > "$t/all"
    uncovered "$DECL" | grep -E "^($id_req)" | sort -u > "$t/uncov"
    comm -23 "$t/all" "$t/uncov" > "$t/reqflow"
    map_upto "$wt" | sort -u > "$t/map"
    if [ ! -s "$t/map" ]; then
        echo "SKIP: no coverage-map rows parsed from ${MAP#"$RQ_ARTIFACTS"/}"
    elif diff -q "$t/reqflow" "$t/map" >/dev/null; then
        local n; n="$(wc -l < "$t/map" | tr -d ' ')"
        echo "ok: exact match, $n/$n"
    else
        comm -23 "$t/reqflow" "$t/map" | sed 's/^/EPIC-CLAIMS-NOT-IN-MAP /'
        comm -13 "$t/reqflow" "$t/map" | sed 's/^/MAP-CLAIMS-NOT-IN-EPIC /'
    fi
    rm -rf "$t"
}

cmd_orphans() {
    gen_configs
    echo "## orphans (declared by no epic 1-$(written_through); expect the later-epic set)"
    uncovered "$DECL" | grep -E "^($id_req)" | oneline
}

# Two strings below name namespaces rather than roles, and a corpus spelling
# its identifiers differently reads a heading that does not describe it: this
# one, and the "ADR=" label `counts` prints for the architecture graph's total.
# Both are output rather than matching, so neither can produce a wrong answer,
# and both are the last of the vocabulary the engine still carries.
cmd_uncited() {
    gen_configs
    echo "## uncited decisions (AR/DC no story cites, ADR no AR rests on)"
    have_role ar || true
    have_role dc || true
    have_role adr || true
    [ -n "$ARREG$DCREG" ] && uncovered "$STORY" | grep -E "^($id_dec)" | oneline
    # The AR register is what bridges a decision into the story graph. Reading
    # the architecture graph without it would report every decision uncited,
    # which is the shape of a complete answer and the content of none.
    [ -n "$ARREG" ] && [ -n "$ADRDOCS" ] && uncovered "$ARCH" | grep -E "$id_arch" | oneline
    return 0
}

cmd_dangling() {
    gen_configs
    echo "## dangling citations"
    local err out
    err="$("$RQ" stat -s -c "$STORY" 2>&1 >/dev/null)"
    # Two distinct reqflow diagnostics, and only the first is a real defect:
    #   "Undefined requirement, referenced by: X"  an id declared nowhere
    #   "Reference without requirement"            a citation with no enclosing
    #                                              heading, i.e. a config gap
    out="$(printf '%s\n' "$err" | awk -F: '
        /Undefined requirement/ { print "UNDEFINED " $2 " cited by" $4 }
        /Reference without requirement/ { print "UNATTRIBUTED " $2 " in " $1 }
    ' | sort -u)"
    if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "ok: none"; fi
}

cmd_impact() {
    [ $# -ge 1 ] || die "usage: rqcheck.sh impact <ID>   a requirement or decision identifier, as the profile's namespaces spell one"
    gen_configs
    echo "## impact: $1 (what cites it)"
    # Without the bridge register the architecture graph carries declarations
    # and no citations, so "nothing cites ADR-N" would mean "nothing could".
    have_role ar || true
    local out
    out="$({ "$RQ" trac -c "$STORY" -x csv 2>/dev/null
             [ -n "$ADRDOCS" ] && "$RQ" trac -c "$ARCH" -x csv 2>/dev/null; } \
           | awk -F, -v id="$1" '$1 == id && $2 != "" { print $2 }' | oneline)"
    if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "(nothing cites $1)"; fi
}

cmd_report() {
    gen_configs
    # The repository root when there is one, otherwise the working directory.
    local out="${1:-${ROOT:-$PWD}/rqcheck-report.html}"
    "$RQ" trac -c "$STORY" -x html -o "$out" 2>/dev/null || die "report generation failed"
    echo "## report -> $out"
}

case "${1:-all}" in
    counts)    cmd_counts ;;
    stale)     cmd_stale ;;
    partition) cmd_partition ;;
    verify)    cmd_verify ;;
    orphans)   cmd_orphans ;;
    uncited)   cmd_uncited ;;
    dangling)  cmd_dangling ;;
    doctor)    cmd_doctor ;;
    emit)      shift; cmd_emit "$@" ;;
    impact)    shift; cmd_impact "$@" ;;
    report)    shift; cmd_report "$@" ;;
    all)
        cmd_counts; echo
        cmd_stale; echo
        cmd_partition; echo
        cmd_verify; echo
        cmd_orphans; echo
        cmd_uncited; echo
        cmd_dangling ;;
    # Reached only if this list and the one at the head of the file disagree.
    *) die "'$1' passed the command-line check at the head of this file and no branch here runs it." ;;
esac
