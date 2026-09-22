# HANDOFF — 003-backend-objectscript

## Objective
Implement the SentaiTask ObjectScript backend for persistence, validation, dispatch, and
tracking of flows defined by spec 002.

## Mandatory sources
- spec 003
- spec 002's openapi.yaml
- spec 002's data-model.md
- spec 002's flow-definition.schema.json
- spec 001's compatibility.md and decision.md

## Decisions already fixed
- Join policy v1: ALL_MUST_SUCCEED
- Scheduler via the native IRIS mechanism
- GUID via the native IRIS mechanism
- isDestructive derived from the type
- single instance in v1
- pause only for the purge family

## Technical constraints
- no unauthenticated web app
- no MatchRoles:"%All"
- no Xecute on request parameters
- no credentials in code
- preserve failureReason verbatim from IRIS

## Architectural expectation
- backend in pure ObjectScript
- full adherence to the approved contracts
- separation between persistence, validation, dispatch, API, and events
- solution prepared for decomposition into small, testable tasks

## Known risks
- the prior absence of this handoff may have left implicit assumptions
- integration decisions and namespace conventions may need adjustment
- SSE and asynchronous dispatch require technical validation on the target IRIS instance

## Points the plan must make explicit
- classes and namespaces
- persistence strategy
- REST strategy
- dispatch strategy
- SSE strategy
- transactions, concurrency, and recovery
- tests per layer
