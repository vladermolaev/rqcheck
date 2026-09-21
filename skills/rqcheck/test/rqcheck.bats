#!/usr/bin/env bats
# Unit tests for rqcheck.sh.
#
# Two corpora under two vocabularies, so the profile boundary is exercised
# rather than asserted. The generic corpus under fixtures/generic/ writes its
# requirements in the plain form BMAD's PRD template emits, keys its declared
# counters under names nothing in the engine knows, keeps its coverage map as a
# table and carries no bounded table; it is read under
# fixtures/generic-profile.sh, which extends nothing. The stock corpus under
# fixtures/stock/ is shaped as BMAD's own templates emit one -- one epics
# document holding the coverage map, the epic index and every epic body, the
# map a flat list rather than a table, and no numbered decision anywhere; it is
# read under profiles/bmad-stock.sh, which extends the default. A check that
# passes on one corpus and not the other is reading a convention from the
# script rather than from a profile, which is the drift these cases exist to
# name.
#
# A consuming repository's own corpus is not read here. A published suite that
# needed one would pass only where one was checked out, and the repositories
# that carry such a tree keep those cases beside it.
#
# The generic corpus declares no bounded table and no `thr` role. Every check
# that would read one must carry on, because a facility no profile turns on
# must not be able to take the run down, and a check that silently narrows its
# answer is worse than one that errors.
#
# reqflow is not vendored. Where it is absent every case below skips rather
# than fails, so a checkout without it reports honestly instead of red.
#
# The scenarios named "discovery filter" build their corpus by copying the
# fixture and mutating the copy, never the fixture itself.

# `run --separate-stderr` throughout, so a case can assert an empty stderr.
# Without it bats folds stderr into $output, $stderr is never set, and every
# such assertion passes on a variable nothing wrote.
bats_require_minimum_version 1.5.0

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHECK="$SKILL_DIR/rqcheck.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  GENERIC="$FIXTURES/generic"
  GENERIC_PROFILE="$FIXTURES/generic-profile.sh"
  STOCK="$FIXTURES/stock"
  DEFAULT_PROFILE="$SKILL_DIR/profiles/default.sh"
  STOCK_PROFILE="$SKILL_DIR/profiles/bmad-stock.sh"
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/rqcheck.XXXXXX")"

  # REQFLOW then PATH, which is the whole of the search rqcheck.sh runs, so a
  # case skips for the reason the script would have died for rather than
  # failing on its message.
  if [ -n "${REQFLOW:-}" ] && [ -x "${REQFLOW:-}" ]; then
    :
  elif command -v reqflow >/dev/null 2>&1; then
    REQFLOW="$(command -v reqflow)"
  else
    REQFLOW=''
  fi
  export REQFLOW
}

