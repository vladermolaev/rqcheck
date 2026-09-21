# shellcheck shell=bash
#
# Every name assigned here is read by rqcheck.sh, which sources this file.
# shellcheck disable=SC2034
#
# rqcheck profile: a BMAD planning-artifact tree carrying identifiers.
#
# This is the profile rqcheck.sh loads when nothing else names one. It is not a
# description of what BMAD emits. Stock BMAD numbers functional requirements
# and nothing else: it writes no NFR identifiers, no architecture decision
# records, no additional-requirements or decomposition-constraints register, no
# coverage table and no counter frontmatter. default.md names each
# addition against the template it is absent from.
#
# So a tree has to have adopted an identifier discipline for this profile to
# read it, and a tree that has not adopted one fails loudly on the first role
# that matches nothing rather than reporting on a graph it could not build.
#
# Sourced by rqcheck.sh, which defines `rq_role`, `rq_alt`, `rq_alt_nc` and
# `rq_extend` before reading this file and validates afterwards that every name
# below is set. Nothing here runs a command or reads a file; the engine does
# all of that.
#
# rq_role <name> <single|unique|set> <required|optional> [skip note]
#
#   single   the best-ranked candidate wins, and a near-tie is fatal
#   unique   exactly one candidate matches, and two is fatal. For a probe that
#            matches a table HEADER, which counts a line or two per document,
#            so ranking one candidate against another at 1 to 1 carries no
#            information at all
#   set      every matching candidate
#
# An optional role that matches nothing leaves the checks reading it to print
# SKIPPED and that role's note, and the rest of the run proceeds. Ambiguity is
# fatal for an optional role exactly as for a required one: absence is a corpus
# that does not carry the document, two candidates is a corpus that does and
# cannot say which.

# Where the artifacts live, relative to the repository root. This is the BMAD
# installer's own default for `planning_artifacts`, not a value any template
# carries, so an install that configured another path overrides it here.
rq_artifacts_default='_bmad-output/planning-artifacts'

# ---------------------------------------------------------------------------
# Namespaces
#
# Built with rq_alt so that a name which is a suffix of another cannot swallow
# it. A profile adding a prefixed namespace adds it to the call rather than to
# the pattern, and the ordering comes out right without the author knowing the
# trap is there.
# ---------------------------------------------------------------------------

id_req="$(rq_alt NFR FR)[0-9]+"
id_dec="$(rq_alt AR DC)[0-9]+"
id_arch="$(rq_alt ADR)-[0-9]+"

# ---------------------------------------------------------------------------
# Probes
#
# probe_*  identifies a file holding the role. Written for grep -E.
# ---------------------------------------------------------------------------

# A requirement declaration, in either the plain form BMAD's PRD template
# writes or the bolded form a tree that numbers its NFRs too tends to adopt.
# Nothing in the shape separates a PRD from a subsidiary register restating a
# condensed requirement list: the two are textually identical, so discovery
# resolves this role by rank and refuses a near tie. default.md carries
# the cost of that and what a corpus can do about it.
probe_prd="^- \\*{0,2}$id_req\\*{0,2}[ :]"
probe_ar='^AR[0-9]+:'
probe_dc='^DC[0-9]+:'
probe_epic='^## Epic [0-9]+'
probe_adr="^#+ $id_arch"

# The coverage map. Structural rather than row-shaped: a requirement-scoring
# table elsewhere can carry rows of the same shape, so the header naming both
# columns is what identifies it. The two column names are read back by the
# engine to locate the columns inside the file, so re-ordering them is safe and
# renaming one is a change here.
#
# Any number of columns may sit between the two named ones, including none. A
# pattern demanding at least one would miss every map that puts the two side by
# side, which is the commonest shape a hand-written map takes.
map_col_req='Requirement'
map_col_epic='Epic'
probe_map="^\\|[^|]*${map_col_req}[^|]*\\|([^|]*\\|)*[^|]*${map_col_epic}[^|]*\\|"

# Empty, so the map is read as a table by the two column names above. A tree
# keeping its map as a flat list -- which is what stock BMAD's template emits
# -- sets this instead and leaves the column names empty. profiles/bmad-stock.sh
# is that profile.
map_line=''

rq_role prd  single required
rq_role ar   single optional 'no additional-requirements register in this corpus'
rq_role dc   single optional 'no decomposition-constraints register in this corpus'
rq_role map  unique required
rq_role epic set    required
# Optional because stock BMAD records its decisions as unnumbered prose under
# topic headings. A tree that numbers them gets the architecture graph, and one
# that does not gets every check except the decision half of `uncited`.
rq_role adr  set    optional 'no numbered architecture decisions in this corpus'

