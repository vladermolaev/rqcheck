---
stepsCompleted: []
inputDocuments:
  - prd.md
workflowType: 'architecture'
---

# Recording Service Architecture Decision Document

## Core Architectural Decisions

### Data Architecture

One relational table holds the submissions, since the list and the record path
read the same rows.

### Authentication & Security

The operator authenticates at the edge and the store trusts the edge.
