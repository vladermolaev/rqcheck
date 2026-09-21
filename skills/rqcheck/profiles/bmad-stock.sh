# shellcheck shell=bash
#
# Every name assigned here is read by rqcheck.sh, which sources this file.
# shellcheck disable=SC2034
#
# Names this file reads rather than assigns come from the profile rq_extend
# loads, which shellcheck cannot follow through a runtime path. rqcheck.sh
# validates every one of them after the chain has loaded.
# shellcheck disable=SC2154
#
# rqcheck profile: a BMAD planning tree that adopted no identifier discipline
# at all, read exactly as BMAD's own templates emit it.
#
# default.sh describes the discipline a tree has to adopt before every check
# has something to read. This file describes the tree that adopted none, so it
# answers less and it answers it about an unmodified corpus. Each override
# below cites the template that forces it, under `.claude/skills/bmad-*/` in a
# repository with BMAD installed. profiles/bmad-stock.md carries the table.

rq_extend default

# ---------------------------------------------------------------------------
# The coverage map
#
# BMAD's epics template writes the map as a flat list of one line per
# requirement, under a level-3 heading, inside the epics document:
#
#     ### FR Coverage Map
#
#     FR1: Epic 1 - [Brief description]
#
# `bmad-create-epics-and-stories/steps/step-02-design-epics.md:160-167` and
# `templates/epics-template.md:30-32`. There is no table anywhere in that
# skill, so the column names the default reads by are emptied and the flat
# pattern replaces them.
#
# The pattern matches a whole line because the engine substitutes what it
# matched: one that stopped at the epic number would leave the description
# standing in the output. Capture 1 is the identifier and capture 2 the epic
# number, and the anchor is what keeps it off the `**FRs covered:**` lines,
# which name identifiers mid-line rather than at a line start.
#
# ` +` rather than a single space. A map padded for alignment writes two spaces
# after a one-digit identifier and one after a two-digit one, and a pattern
# demanding exactly one drops the single-digit rows. The lost rows are silent:
# the map still parses, `verify` still reports, and the answer is wrong about
# the requirements that vanished. `doctor` prints the entry count for the same
# reason.
# ---------------------------------------------------------------------------

map_col_req=''
map_col_epic=''
# rq_ids rather than rq_alt: this pattern is read as a POSIX ERE, which has no
# non-capturing group, so an alternation that opened a group of its own would
# shift the epic number into capture 3 and leave capture 2 holding a namespace
# name. The engine counts the groups and refuses a pattern that carries a
# third, but the helper is what keeps the ordering right without the author
# meeting either trap.
map_line="^$(rq_ids '[0-9]+' NFR FR): +Epic ([0-9]+).*$"
probe_map='^#+ FR Coverage Map'

# ---------------------------------------------------------------------------
# The epics document
#
# One file holds the coverage map, the epic list and every epic body, so the
# declaration graph has to be cut out of it rather than found in a file of its
# own.
#
# What an epic delivers is stated once, in the `## Epic List` index, as a
# `**FRs covered:** FR1, FR2` line under a level-3 entry
# (`steps/step-02-design-epics.md:133-145`). The per-epic bodies further down
# carry no identifier at all, so reading them yields an empty delivery graph
# and `verify` then reports every requirement missing from the epics.
#
# So the declaration graph captures the index entries and stops where the
# bodies begin. `-stop-after` excludes the matching line onward, and the first
# level-2 `## Epic N:` heading is the first body section: `## Epic List` is
# level 2 but carries a word rather than a digit, so it does not match.
# ---------------------------------------------------------------------------

req_epic_decl='^### (Epic [0-9]+)'
start_epic_decl='^## Epic List'
stop_epic_decl='^## Epic [0-9]+'

# The story graph reads the bodies, where the stories are. Capturing the index
# entries here too would declare each epic twice in one document, so only the
# level-2 bodies and the level-3 stories are captured.
req_epic_story='^### (Epic [0-9]+|Story [0-9]+\\.[0-9]+)'
start_epic_story='^## Epic List'