teardown() {
  [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

need_reqflow() {
  [ -n "$REQFLOW" ] || skip "reqflow not built; see github.com/goeb/reqflow or set REQFLOW"
}

# Run a subcommand against the generic corpus under the minimal profile.
generic() {
  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" "$@"
}

# Run a subcommand against the stock-shaped corpus under the stock profile.
stock() {
  RQ_PROFILE="$STOCK_PROFILE" RQ_ARTIFACTS="$STOCK" run --separate-stderr "$CHECK" "$@"
}

# A writable copy of the generic corpus, for the cases that mutate one.
generic_copy() {
  local dest="$WORK/corpus"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$GENERIC/." "$dest/"
  echo "$dest"
}

# Assert a clean run: exit 0 and nothing on stderr. Both halves matter — a
# reqflow parse this script abandons is reported on stderr while the check it
# fed still exits 0 with a confident, partial answer.
assert_clean() {
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

# ── The generic corpus: every check runs under a profile that is not the default ──

@test "generic: counts reports every register the corpus carries" {
  need_reqflow
  generic counts
  assert_clean
  [[ "$output" == *"PRD=4"* ]]
  [[ "$output" == *"AR=1"* ]]
  [[ "$output" == *"DC=1"* ]]
  [[ "$output" == *"ADR=2"* ]]
  [[ "$output" != *"SKIPPED"* ]]
}

@test "generic: verify diffs the epic files against the coverage map" {
  need_reqflow
  generic verify
  assert_clean
  [[ "$output" == *"ok: exact match, 3/3"* ]]
}

@test "generic: orphans names the requirement no written epic declares" {
  need_reqflow
  generic orphans
  assert_clean
  [[ "$output" == *"FR3"* ]]
  [[ "$output" != *"FR1"* ]]
  [[ "$output" != *"FR2"* ]]
}

@test "generic: partition finds no requirement declared twice" {
  need_reqflow
  generic partition
  assert_clean
  [[ "$output" == *"ok: no requirement declared by more than one epic"* ]]
}

@test "generic: uncited names the constraint and the decision nothing rests on" {
  need_reqflow
  generic uncited
  assert_clean
  [[ "$output" == *"DC1"* ]]
  [[ "$output" == *"ADR-2"* ]]
  # AR1 is cited by story 1.1, and ADR-1 by AR1 through the bridge.
  [[ "$output" != *"AR1"* ]]
  [[ "$output" != *"ADR-1"* ]]
}

@test "generic: dangling reports none" {
  need_reqflow
  generic dangling
  assert_clean
  [[ "$output" == *"ok: none"* ]]
}

@test "generic: stale checks the frontmatter counters and matches" {
  need_reqflow
  generic stale
  assert_clean
  [[ "$output" == *"ok: every derivable counter matches"* ]]
  [[ "$output" != *"STALE"* ]]
}

@test "generic: the counter key namespace is the profile's, not the engine's" {
  need_reqflow
  # Nothing in rqcheck.sh names registerTotals, epicTally or storyTally. They
  # reach `stale` only because the profile's counters_table derives them, and
  # the keys this repository's own corpus uses appear nowhere in this run.
  generic stale
  assert_clean
  [[ "$output" != *"requirementCounts"* ]]
  [[ "$output" != *"phaseDistribution"* ]]

  # Renaming a declared counter takes it out of reach of every probe, and the
  # verdict is UNCHECKED rather than a silent pass.
  local corpus; corpus="$(generic_copy)"
  sed 's/^registerTotals:/registerTally:/' "$GENERIC/epics/index.md" > "$corpus/epics/index.md"
  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" stale
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCHECKED"*"registerTally.fr"* ]]
}

@test "generic: every counter kind the driver carries is exercised" {
  need_reqflow
  # lines, docs, maxnum, minus and perdoc all feed one document's declarations,
  # so a driver that mis-ran any of the five would report STALE here.
  generic doctor
  assert_clean
  generic stale
  assert_clean
  [[ "$output" == *"across 2 document(s)"* ]]
  [[ "$output" != *"STALE"* ]]
  [[ "$output" != *"UNCHECKED"* ]]
}

@test "generic: impact reports what cites a requirement" {
  need_reqflow
  generic impact FR1
  assert_clean
  [[ "$output" == *"Story 1.1"* ]]
}

@test "generic: emit prints a config for each of the three graphs" {
  need_reqflow
  local graph
  for graph in decl story arch; do
    generic emit "$graph"
    assert_clean
    [[ "$output" == *"document "* ]]
  done
}

@test "generic: report writes the HTML matrices" {
  need_reqflow
  generic report "$WORK/trace.html"
  assert_clean
  [ -s "$WORK/trace.html" ]
}

@test "generic: all runs every check end to end" {
  need_reqflow
  generic all
  assert_clean
  [[ "$output" == *"## register counts"* ]]
  [[ "$output" == *"## dangling citations"* ]]
}

# ── Optional roles ───────────────────────────────────────────────────────────

@test "a missing optional role skips the checks reading it and takes down none" {
  need_reqflow
  # This is the defect the optional flag exists for: a role the corpus does not
  # carry must not make every check exit 1 over a document none of them reads.
  local corpus; corpus="$(generic_copy)"
  rm -f "$corpus/epics/03-additional-requirements.md"
  local cmd
  for cmd in counts stale partition verify orphans dangling; do
    RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" "$cmd"
    [ "$status" -eq 0 ]
  done
}

@test "a check reading a missing optional role says which document is absent" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  rm -f "$corpus/epics/04-decomposition-constraints.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" counts

  assert_clean
  [[ "$output" == *"SKIPPED dc: no decomposition-constraints register in this corpus"* ]]
  # SKIPPED rather than a missing line. A silently narrowed answer is a green
  # wrong answer.
  [[ "$output" != *"DC="* ]]
}

@test "a missing optional role resolves to (none) rather than (UNRESOLVED)" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  rm -f "$corpus/epics/03-additional-requirements.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" doctor

  assert_clean
  [[ "$output" == *"ar          (none)"* ]]
  [[ "$output" != *"(UNRESOLVED)"* ]]
}

@test "doctor names a role no profile declares nowhere at all" {
  need_reqflow
  # The engine prints one line per role the profile declares, so a facility
  # this profile leaves off is absent from the report rather than reported as
  # an unresolved document the corpus owes.
  generic doctor
  assert_clean
  [[ "$output" != *"thr"* ]]
  [[ "$output" != *"(UNRESOLVED)"* ]]
}

@test "the skill default reads the generic corpus, whose profile is not it" {
  need_reqflow
  # profiles/default.sh against a corpus written in the plain declaration
  # form BMAD's PRD template emits, with none of this repository's vocabulary:
  # no phase marker, no prefixed decision namespace, no counter keys it knows.
  RQ_PROFILE="$DEFAULT_PROFILE" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" verify
  assert_clean
  [[ "$output" == *"ok: exact match, 3/3"* ]]
}

@test "the skill default derives no counter, so it diffs none" {
  need_reqflow
  # No BMAD template states a count of the corpus, so the default profile's
  # counters_table is empty and a document declaring only counters it cannot
  # reach is passed over rather than reported line by line.
  RQ_PROFILE="$DEFAULT_PROFILE" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" stale
  assert_clean
  [[ "$output" == *"ok: nothing declares a counter this harness derives"* ]]
  [[ "$output" != *"UNCHECKED"* ]]
}

@test "a corpus of FR, NFR and ADR alone runs every check and skips loudly" {
  need_reqflow
  # A plain BMAD tree carries no architecture-requirement register and no
  # decomposition-constraints register. Three of the seven roles resolve to
  # nothing, and the run still answers every question that does not need them.
  local corpus; corpus="$(generic_copy)"
  rm -f "$corpus/epics/03-additional-requirements.md" \
        "$corpus/epics/04-decomposition-constraints.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" all

  assert_clean
  [[ "$output" == *"SKIPPED ar: no additional-requirements register in this corpus"* ]]
  [[ "$output" == *"SKIPPED dc: no decomposition-constraints register in this corpus"* ]]
  # The checks that need none of the three still answer in full.
  [[ "$output" == *"ok: exact match, 3/3"* ]]
  [[ "$output" == *"PRD=4"* ]]
  [[ "$output" == *"ADR=2"* ]]
  # And the one that needed them reports no decision set at all rather than
  # the whole of it.
  [[ "$output" != *"ADR-1"* ]]
  [[ "$output" != *"ADR-2"* ]]
}

@test "a missing REQUIRED role is fatal and names the probe" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  rm -f "$corpus/epics/05-coverage-map.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" verify

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"role 'map' matched no candidate"* ]]
}

