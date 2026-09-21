---
stepsCompleted: []
inputDocuments: []
---

# Recording Service Epics

## Requirements Inventory

### UX Design Requirements

The operator sees a confirmation after every recorded submission.

### FR Coverage Map

FR1:  Epic 1 - the store records one submission
FR2:  Epic 1 - the list reads the store
FR3:  Epic 2 - the exporter reads the store

## Epic List

### Epic 1: Record and list submissions

Operators record submissions and read back what they recorded.
**FRs covered:** FR1, FR2

### Epic 2: Export the recorded submissions

Operators take the recorded submissions elsewhere.
**FRs covered:** FR3

## Epic 1: Record and list submissions

Operators record submissions and read back what they recorded.

### Story 1.1: Record a submission

As an operator,
I want to send a submission,
So that it is retained.

**Acceptance Criteria:**

**Given** an operator with a submission
**When** it is sent
**Then** it is recorded and retrievable.

### Story 1.2: List the recorded submissions

As an operator,
I want to list what has been recorded,
So that I can confirm a submission arrived.

**Acceptance Criteria:**

**Given** recorded submissions
**When** the list is requested
**Then** it names every recorded submission.

## Epic 2: Export the recorded submissions

Operators take the recorded submissions elsewhere.

### Story 2.1: Export the recorded submissions

As an operator,
I want to export what has been recorded,
So that I can use it elsewhere.

**Acceptance Criteria:**

**Given** recorded submissions
**When** an export is requested
**Then** every recorded submission appears in the export.
