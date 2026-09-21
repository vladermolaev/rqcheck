---
inputDocuments:
  - prd.md
---

# Architecture

#### ADR-1 — Store submissions in a relational table

A relational table is what FR1 and FR2 both read, so one store serves both.

#### ADR-2 — Defer the export format

FR3 is a later-phase requirement and nothing at first release reads an export.