@test "an optional role matching two documents is fatal, as a required one is" {
  need_reqflow
  # Absence is a corpus that does not carry the document. Two candidates is one
  # that does and cannot say which, which no amount of optionality resolves.
  local corpus; corpus="$(generic_copy)"
  cp "$corpus/epics/03-additional-requirements.md" "$corpus/epics/03-copy.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" counts

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"role 'ar' does not resolve"* ]]
}

# ── Profile resolution ───────────────────────────────────────────────────────

@test "doctor names the loaded profile and where it came from" {
  need_reqflow
  generic doctor
  assert_clean
  [[ "$output" == *"profile     $GENERIC_PROFILE (RQ_PROFILE)"* ]]
}

@test "doctor names the skill default when nothing overrides it" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  # A repository of its own, so the resolution cannot reach this one's profile.
  git -C "$WORK" init -q
  local top; top="$(git -C "$WORK" rev-parse --show-toplevel)"

  RQ_ARTIFACTS="$corpus" run --separate-stderr \
    env -u RQ_PROFILE bash -c "cd '$top' && '$CHECK' doctor"

  [ "$status" -eq 0 ]
  [[ "$output" == *"profile     $DEFAULT_PROFILE (skill default)"* ]]
  [[ "$output" == *"namespaces  ${DEFAULT_PROFILE%.sh}.md"* ]]
  [[ "$output" != *"extends"* ]]
}

@test "doctor names the artifact tree in full rather than relative to the root" {
  need_reqflow
  # Printing the tree relative to the root would strip the one part of the path
  # that can be wrong. Asserted wherever the suite runs from, since the tree is
  # named the same way with a root and without one.
  generic doctor
  assert_clean
  [[ "$output" == *"artifacts   $GENERIC"* ]]
}

@test "inside a repository the root is git's and is named as git's" {
  need_reqflow
  # A checkout of its own, so the case asserts the same thing whether the suite
  # itself was unpacked inside a repository or outside one.
  local corpus; corpus="$(generic_copy)"
  git -C "$WORK" init -q
  local top; top="$(git -C "$WORK" rev-parse --show-toplevel)"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" \
    run --separate-stderr bash -c "cd '$top' && '$CHECK' doctor"

  [ "$status" -eq 0 ]
  [[ "$output" == *"root        $top (git)"* ]]
}

@test "outside a repository the tree is named rather than guessed" {
  need_reqflow
  # The failure a guessed root produces: a skill installed once under a home
  # directory, or unpacked into a plugin cache, sits three levels below
  # something that is not a repository at all. A root derived from its own
  # location then names that, and the run reads a profile and an artifact tree
  # from a stranger's directory and reports on them. So there is no derivation
  # to guess with, and RQ_ARTIFACTS carries the whole answer.
  local away="$WORK/outside"
  mkdir -p "$away"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$GENERIC" \
    run --separate-stderr bash -c "cd '$away' && '$CHECK' doctor"

  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"root        (none)"* ]]
  [[ "$output" == *"git names no repository above the working directory"* ]]
  # And the tree it actually read, absolute, so nothing about it is inferred.
  [[ "$output" == *"artifacts   $GENERIC"* ]]
}

@test "outside a repository every check still answers" {
  need_reqflow
  # Not merely doctor: a per-user install is the case with no root, and a run
  # that reported cleanly under doctor and failed under every check would be no
  # install at all.
  local away="$WORK/outside"
  mkdir -p "$away"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$GENERIC" \
    run --separate-stderr bash -c "cd '$away' && '$CHECK' all"

  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"ok: exact match, 3/3"* ]]
}

@test "outside a repository RQ_ARTIFACTS is mandatory rather than defaulted" {
  # A profile's default artifact path is relative to a repository root. With no
  # root there is nothing to resolve it against, and the error names the one
  # variable that supplies the answer rather than reading some other tree.
  local away="$WORK/outside"
  mkdir -p "$away"

  run --separate-stderr env -u RQ_ARTIFACTS \
    bash -c "cd '$away' && RQ_PROFILE='$GENERIC_PROFILE' '$CHECK' doctor"

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"git names no repository above the working directory"* ]]
  [[ "$stderr" == *"Set RQ_ARTIFACTS"* ]]
}

@test "a repo-local .rqcheck-profile.sh outranks the skill default" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  # A repository whose root is the working directory, so the resolution reads
  # from the tree being asked about rather than from the skill's own depth.
  git -C "$WORK" init -q
  cp "$GENERIC_PROFILE" "$WORK/.rqcheck-profile.sh"
  # git resolves the symlink that puts /tmp under /private on macOS, and the
  # resolved root is what the script reports, so the expectation reads the same
  # path the same way rather than assuming mktemp handed back a real one.
  local top; top="$(git -C "$WORK" rev-parse --show-toplevel)"

  RQ_ARTIFACTS="$corpus" run --separate-stderr env -u RQ_PROFILE bash -c "cd '$WORK' && '$CHECK' doctor"

  [ "$status" -eq 0 ]
  [[ "$output" == *"profile     $top/.rqcheck-profile.sh (repo)"* ]]
}

@test "RQ_PROFILE naming no file is fatal rather than a silent fallback" {
  RQ_PROFILE="$WORK/no-such-profile.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" doctor

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"which is not a file"* ]]
}

