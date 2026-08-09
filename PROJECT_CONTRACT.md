# AI Agent Workflow Builder

# PROJECT CONTRACT

## 1. Purpose

This repository contains one shared AI Agent Workflow Builder application.

Multiple specialist development chats may work on different subsystems, but all components belong to the same application, architecture, repository, and integration contract.

This document is the shared architectural contract.

---

## 2. Source of Truth

The assignment specification defines the required product behavior, technology choices, priorities, and evaluation scenario.

When implementation decisions are ambiguous, preserve the assignment requirements and prefer the simplest architecture that satisfies them.

---

## 3. Technology Stack

Frontend:

* Next.js
* React

Backend:

* Python
* FastAPI

Data/API:

* Nhost
* Hasura GraphQL Engine
* PostgreSQL
* GraphQL

External integrations:

* Real LLM API where practical
* HTTP APIs

Repository:

* GitHub

Deployment:

* Vercel for frontend
* Render/Railway or equivalent for Python backend
* Nhost for authentication/PostgreSQL/Hasura environment

Do not introduce unnecessary infrastructure.

Avoid:

* Redis
* Kafka
* Celery
* Kubernetes
* unnecessary microservices
* LangChain
* LangGraph
* other infrastructure that does not directly support the assignment

---

## 4. Architecture

The system consists of five primary layers:

1. Next.js / React frontend
2. Nhost authentication
3. Hasura GraphQL and authorization
4. PostgreSQL persistence
5. Python/FastAPI workflow executor

Hasura provides:

* GraphQL
* relationships
* subscriptions
* declarative authorization
* Actions

Python/FastAPI provides:

* workflow execution
* procedural authorization
* external API calls
* retries
* approval/resume
* quota checks
* webhook execution

Next.js provides:

* user interface
* workflow editing
* run controls
* approval interface
* realtime execution display

The frontend is never a security boundary.

---

## 5. Repository Structure

The repository should contain:

frontend/
backend/
hasura/
migrations/
graphql/
docs/
tests/
scripts/

.env.example
PROJECT_CONTRACT.md
README.md

Specialists may add files within their owned subsystem when necessary, but should not restructure the application without a documented architectural change.

---

## 6. Core Database Entities

Required entities:

* organizations
* org_members
* workflows
* workflow_steps
* workflow_triggers
* workflow_runs
* step_runs

Relationships:

organization
→ org_members

organization
→ workflows

workflow
→ workflow_steps

workflow
→ workflow_triggers

workflow
→ workflow_runs

workflow_run
→ step_runs

Every workflow belongs to exactly one organization.

Every organization-scoped operation must ultimately be authorized through organization membership.

---

## 7. Roles

Supported roles:

* owner
* editor
* viewer

Owner:

* full workflow control
* step control
* trigger control
* organization membership management
* workflow execution
* approval
* owner-only operations

Editor:

* create/edit workflows
* edit permitted steps
* trigger workflows

Editor cannot manage organization membership or perform owner-only operations.

Viewer:

* read-only access

Viewer cannot:

* edit workflows
* trigger workflows
* approve workflow steps

A role is never sufficient by itself.

Organization membership must always be established first.

---

## 8. Organization Isolation

Organization isolation is mandatory.

The authorization relationship is:

authenticated user
→ org_members
→ organization
→ requested resource

A user from Organization B must not access Organization A resources, even if the user knows or guesses the resource UUID.

Direct ID guessing must fail.

Frontend restrictions are not sufficient.

---

## 9. Two Security Layers

### Layer 1 — Organization and role authorization

Primarily enforced by Hasura permissions.

Hasura must restrict organization-scoped database access according to the authenticated user's organization membership and role.

### Layer 2 — Procedural and step authorization

Enforced by Python/FastAPI where required.

Examples:

* owner-only db_write
* owner-only notify
* owner-only webhook trigger
* approval authorization
* execution-specific checks
* quota enforcement

The system must never rely solely on frontend authorization.

---

## 10. Workflow Step Types

Required step types:

* llm_call
* http_request
* db_write
* notify
* conditional_branch
* approval_gate

Workflow execution is primarily linear.

Steps are ordered using a position/order mechanism.

Do not build a general-purpose DAG engine unless a strong requirement appears.

Step configuration may use JSON/JSONB.

---

## 11. Workflow Run States

Supported workflow run states:

* pending
* running
* paused
* completed
* failed

Supported step run states:

* pending
* running
* paused
* completed
* failed

At an approval gate:

workflow_run.status = paused

step_run.status = paused

Execution must stop until approval occurs.

---

## 12. Required Actions

### triggerWorkflowRun

The Action must:

1. identify caller
2. verify organization membership
3. verify caller role
4. verify workflow belongs to caller's organization
5. check quota
6. create workflow_run
7. execute workflow steps
8. perform real LLM/HTTP calls where practical
9. retry at least once on failure
10. pause at approval_gate
11. update step_runs continuously
12. resume after approval
13. finalize workflow_run
14. account for usage

### approveStep

The Action must:

1. identify approver
2. verify organization membership
3. verify appropriate role
4. verify workflow run is paused
5. verify target step is an approval_gate
6. record approved_by
7. record approved_at
8. resume workflow execution