# A block of derived numbers in a document's own frontmatter: a parent key
# named for what it counts, with nothing after the colon. Any register may
# carry one, so `stale` reads every match rather than a single best one. No
# BMAD template writes such a block, so this matches nothing until a tree
# starts keeping counts by hand -- which is the moment they start to drift.
probe_idx='^[A-Za-z]+([Cc]ounts|Distribution):[ \t]*$'

# A derivative document: a report, a validation, a review, a research write-up
# or a change proposal. Its subject is another document in the tree, so it
# quotes declarations rather than making them, and a quotation is
# indistinguishable from the original to any probe that counts declaration
# lines. Discovery drops these before ranking, and `stale` never reads their
# counters, because a figure in one is a record of a day rather than a claim.
#
# The marker is a frontmatter key naming what the document is ABOUT, or a
# workflowType whose value is a workflow that reports on other documents.
# `inputDocuments` cannot serve: a PRD, an architecture register and an epics
# index all carry one, because consuming a source is not the same as being a
# report on it.
#
# Every alternative here is a key some BMAD template writes. The list tracks
# those templates rather than any one corpus's contents, so a new template
# inventing a new key slips through, and it slips through silently. That is why
# a single-best role that stays ambiguous after the filter is fatal rather than
# advisory: the filter is the part that can silently miss, and the hard error is
# what keeps a miss from becoming a green wrong answer.
probe_derived='^(validationTarget|validationDate|validationStatus|validationStepsCompleted|holisticQualityRating|overallStatus|validation_date|overall_status|research_type|sourceWorkflow|generatedBy|downstream_consumer):|^type: *bmad-distillate|^workflowType: *.?(research|testarch-)'

# ---------------------------------------------------------------------------
# reqflow patterns, in config-file escaping (backslashes doubled)
# ---------------------------------------------------------------------------

req_prd="^- \\\\*{0,2}($(rq_alt_nc NFR FR)[0-9]+)"
req_ar='^(AR[0-9]+):'
req_dc='^(DC[0-9]+):'

# A document may declare a namespace or cite it, never both -- an identical
# -ref swallows the -req headings. So the architecture registers declare, and
# the bridge register cites.
req_adr="^#+ ($(rq_alt_nc ADR)-[0-9]+)"
ref_adr="($(rq_alt_nc ADR)-[0-9]+)"

# An epic read for what it declares it delivers, and read for every citation.
req_epic_decl='^## (Epic [0-9]+)'
ref_epic_decl="($(rq_alt_nc NFR FR)[0-9]+)"
req_epic_story='^#+ (Epic [0-9]+|Story [0-9]+\\.[0-9]+)'
# Every namespace a story may cite. A profile that drops the `ar` or `dc` role
# drops its namespace here too: citing one no document declares makes every
# such citation dangle.
ref_epic_story="($(rq_alt_nc NFR FR AR DC)[0-9]+)"

# Where the declared-coverage block ends. The first level-3 heading, which in
# BMAD's epic template is the first story.
stop_epic_decl='^#{3} '

# The heading that declares an epic, and whose digits are its number.
epic_heading='^## Epic [0-9]+'
# Where the declared-coverage block begins. Empty here: a tree keeping one file
# per epic has the epic heading at the top and needs no start. A tree whose one
# epics document opens with the coverage map sets this, since the map's own
# identifiers would otherwise read as citations belonging to no epic.
start_epic_decl=''
start_epic_story=''


# ---------------------------------------------------------------------------
# Declared counters
#
# Both tables are empty here. No BMAD template states a count of the corpus, in
# frontmatter or in a sentence, so there is nothing for a default profile to
# diff. A tree that keeps such counts by hand fills these in, and the key names
# it uses are its own -- `stale` matches a declaration to a derivation by key,
# so the key vocabulary belongs to the corpus that writes it.
#
# counters_table rows are `key<TAB>kind<TAB>argument...`, and rqcheck.sh
# documents the five kinds above `computed_counters`.
# inline_counters_table rows are `key<TAB>scope pattern<TAB>value pattern`.
# ---------------------------------------------------------------------------

counters_table=''
inline_counters_table=''

# The role whose document the bounded-table facility reads. Empty turns it off.
bounded_table=''