@test "a profile omitting a pattern fails at load rather than inside a check" {
  # A pattern expanding to the empty string matches every line, so the failure
  # this refuses is a check reporting confidently on the whole corpus.
  grep -v '^req_prd=' "$GENERIC_PROFILE" > "$WORK/holed-profile.sh"

  RQ_PROFILE="$WORK/holed-profile.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" counts

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"defines no req_prd"* ]]
}

@test "a profile with several holes names them all in one pass" {
  # A profile is authored by running this script against a tree and fixing what
  # it names. Raising the first fault and stopping turns that into as many runs
  # as the profile has holes, and each run hides the next hole behind the one
  # it just named.
  # Three keys the profile assigns and nothing in it reads back, so the file
  # still sources and the validation is what speaks.
  grep -v '^req_prd=\|^probe_idx=\|^stop_epic_decl=' "$GENERIC_PROFILE" > "$WORK/holey.sh"

  RQ_PROFILE="$WORK/holey.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" counts

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is incomplete"* ]]
  [[ "$stderr" == *"defines no req_prd"* ]]
  [[ "$stderr" == *"defines no probe_idx"* ]]
  [[ "$stderr" == *"defines no stop_epic_decl"* ]]
}

@test "a profile declaring a role with no probe fails at load" {
  { cat "$GENERIC_PROFILE"; echo "rq_role extra single required"; } > "$WORK/extra-profile.sh"

  RQ_PROFILE="$WORK/extra-profile.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" counts

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"declares role 'extra' but defines no probe_extra"* ]]
}

@test "a profile declaring no ar role owes no AR pattern" {
  need_reqflow
  # A minimal profile is minimal both ways: dropping the role drops the
  # patterns that only that role's document is read with.
  local corpus; corpus="$(generic_copy)"
  rm -f "$corpus/epics/03-additional-requirements.md"
  grep -vE "^(rq_role ar |req_ar=|ref_adr=|probe_ar=)" "$GENERIC_PROFILE" \
    > "$WORK/no-ar-profile.sh"

  RQ_PROFILE="$WORK/no-ar-profile.sh" RQ_ARTIFACTS="$corpus" \
    run --separate-stderr "$CHECK" verify

  assert_clean
  [[ "$output" == *"ok: exact match, 3/3"* ]]
}

@test "a profile omitting a role the checks name directly fails at load" {
  grep -v '^rq_role map ' "$GENERIC_PROFILE" > "$WORK/no-map-profile.sh"

  RQ_PROFILE="$WORK/no-map-profile.sh" RQ_ARTIFACTS="$GENERIC" \
    run --separate-stderr "$CHECK" verify

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"declares no 'map' role"* ]]
}

@test "a profile declaring no role at all fails at load" {
  grep -v '^rq_role ' "$GENERIC_PROFILE" > "$WORK/roleless-profile.sh"

  RQ_PROFILE="$WORK/roleless-profile.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" counts

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"declares no role"* ]]
}

# ── Namespaces and the alternation order ─────────────────────────────────────

@test "a prefixed namespace cannot be swallowed by the bare one it ends with" {
  need_reqflow
  # The trap rq_alt exists to close: a bare ADR branch placed first matches
  # inside DEVOPS-ADR-7 and captures ADR-7, so one decision answers to two
  # names and neither is traceable. The profile names both and the engine
  # orders them, so an author adding a prefix never meets the trap.
  local corpus; corpus="$(generic_copy)"
  cat > "$corpus/arch-devops.md" <<'CORPUS'
# DevOps Architecture

#### DEVOPS-ADR-1 — Run the applier in a container

The applier rests on nothing in the product architecture.
CORPUS
  sed 's/^AR1: .*/AR1: The store is a relational table, resting on ADR-1 and DEVOPS-ADR-1./' \
    "$GENERIC/epics/03-additional-requirements.md" > "$corpus/epics/03-additional-requirements.md"

  {
    sed -e 's/^id_arch=.*/id_arch="$(rq_alt ADR DEVOPS-ADR)-[0-9]+"/' \
        -e 's/^req_adr=.*/req_adr="^#+ ($(rq_alt_nc ADR DEVOPS-ADR)-[0-9]+)"/' \
        -e 's/^ref_adr=.*/ref_adr="($(rq_alt_nc ADR DEVOPS-ADR)-[0-9]+)"/' \
        "$GENERIC_PROFILE"
  } > "$WORK/prefixed-profile.sh"

  RQ_PROFILE="$WORK/prefixed-profile.sh" RQ_ARTIFACTS="$corpus" \
    run --separate-stderr "$CHECK" impact DEVOPS-ADR-1

  assert_clean
  # Cited under its whole name. A swallowed prefix would have declared it as
  # ADR-1 instead, and this would report nothing citing it.
  [[ "$output" == *"AR1"* ]]

  RQ_PROFILE="$WORK/prefixed-profile.sh" RQ_ARTIFACTS="$corpus" \
    run --separate-stderr "$CHECK" dangling
  assert_clean
  [[ "$output" == *"ok: none"* ]]
}

@test "one namespace needs no alternation group at all" {
  need_reqflow
  # rq_alt with a single name emits the name, so a profile author checking a
  # pattern by eye reads ADR-[0-9]+ rather than (?:ADR)-[0-9]+.
  generic emit arch
  assert_clean
  [[ "$output" == *"(ADR-[0-9]+)"* ]]
  [[ "$output" != *"(?:ADR)"* ]]
}

# ── Extending a profile ──────────────────────────────────────────────────────

