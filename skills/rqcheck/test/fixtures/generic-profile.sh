# shellcheck shell=bash
#
# A minimal rqcheck profile for the generic fixture corpus, written
# standalone rather than extending the skill default, so the suite exercises
# the profile boundary rather than asserting it.
#
# Its vocabulary is deliberately not the default's. The requirement
# declarations use the plain form BMAD's PRD template writes, the coverage map
# has a phase column whose values are not the default's, and the declared
# counters are keyed under names nothing in the engine knows. A check that
# passes here and on this repository's own corpus has read both vocabularies
# from a profile rather than from the script.
#
# No verification table, so no bounded_table and no `thr` role: every check
# reading one must report SKIPPED and carry on.
#
# Every name assigned here is read by rqcheck.sh, which sources this file.
# shellcheck disable=SC2034

rq_artifacts_default='artifacts'

id_req="$(rq_alt NFR FR)[0-9]+"
id_dec="$(rq_alt AR DC)[0-9]+"
id_arch="$(rq_alt ADR)-[0-9]+"

probe_prd="^- $id_req:"
probe_ar='^AR[0-9]+:'
probe_dc='^DC[0-9]+:'
probe_epic='^## Epic [0-9]+'
probe_adr="^#+ $id_arch"

map_col_req='Requirement'
map_col_epic='Epic'
# This corpus keeps its map as a table, so it is read by the column names above
# and not by a flat-list pattern.
map_line=''
probe_map="^\\|[^|]*${map_col_req}[^|]*\\|([^|]*\\|)*[^|]*${map_col_epic}[^|]*\\|"

rq_role prd  single required
rq_role ar   single optional 'no additional-requirements register in this corpus'
rq_role dc   single optional 'no decomposition-constraints register in this corpus'
rq_role map  unique required
rq_role epic set    required
rq_role adr  set    required

probe_idx='^[A-Za-z]+(Totals|Tally):[ \t]*$'
probe_derived='^(validationTarget|validationStatus|research_type):|^workflowType: *.?(research|testarch-)'

req_prd="^- ($(rq_alt_nc NFR FR)[0-9]+):"
req_ar='^(AR[0-9]+):'
req_dc='^(DC[0-9]+):'
req_adr="^#+ ($(rq_alt_nc ADR)-[0-9]+)"
ref_adr="($(rq_alt_nc ADR)-[0-9]+)"
req_epic_decl='^## (Epic [0-9]+)'
ref_epic_decl="($(rq_alt_nc NFR FR)[0-9]+)"
req_epic_story='^#+ (Epic [0-9]+|Story [0-9]+\\.[0-9]+)'
ref_epic_story="($(rq_alt_nc NFR FR AR DC)[0-9]+)"
stop_epic_decl='^#{3} '
epic_heading='^## Epic [0-9]+'
# One file per epic, so the declared-coverage block starts at the top.
start_epic_decl=''
start_epic_story=''


# Keys nothing in the engine names, exercising every kind the driver carries.
# `minus` reads the rows above it, so its two operands come first.
counters_table="registerTotals.fr	lines	prd	^- FR[0-9]+:
registerTotals.nfr	lines	prd	^- NFR[0-9]+:
epicTally.total	maxnum	*	^#+ Epic [0-9]+
epicTally.withStories	docs	epic
epicTally.mapOnly	minus	epicTally.total	epicTally.withStories
storyTally.epic{n}	perdoc	epic	$epic_heading	^### Story [0-9]+\\.[0-9]+
storyTally.total	lines	epic	^### Story [0-9]+\\.[0-9]+"

# Nothing in this corpus asserts a count in a sentence, and it enumerates
# nothing in a bracketed table.
inline_counters_table=''
bounded_table=''
