# POS Accounting Bridge Design

## Objective

The POS accounting bridge must connect a posted POS document or opening-stock movement to Qayd's existing voucher and ledger workflow without creating a parallel ledger writer. It must remain inside the shared Flutter application, SQLCipher database, identity, governance rules, and fiscal-period policy.

## Existing official path

Qayd already exposes `VoucherRepository.saveWithLedgerEntries`, which persists a voucher and its generated ledger lines in one transaction. `EntryGenerator` builds the canonical two-line receipt/payment entries from a confirmed `Voucher`. `CreateVoucherUseCase` performs governance and fiscal-period checks before saving a voucher. POS must reuse or extend these official ports rather than inserting into `ledger_entries` directly.

## Required POS bridge boundary

The bridge should be an Application-level orchestration use case. Its input is a typed POS posting command containing the source POS document ID, posting date, base currency, total amount, account mapping keys, and an idempotency key. It must first pass `GovernanceWriteGuard`, then apply `FiscalPeriodPolicy` to the posting date, resolve the activated POS template account IDs by metadata key, construct a confirmed domain `Voucher`, generate balanced `LedgerEntry` values through the approved generator or a POS-specific domain generator, and delegate persistence to `VoucherRepository.saveWithLedgerEntries`.

The Data layer remains responsible for persistence adapters and transaction implementation. No Widget, Cubit, POS repository, or stock movement adapter may issue SQL against `ledger_entries`. Any SDK or existing accounting implementation must remain behind a repository or adapter port.

## Document-to-entry mapping

| POS event | Debit | Credit | Inventory effect |
|---|---|---|---|
| Opening stock | POS inventory asset | POS opening-balance clearing/equity account | Inbound at supplied cost |
| Purchase, cash | POS inventory asset | POS cash | Inbound at purchase cost |
| Purchase, credit | POS inventory asset | Supplier payable | Inbound at purchase cost |
| Sale, cash | POS cash | POS sales revenue | Outbound at weighted-average cost; separate COGS pair required |
| Sale, credit | Customer receivable | POS sales revenue | Outbound at weighted-average cost; separate COGS pair required |
| Sales return | POS sales returns and inventory asset as applicable | Customer/cash and COGS reversal as applicable | Inbound at the approved return-cost policy |
| Purchase return | Supplier payable/cash and purchase-returns account as applicable | POS inventory asset | Outbound at the original or approved return-cost policy |

A sale or purchase cannot be considered posted when only the revenue/payment pair exists while the inventory and COGS effects are absent. The final implementation must represent the complete balanced journal, not a partial convenience entry.

## Identified prerequisite

The current POS template contains inventory, revenue, COGS, cash, receivables, payables, returns, discounts, and optional tax accounts, but it does not contain an explicit opening-balance clearing/equity account. The opening-balance accounting bridge must not silently use an unrelated account. Before posting opening stock to the ledger, the template must gain a stable `openingBalanceClearing` account key under a versioned template upgrade, or the product must explicitly select an existing authorized counterpart account through a typed configuration use case. The choice must be persisted by metadata key, not by account name.

## Fiscal-period and correction rules

Posting dates in closed fiscal periods must be rejected before any voucher, ledger, or stock write. A correction must be a new reversal or corrective document linked to the source document; neither the voucher nor ledger rows may be updated to rewrite history. The bridge must reject duplicate source/idempotency keys deterministically and return the existing posting only when its immutable fingerprint matches.

## Atomicity requirement

Stock movement and accounting posting must share one atomic application/data boundary for every posted purchase, sale, return, or opening balance. The opening-balance slice now has a Data-layer `SqlitePosAccountingPostingRepository` that runs stock validation/insert and official voucher-ledger persistence through one `DatabaseTransactionRunner` transaction. The Application use case owns governance, fiscal-period, product, currency/scale, activation, and account-map checks before delegating to that boundary. Sequential stock-plus-ledger writes remain forbidden for future posted sales, purchases, and returns until they use the same pattern.

### Opening-balance replay policy

The coordinator applies the following fail-closed rules inside the same transaction. A replay is successful only when both the stock movement identified by its idempotency key and the voucher with its ledger entries are present and their immutable business fingerprints match. An existing stock row without its complete accounting posting, a voucher without its stock movement, a ledger count or payload mismatch, or a different voucher using the same source reference is rejected as a partial/conflict state; it is never repaired by deleting or replacing history. Exact replay returns success without deleting and reinserting ledger rows, preserving append-only audit history.

Posting date matching uses the **UTC calendar date** rather than exact timestamps. This permits harmless differences in time-of-day while still preventing a movement and its bridge voucher from crossing fiscal business dates. Audit `created_at` timestamps are excluded from the replay fingerprint; all business identifiers, amounts, accounts, sides, currencies, dates, and payload fields remain part of the comparison.

The typed template-installation read port is read-only and returns the enabled warehouse plus account IDs keyed by stable `PosTemplateAccountKey.value` metadata. It never provisions accounts. The opening-balance UI now invokes the governed orchestration and carries a stable idempotency key across retries of the same form values; stock is refreshed only after the atomic posting succeeds.

## Implementation order

1. **Completed:** Add and version the opening-balance clearing account mapping.
2. **Completed for opening balance:** Define typed account-map access and posting payload/coordinator ports in Domain/Application.
3. **Completed for opening balance:** Build the governed bridge using the official voucher and `EntryGenerator` path.
4. **Completed for opening balance:** Commit stock plus voucher-ledger effects through one coordinator transaction, with replay, conflict, partial-state, and rollback tests.
5. **Completed:** Connect the opening-balance UI to the governed use case; widget coverage verifies that product, quantity, cost, currency, source ID, and idempotency key are sent to the atomic coordinator.
6. **Next:** Implement purchase inbound posting before sales/COGS checkout, then build the linked correction, return, collection, and inventory-adjustment workflows with matching atomic accounting coordinators.

## Cross-device sync boundary

The Laravel sync API is a blind relay for opaque encrypted payloads; it does not need POS-specific plaintext endpoints or tables. However, the Flutter client currently emits and applies only its registered sync event types. POS products, stock movements, and invoices are not yet emitted through the outbox or applied by the inbound processor; an unrecognized event is treated as `unknown` and returned as processed. POS data therefore remains local to the device today. Before enabling cross-device POS sync, define versioned encrypted event envelopes plus replay/idempotency, conflict, ordering, and acknowledgement behavior, then add client-side dispatch/processor coverage. Do not send financial records in plaintext to the API.