@test "an extending profile overrides the base and doctor names both files" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  cat > "$WORK/overlay-profile.sh" <<OVERLAY
rq_extend '$GENERIC_PROFILE'
rq_role ar single required
OVERLAY

  RQ_PROFILE="$WORK/overlay-profile.sh" RQ_ARTIFACTS="$corpus" \
    run --separate-stderr "$CHECK" doctor

  [ "$status" -eq 0 ]
  [[ "$output" == *"profile     $WORK/overlay-profile.sh (RQ_PROFILE)"* ]]
  [[ "$output" == *"extends     $GENERIC_PROFILE"* ]]
  # The base declared `ar` optional. Re-declaring it replaces that entry rather
  # than adding a second, so the corpus owes the document instead of being
  # allowed to skip it.
  rm -f "$corpus/epics/03-additional-requirements.md"
  RQ_PROFILE="$WORK/overlay-profile.sh" RQ_ARTIFACTS="$corpus" \
    run --separate-stderr "$CHECK" counts
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"role 'ar' matched no candidate"* ]]
}

@test "rq_extend naming no file is fatal rather than a silent fallback" {
  echo "rq_extend '$WORK/no-such-base.sh'" > "$WORK/bad-overlay.sh"

  RQ_PROFILE="$WORK/bad-overlay.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" counts

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"rq_extend names"* ]]
  [[ "$stderr" == *"which is not a file"* ]]
}

@test "a profile that extends itself is fatal rather than a hang" {
  cp "$GENERIC_PROFILE" "$WORK/loop-profile.sh"
  printf "rq_extend '%s/loop-profile.sh'\n" "$WORK" >> "$WORK/loop-profile.sh"

  RQ_PROFILE="$WORK/loop-profile.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" counts

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"loops back to"* ]]
}

# ── What a profile owes ──────────────────────────────────────────────────────

@test "a profile emptying an identifier pattern fails at load" {
  # The same reasoning as a missing reqflow pattern: an empty id_req makes
  # every grep that filters by it match every line, so the check would report
  # confidently on the whole corpus.
  { cat "$GENERIC_PROFILE"; echo "id_req=''"; } > "$WORK/no-idreq.sh"

  RQ_PROFILE="$WORK/no-idreq.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" verify

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"defines no id_req"* ]]
}

@test "a profile leaving a counter table undefined fails at load" {
  # Empty is an answer -- this corpus declares no counters. Undefined is a
  # profile that never asked, and the two must not read alike.
  grep -v '^counters_table=' "$GENERIC_PROFILE" | grep -v '^registerTotals\|^epicTally\|^storyTally' \
    > "$WORK/no-counters.sh"

  RQ_PROFILE="$WORK/no-counters.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" stale

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"defines no counters_table"* ]]
}

@test "a counter row naming an unknown kind fails rather than counting nothing" {
  need_reqflow
  { grep -v '^counters_table=' "$GENERIC_PROFILE" \
      | grep -v '^registerTotals\|^epicTally\|^storyTally'
    printf "counters_table='registerTotals.fr\ttally\tprd\t^- FR[0-9]+:'\n"
  } > "$WORK/bad-kind.sh"

  # Any subcommand, because the row is read when the profile loads rather than
  # when a check runs: `computed_counters` runs inside a pipeline, and a die
  # there would exit the subshell and leave `stale` reporting on the rows it
  # had already read.
  RQ_PROFILE="$WORK/bad-kind.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" counts

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"has kind 'tally'"* ]]
}

@test "a profile naming a bounded table owes every name the facility reads" {
  { cat "$GENERIC_PROFILE"; echo "bounded_table='thr'"; } > "$WORK/bt-noroles.sh"

  RQ_PROFILE="$WORK/bt-noroles.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" stale

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"bounded_table to 'thr' but declares no such role"* ]]
}

# ── A corpus that adopted no identifier discipline ───────────────────────────

@test "a stock-shaped BMAD tree fails loudly instead of answering thinly" {
  need_reqflow
  # Stock BMAD numbers functional requirements and nothing else: no coverage
  # table, no numbered decisions. The default profile must refuse such a tree
  # on the role it cannot find rather than report on the sliver it can read,
  # because a thin green answer is the failure this skill exists to prevent.
  local corpus="$WORK/stock"
  mkdir -p "$corpus"
  cat > "$corpus/prd.md" <<'CORPUS'
---
stepsCompleted: []
inputDocuments: []
workflowType: 'prd'
---

# Product Requirements Document

## Functional Requirements

- FR1: An operator can record a submission.
- FR2: An operator can list the recorded submissions.
CORPUS
  cat > "$corpus/epics.md" <<'CORPUS'
---
stepsCompleted: []
inputDocuments: []
---

# Epic Breakdown

### FR Coverage Map

FR1: Epic 1 - the store records one submission
FR2: Epic 1 - the list reads the store

## Epic 1: Record and list submissions

Operators record and read back what they recorded.

### Story 1.1: Record a submission

As an operator, I record a submission so that it is retained.
CORPUS

  RQ_PROFILE="$DEFAULT_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" verify

  [ "$status" -eq 1 ]
  # The coverage map is the first thing a stock tree does not carry as a table.
  [[ "$stderr" == *"role 'map' matched no candidate"* ]]
}