---

## 13. Trigger Types

P0:

* manual
* webhook

Manual and webhook triggers must eventually invoke the same workflow execution service.

Do not create separate workflow engines for different trigger types.

---

## 14. Workflow Execution Context

Workflow execution must maintain sufficient context to support:

* workflow identity
* workflow run identity
* organization identity
* triggering user identity
* ordered steps
* previous step outputs
* workflow variables
* approval state

Step outputs must be available to later steps when required.

The LLM output must be capable of influencing conditional execution.

---

## 15. Approval Model

An approval gate pauses execution.

The frontend displays the paused state.

Only an authorized user may approve.

Approval must be verified server-side.

After successful approval:

* approved_by is recorded
* approved_at is recorded
* workflow execution resumes
* subsequent steps continue

---

## 16. Retry Model

External operations must support at least one retry attempt.

If the final attempt fails:

* step_run becomes failed
* workflow_run becomes failed unless another explicitly supported execution policy applies

Retry behavior must not bypass authorization or quota checks.

---

## 17. GraphQL Contract

Required capabilities:

### Queries

* organization workflows
* workflow steps
* workflow triggers
* recent workflow runs
* step runs

### Mutations

* create/edit workflow configuration
* triggerWorkflowRun
* approveStep

### Subscriptions

* step_runs filtered by workflow_run_id

The frontend must receive live execution state without requiring page refresh.

---

## 18. Realtime Execution

Execution state flows through:

Python/FastAPI
→ PostgreSQL
→ Hasura
→ GraphQL subscription
→ Next.js

The frontend should display:

* pending
* running
* completed
* failed
* paused

in realtime.

---

## 19. Final Demonstration Contract

The final demonstration must prove:

### Organization A

An authorized user creates:

LLM
↓
Conditional
↓
HTTP
↓
Approval Gate
↓
DB Write

The LLM output influences the conditional branch.

The workflow can be started manually and through webhook.

Execution is visible live.

The approval gate pauses execution.

An authorized user approves it.

The workflow resumes and completes.

### Organization B

An Organization B user attempts:

* viewing Organization A workflow
* querying Organization A workflow by guessed ID
* triggering Organization A workflow
* approving Organization A run

All must fail.

This security demonstration is part of the P0 acceptance criteria.

---

## 20. Priority Levels

### P0 — Must Work

* database
* Nhost authentication
* Hasura relationships
* organization isolation
* role permissions
* triggerWorkflowRun
* LLM
* HTTP
* conditional branch
* approval gate
* resume
* step_runs
* GraphQL subscription
* Next.js UI
* manual trigger
* webhook trigger
* two organizations
* security demonstration
* deployment

### P1 — Should Work

* db_write
* notify
* quota UI
* retry demonstration
* polished README
* stronger validation/error handling

### P2 — Nice to Have

* scheduled trigger
* database event trigger
* advanced workflow canvas
* animations
* advanced notifications
* unnecessary infrastructure

If time becomes constrained, remove P2 before compromising P0.

---

## 21. Component Ownership

### Database specialist

Owns:

* PostgreSQL schema
* migrations
* constraints
* indexes
* seed/demo data

### Hasura/security specialist

Owns:

* Hasura metadata
* relationships
* permissions
* Actions
* GraphQL exposure
* subscription configuration

### Python specialist

Owns:

* FastAPI
* workflow executor
* step handlers
* procedural authorization
* retries
* quota
* approval/resume

### Frontend specialist

Owns:

* Next.js
* React UI
* workflow editor
* authentication experience
* run UI
* approval UI
* live execution UI

### QA/security specialist

Owns:

* integration testing
* security testing
* cross-organization isolation testing
* failure/retry testing
* end-to-end verification

### Deployment specialist

Owns:

* production deployment
* environment configuration
* deployment documentation
* final evaluator experience

### Architect/Tech Lead

Owns:

* architecture
* contracts
* dependency order
* integration decisions
* scope control
* change approval
* final demo readiness

---

## 22. Change Control

No specialist may silently change a shared interface.

This includes:

* database field names
* table names
* GraphQL operation names
* Action names
* API contracts
* environment variables
* status values
* authentication assumptions

Required format:

PROPOSED CHANGE

Current:
...

Proposed:
...

Reason:
...

Affected:
...

The architectural owner must review significant cross-component changes before dependent systems are modified.

---

## 23. Development Philosophy

Prefer simple, understandable, production-style code.

Before implementing a major component:

1. explain what it is
2. explain why it is required
3. explain how it connects to the architecture
4. identify affected files
5. implement
6. test
7. explain verification

Do not build cosmetic complexity before P0 works.

Do not use fake security.

Do not rely on frontend-only authorization.

Do not assume a role implies organization access.

---

## 24. Definition of Done

The project is considered P0-complete only when the evaluator can:

1. authenticate
2. access an organization
3. create/configure a workflow
4. trigger it manually
5. trigger it through webhook
6. observe live execution
7. observe an approval pause
8. approve as an authorized user
9. observe execution resume
10. observe final completion
11. switch to another organization
12. attempt cross-organization access
13. observe authorization failures

The system must be deployable and reproducible.

---
