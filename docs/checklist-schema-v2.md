# Checklist schema, version 2

This is an additive Firestore schema update. It reuses `allocation_checklist`,
`staff_inventory`, `completed_sales`, and `stock_adjustments`; no new top-level
collection, destructive backfill, or composite index is required.

## Compatibility migration

Deploy the updated readers and writers together. Records without `kind` are
incoming deliveries. `ChecklistStatus` maps existing `pending` to
`Awaiting Confirmation` and `accepted` to `Received` on read. Historical
`declined` records remain closed because their stock was already restored.
Do not convert declined records into Issue Reported or reconfirm them.
Existing audit dates/IDs remain intact. Missing allocator identities on old
records are shown as not recorded, never fabricated.

New allocations write `schemaVersion: 2`, `kind: incoming`, and
`status: Awaiting Confirmation`. Metadata editors support both legacy pending
records and new open/issue deliveries. Backups already include all affected
collections; report history stays inside the checklist document.

## allocation_checklist fields

| Field | Type / use |
| --- | --- |
| schemaVersion | Integer, 2 for new documents |
| kind | incoming or return; missing means incoming |
| status | Awaiting Confirmation, Received, Awaiting Admin Confirmation, Return Completed, Issue Reported, or Discrepancy Reported |
| staffId | Existing allocation scope identifier (branch ID or direct staff allocation ID); used by live queries |
| name, items, bundleCount | Existing delivery item snapshot and quantities |
| targetDocId, sourceInventoryId | Existing inventory references for incoming stock |
| allocatedBy, allocatedByName | Allocating admin auth UID and display identity for new deliveries |
| createdAt, assignedAt | Firestore timestamps; createdAt on all new records |
| confirmedBy, confirmedByName, confirmedAt | Auth UID, display identity, and authoritative server confirmation timestamp |
| decidedBy, decidedAt | Retained incoming compatibility audit fields |
| issueReason, reportedBy, reportedByName, reportedAt | Latest report and server timestamp |
| reports | Map keyed by generated report ID, containing status, reason, actorId, actorName, and server createdAt; preserves repeated reports |
| branchId, branchName | Return's original branch/scope and saved display name |
| submittedBy, submittedByName, staffName | Return submitting staff identity |
| quantity, reason | Positive whole return quantity and required reason |
| returnSourceCollection | staff_inventory, completed_sales, or stock_adjustments |
| returnSourceId, returnLineKey | Auditable source document and item/line |
| updatedAt | Server timestamp |

## Quantity reservation

Staff inventory returns atomically decrement the selected item's `stock`, or
reserve available bundle instances with `status: return_pending` and `returnId`
and decrement `bundleCount`. Sold/reserved instances cannot be returned again.
Admin confirmation changes these reserved bundle instances to `returned`.

Recorded refunds and reductions have already removed their stock. Instead of
subtracting again, the source document receives an additive
`checklistReturnedQuantities` map (line key to claimed integer quantity).
The transaction checks remaining unsubmitted quantity before updating this map.
Add-on catalog voids do not represent physical stock and are excluded.
A stable checklist document ID prevents replay of the same submission.

Admin receipt records physical custody in the completed checklist entry. It does
not increase sellable inventory: damaged/refunded goods must not silently become
available for sale. Any later restocking uses the existing inventory workflow.
Issue/discrepancy reporting never changes stock. Reports stay pending until the
appropriate recipient confirms after resolving the physical problem.

## Live synchronization and deployment verification

Admin and staff listen to the same collection using Firestore snapshots. Stock
changes, receipt confirmation, quantity claims, and return status changes use
transactions. Transactions require connectivity and surface failures to the user.

This repository does not contain a Firebase rules deployment configuration or
an emulator setup. The production database/rules were not modified. Before a
production rollout, verify the existing rules permit authorized admin reads of
all checklist entries, scoped staff reads, the new fields, and the corresponding
transaction writes. Rules must enforce admin-only allocation/return confirmation,
staff branch membership, authenticated audit IDs, immutable source links, and
valid transitions; client-side UI role checks are not a security boundary.

Local fake-Firestore service tests cover receipt/return flow, server audit fields,
issue/discrepancy handling, quantity limits, branch mismatch, bundle reservation,
legacy statuses, and duplicate actions. Widget tests cover live admin counts,
branch filtering, search, required report reasons, and mobile/tablet layouts.
A real two-session Admin/Staff run remains necessary to validate deployed rules
and network synchronization against the production configuration.