@test "a tree with no numbered decisions still answers every other question" {
  need_reqflow
  # The other half of the same finding: stock BMAD writes its decisions as
  # unnumbered prose, so the default declares `adr` optional and a tree without
  # one loses the decision half of `uncited` and nothing else.
  local corpus; corpus="$(generic_copy)"
  rm -f "$corpus/arch.md"

  RQ_PROFILE="$DEFAULT_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" all

  assert_clean
  [[ "$output" == *"SKIPPED adr: no numbered architecture decisions in this corpus"* ]]
  [[ "$output" == *"ok: exact match, 3/3"* ]]
  # The bridge register still cites ADR-1. With nothing on the far side of the
  # bridge the graph is left unbuilt rather than reporting that citation
  # undefined, which would be a defect in the reading rather than the corpus.
  [[ "$output" != *"ADR-1"* ]]
  [[ "$output" != *"ADR-2"* ]]
}

# ── A flat coverage map, and the tree BMAD's own templates emit ──────────────

@test "stock: a flat coverage map answers every check the corpus can answer" {
  need_reqflow
  # The tree BMAD writes with nothing added: one epics document holding the
  # coverage map, the epic index and every epic body, the map a flat list of
  # one line per requirement, and no numbered decision anywhere. Everything
  # that needs a register this corpus lacks says SKIPPED, and everything else
  # answers.
  stock all

  assert_clean
  [[ "$output" == *"ok: exact match, 3/3"* ]]
  [[ "$output" == *"ok: no requirement declared by more than one epic"* ]]
  [[ "$output" == *"ok: none"* ]]
  [[ "$output" == *"SKIPPED adr: no numbered architecture decisions in this corpus"* ]]
}

@test "stock: the flat reader restricts the map by the epic number it captures" {
  need_reqflow
  # Capture 2 is the epic number, and `verify` compares only the rows at or
  # below the highest written epic. A reader that lost the number would admit
  # every row, which reads as an exact match on a corpus where a later epic is
  # unwritten -- the one wrong answer this check exists to give.
  local corpus="$WORK/stock-partial"
  cp -R "$STOCK" "$corpus"
  # Epic 2 becomes a coverage-map row with no body, as an unwritten epic is.
  awk '/^## Epic 2: /{ exit } { print }' "$STOCK/epics.md" > "$corpus/epics.md"

  RQ_PROFILE="$STOCK_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" verify

  [ "$status" -eq 0 ]
  [[ "$output" == *"epics 1-1"* ]]
  # FR3 is declared by the index entry for epic 2 and mapped to epic 2, which
  # is past the written boundary, so the two sides disagree and say how.
  [[ "$output" == *"EPIC-CLAIMS-NOT-IN-MAP FR3"* ]]
}

@test "stock: doctor names the flat-map document and the profile chain" {
  need_reqflow
  stock doctor
  assert_clean
  [[ "$output" == *"profile     $STOCK_PROFILE (RQ_PROFILE)"* ]]
  [[ "$output" == *"extends     $DEFAULT_PROFILE"* ]]
  # One document carries both roles here, which is what a monolithic epics
  # document is, and doctor names it under each rather than hiding the overlap.
  [[ "$output" == *"map         epics.md"* ]]
  [[ "$output" == *"epic        epics.md"* ]]
}

@test "a map pattern carrying a third capture group is refused" {
  # The trap this refuses: rq_alt opens a group of its own, so a map_line built
  # with it shifts the epic number into capture 3 and leaves capture 2 holding
  # a namespace name. Every row's epic then evaluates as zero, every row passes
  # the written-epic test, and the map parses clean and wrong.
  {
    grep -v '^map_line=' "$STOCK_PROFILE"
    echo 'map_line="^($(rq_alt NFR FR)[0-9]+): Epic ([0-9]+).*$"'
  } > "$WORK/three-groups.sh"

  RQ_PROFILE="$WORK/three-groups.sh" RQ_ARTIFACTS="$STOCK" run --separate-stderr "$CHECK" verify

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"3 capture group(s) where the reader needs exactly two"* ]]
  [[ "$stderr" == *"rq_ids"* ]]
}

@test "rq_ids keeps a whole identifier inside one group, longest namespace first" {
  need_reqflow
  # The suffix sits inside the group and the names are ordered longest first,
  # so a bare FR branch cannot match the FR inside an NFR identifier and the
  # group count stays at one.
  {
    grep -v '^map_line=' "$STOCK_PROFILE"
    echo 'map_line="^$(rq_ids '"'"'[0-9]+'"'"' FR NFR): +Epic ([0-9]+).*$"'
    echo 'echo "BUILT $map_line" >&2'
  } > "$WORK/ids.sh"

  RQ_PROFILE="$WORK/ids.sh" RQ_ARTIFACTS="$STOCK" run --separate-stderr "$CHECK" verify

  [ "$status" -eq 0 ]
  [[ "$stderr" == *'BUILT ^(NFR[0-9]+|FR[0-9]+): +Epic ([0-9]+).*$'* ]]
  [[ "$output" == *"ok: exact match, 3/3"* ]]
}

@test "a profile reading its map both ways is refused, and so is one reading it neither" {
  # Owing both leaves the engine to pick, and whichever it picked would be
  # right about half the corpora that set both.
  {
    grep -v '^map_col_req=\|^map_col_epic=' "$STOCK_PROFILE"
    echo "map_col_req='Requirement'"
    echo "map_col_epic='Epic'"
  } > "$WORK/both.sh"

  RQ_PROFILE="$WORK/both.sh" RQ_ARTIFACTS="$STOCK" run --separate-stderr "$CHECK" verify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"never as both"* ]]

  grep -v '^map_line=' "$GENERIC_PROFILE" > "$WORK/neither.sh"
  RQ_PROFILE="$WORK/neither.sh" RQ_ARTIFACTS="$GENERIC" run --separate-stderr "$CHECK" verify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"defines no map_line"* ]]
}

@test "stock: a map padded for alignment loses no row" {
  need_reqflow
  # A hand-maintained flat map pads the epic column so it lines up, which puts
  # two spaces after a one-digit identifier and one after a two-digit one. A
  # pattern demanding exactly one space drops the single-digit rows, and drops
  # them silently: the map still parses, `verify` still reports, and the answer
  # is wrong about exactly the requirements that vanished.
  grep -q '^FR1:  Epic 1' "$STOCK/epics.md"
  stock doctor
  assert_clean
  [[ "$output" == *"map         epics.md (3 entries parsed)"* ]]
}

@test "doctor counts the map entries the reader took, not the ones it could see" {
  need_reqflow
  # Locating the map and reading it are separate failures and only the first is
  # loud. A header probe resolves a document whose rows the reader then takes
  # none of, and `verify` reports SKIP where it would have reported a diff.
  local corpus; corpus="$(generic_copy)"
  # The header stays, so the role still resolves. The rows stop matching.
  sed -i.bak 's/^| FR/| XR/; s/^| NFR/| XNFR/' "$corpus/epics/05-coverage-map.md"
  rm -f "$corpus"/epics/*.bak

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"(0 entries parsed)"* ]]
}

@test "a coverage map whose two named columns sit side by side resolves" {
  need_reqflow
  # A pattern demanding a column between the two would miss every map that puts
  # them adjacent, which is the commonest shape a hand-written map takes.
  local corpus; corpus="$(generic_copy)"
  cat > "$corpus/epics/05-coverage-map.md" <<'MAP'
# Coverage Map

| Requirement | Epic |
|---|---|
| FR1 | 1 |
| FR2 | 1 |
| NFR1 | 1 |
| FR3 | 2 |
MAP

  # Under the shipped default profile, whose probe is the one this is about.
  # The generic corpus declares its requirements in the plain form that profile
  # reads, so it is a corpus the default can resolve.
  RQ_PROFILE="$DEFAULT_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" verify
  assert_clean
  [[ "$output" == *"ok: exact match, 3/3"* ]]
}

@test "an epic cell carrying words as well as a number is read by its number" {
  need_reqflow
  # `"Epic 2" + 0` is zero, and zero is at or below every bound, so a reader
  # coercing the cell would admit every row whatever the written boundary is.
  # Here epic 2 is unwritten, so a row admitted wrongly shows up as a match
  # where a diff belongs.
  local corpus; corpus="$(generic_copy)"
  cat > "$corpus/epics/05-coverage-map.md" <<'MAP'
# Coverage Map

| Requirement | Phase | Epic | Note |
|---|---|---|---|
| FR1 | first | Epic 1 | Recorded by story 1.1 |
| FR2 | first | Epic 1 | Recorded by story 1.2 |
| NFR1 | first | Epic 1 | Recorded by story 1.1 |
| FR3 | later | Epic 2: Export | Epic 2 carries no story file yet |
MAP

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" verify
  assert_clean
  # Three rows at or below epic 1, and FR3 restricted away rather than admitted
  # as epic zero.
  [[ "$output" == *"ok: exact match, 3/3"* ]]
}

@test "an epic cell carrying no number at all takes its row out of the map" {
  need_reqflow
  # Not silently in range. The row is absent from the parsed map, and the count
  # doctor prints is what shows it.
  local corpus; corpus="$(generic_copy)"
  sed -i.bak 's/^| FR1 | first | 1 |/| FR1 | first | TBD |/' "$corpus/epics/05-coverage-map.md"
  rm -f "$corpus"/epics/*.bak

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"(3 entries parsed)"* ]]
}

# ── The reqflow interface ────────────────────────────────────────────────────

@test "doctor names the reqflow version whose output shapes it verified" {
  need_reqflow
  generic doctor
  assert_clean
  [[ "$output" == *"reqflow     $REQFLOW (Reqflow "*", output shapes verified)"* ]]
}

@test "a reqflow whose output shapes moved is fatal rather than empty" {
  # None of the shapes this script reads is a promised interface. An upstream
  # that reformatted one would not break a contract, and the failure is silent:
  # a stat -v whose status column moved reports every requirement covered, and
  # `orphans` then prints nothing, which is the shape of a clean corpus.
  cat > "$WORK/moved-reqflow" <<'FAKE'
#!/usr/bin/env bash
# Answers `version` and nothing else, which is an upstream whose output moved
# rather than one that is absent.
[ "${1:-}" = version ] && { echo "Reqflow 9.0.0"; exit 1; }
exit 0
FAKE
  chmod +x "$WORK/moved-reqflow"

  REQFLOW="$WORK/moved-reqflow" RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$GENERIC" \
    run --separate-stderr "$CHECK" orphans

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"does not produce the output this script reads"* ]]
  [[ "$stderr" == *"stat -v"* ]]
  # The version the assertions were written against, named in the failure
  # rather than compared against the binary: a consumer builds reqflow from
  # source, so a version test would fail a build that still behaves.
  [[ "$stderr" == *"Reqflow 1.6.0"* ]]
  [[ "$stderr" == *"GPL-2.0-or-later"* ]]
}

@test "the interface check runs before doctor reports anything" {
  # doctor is what a consuming skill runs first, so a doctor that reported
  # resolved roles under a reqflow it had not checked would be the one command
  # able to bless a run that cannot answer.
  cat > "$WORK/moved-reqflow" <<'FAKE'
#!/usr/bin/env bash
[ "${1:-}" = version ] && { echo "Reqflow 9.0.0"; exit 1; }
exit 0
FAKE
  chmod +x "$WORK/moved-reqflow"

  REQFLOW="$WORK/moved-reqflow" RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$GENERIC" \
    run --separate-stderr "$CHECK" doctor

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"does not produce the output this script reads"* ]]
}

# ── Discovery filters ────────────────────────────────────────────────────────

@test "discovery filter: a marked derivative document is dropped silently" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  {
    echo '---'
    echo 'validationTarget: prd.md'
    echo '---'
    cat "$GENERIC/prd.md"
  } > "$corpus/readiness-report.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" verify

  assert_clean
  [[ "$output" == *"ok: exact match, 3/3"* ]]
}

@test "discovery filter: an unmarked copy of the PRD is fatal at a tie" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  cp "$GENERIC/prd.md" "$corpus/prd-copy.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" verify

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"role 'prd' does not resolve"* ]]
}

@test "discovery filter: an unmarked copy one declaration ahead is fatal too" {
  need_reqflow
  # Ranking separates 5 from 4 and still refuses: a copy that gained a
  # declaration outranks the original, and the winner is then the wrong file.
  local corpus; corpus="$(generic_copy)"
  {
    cat "$GENERIC/prd.md"
    echo '- **FR9** `Vision`: An extra declaration this copy carries.'
  } > "$corpus/prd-copy.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" verify

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"role 'prd' does not resolve"* ]]
}

@test "discovery filter: RQ_EXCLUDE clears the ambiguity a copy creates" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  cp "$GENERIC/prd.md" "$corpus/prd-copy.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" RQ_EXCLUDE="prd-copy.md" \
    run --separate-stderr "$CHECK" verify

  assert_clean
  [[ "$output" == *"ok: exact match, 3/3"* ]]
}

@test "discovery filter: RQ_EXCLUDE naming no file is an error, not a no-op" {
  need_reqflow
  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$GENERIC" RQ_EXCLUDE="no-such-file.md" \
    run --separate-stderr "$CHECK" verify

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"which is not a file"* ]]
}

@test "discovery filter: doctor survives an unresolved role and names both candidates" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  cp "$GENERIC/prd.md" "$corpus/prd-copy.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" run --separate-stderr "$CHECK" doctor

  # Exit 0: doctor is the command every ambiguity message sends the reader to,
  # so it has to reach the end of its report rather than die partway.
  [ "$status" -eq 0 ]
  [[ "$output" == *"prd         (UNRESOLVED)"* ]]
  [[ "$output" == *"prd-copy.md"* ]]
  [[ "$output" == *"prd.md"* ]]
}

@test "discovery filter: doctor lists what each filter removed" {
  need_reqflow
  local corpus; corpus="$(generic_copy)"
  {
    echo '---'
    echo 'research_type: technical'
    echo '---'
    echo 'A research write-up.'
  } > "$corpus/research.md"

  RQ_PROFILE="$GENERIC_PROFILE" RQ_ARTIFACTS="$corpus" RQ_EXCLUDE="arch.md" \
    run --separate-stderr "$CHECK" doctor

  [ "$status" -eq 0 ]
  [[ "$output" == *"derived  research.md"* ]]
  [[ "$output" == *"caller   arch.md"* ]]
}

@test "an unknown subcommand is refused before any tree is looked for" {
  # A misspelled subcommand is the caller's to fix and says nothing about any
  # corpus, so answering it with "planning artifacts not found" would name the
  # wrong problem. Run from outside a repository, with no artifact tree
  # anywhere, so only the argument check can produce this.
  local away="$WORK/outside"
  mkdir -p "$away"

  run --separate-stderr env -u RQ_ARTIFACTS -u RQ_PROFILE \
    bash -c "cd '$away' && '$CHECK' no-such-command"

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unknown command"* ]]
  [[ "$stderr" == *"doctor"* ]]
}

@test "help prints the header block through the last environment variable" {
  # With no profile, no artifact tree and no repository. help describes this
  # script rather than any corpus, and it is the first thing a reader with
  # none of those runs.
  local away="$WORK/outside"
  mkdir -p "$away"

  run --separate-stderr env -u RQ_ARTIFACTS -u RQ_PROFILE \
    bash -c "cd '$away' && '$CHECK' help"

  [ "$status" -eq 0 ]
  [[ "$output" == *"RQ_ARTIFACTS"* ]]
  [[ "$output" == *"RQ_PROFILE"* ]]
  [[ "$output" == *"RQ_EXCLUDE"* ]]
  [[ "$output" == *"WRITTEN_THROUGH"* ]]
}

@test "an artifact tree that does not exist is fatal" {
  RQ_ARTIFACTS="$WORK/no-such-tree" run --separate-stderr "$CHECK" counts

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"planning artifacts not found"* ]]
}

@test "emit takes only the three graph names" {
  need_reqflow
  generic emit nonsense

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"emit takes"* ]]
}

@test "impact with no identifier prints its usage" {
  local away="$WORK/outside"
  mkdir -p "$away"

  run --separate-stderr env -u RQ_ARTIFACTS -u RQ_PROFILE \
    bash -c "cd '$away' && '$CHECK' impact"

  [ "$status" -eq 1 ]
  [[ "$stderr" == *"usage: rqcheck.sh impact"* ]]
}

@test "no temp directory is left behind" {
  need_reqflow
  local before after
  before="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' -type d 2>/dev/null | wc -l)"
  generic all
  [ "$status" -eq 0 ]
  after="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' -type d 2>/dev/null | wc -l)"
  [ "$before" -eq "$after" ]
}
