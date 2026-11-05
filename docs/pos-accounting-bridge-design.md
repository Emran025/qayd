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

The version 2 POS template now defines `openingBalanceClearing` as a required stable account key and installs it during explicit POS activation. Opening-balance posting therefore has an authorized counterpart without selecting an unrelated account by name. Future posting flows must continue to resolve template accounts through stable metadata keys.

## Fiscal-period and correction rules

Posting dates in closed fiscal periods must be rejected before any voucher, ledger, or stock write. A correction must be a new reversal or corrective document linked to the source document; neither the voucher nor ledger rows may be updated to rewrite history. The bridge must reject duplicate source/idempotency keys deterministically and return the existing posting only when its immutable fingerprint matches.

## Atomicity requirement

Stock movement and accounting posting must share one atomic application/data boundary for every posted purchase, sale, sales return, opening balance, or stock adjustment. The Data-layer `SqlitePosAccountingPostingRepository` runs opening stock and manual stock adjustments with their official voucher-ledger persistence through one `DatabaseTransactionRunner` transaction. Purchase, sale, and sales-return posting repositories likewise expose caller-owned transaction methods for invoice lines, stock movements, payments, and voucher/ledger rows. POS invoice collections commit the payment, invoice balance, voucher, and ledger effects together. Purchase-return remains outside this atomic vertical slice and must not be auto-posted. Application use cases own governance, fiscal-period, product, currency/scale, activation, and account-map checks before delegating to those boundaries.

### Opening-balance replay policy

The coordinator applies the following fail-closed rules inside the same transaction. A replay is successful only when both the stock movement identified by its idempotency key and the voucher with its ledger entries are present and their immutable business fingerprints match. An existing stock row without its complete accounting posting, a voucher without its stock movement, a ledger count or payload mismatch, or a different voucher using the same source reference is rejected as a partial/conflict state; it is never repaired by deleting or replacing history. Exact replay returns success without deleting and reinserting ledger rows, preserving append-only audit history.

Posting date matching uses the **UTC calendar date** rather than exact timestamps. This permits harmless differences in time-of-day while still preventing a movement and its bridge voucher from crossing fiscal business dates. Audit `created_at` timestamps are excluded from the replay fingerprint; all business identifiers, amounts, accounts, sides, currencies, dates, and payload fields remain part of the comparison.

The typed template-installation read port is read-only and returns the enabled warehouse plus account IDs keyed by stable `PosTemplateAccountKey.value` metadata. It never provisions accounts. The opening-balance UI invokes the governed orchestration and retains its idempotency key across retries of the same form values. Purchase receiving also persists a SHA-256-keyed request identity in the encrypted local database before submission; the invoice UUID, idempotency key, and original date survive app restarts. The intent remains until the UI acknowledges the successful result, so a restart after database commit but before the success message replays the same immutable posting rather than creating a duplicate. Stock is refreshed only after the atomic posting succeeds.

### Manual stock-adjustment replay policy

The adjustment use case rejects inactive products, invalid quantity scales/currencies, closed fiscal periods, inactive accounts, and decreases that exceed current stock. The Data adapter repeats the weighted-average and non-negative-stock checks inside the transaction, then persists the append-only movement and balanced voucher/ledger pair together. The request IDs remain stable for retries while the form is open; the selected counter-account must be an active account distinct from inventory.

## Implementation order

1. **Completed:** Add and version the opening-balance clearing account mapping.
2. **Completed for opening balance:** Define typed account-map access and posting payload/coordinator ports in Domain/Application.
3. **Completed for opening balance:** Build the governed bridge using the official voucher and `EntryGenerator` path.
4. **Completed for opening balance:** Commit stock plus voucher-ledger effects through one coordinator transaction, with replay, conflict, partial-state, and rollback tests.
5. **Completed:** Connect the opening-balance UI to the governed use case; widget coverage verifies that product, quantity, cost, currency, source ID, and idempotency key are sent to the atomic coordinator.
6. **Completed:** Implement atomic purchase receiving, inventory movement history, and governed stock adjustments; exact purchase retries retain their persisted request identity across app restarts.
7. **Next (workflow/UI scope):** Add damaged/expired stock and batch/expiry tracking; finish operator-facing sales-return and collection workflows around their atomic posting boundaries; then implement invoice cancellation/reversal, discounts, tax handling, and thermal receipt printing with linked accounting effects.

## Cross-device sync boundary

The Laravel sync API remains a blind relay for opaque encrypted payloads; it does not need POS-specific plaintext endpoints or tables. The feature branch for same-account devices adds v2 per-device E2EE envelopes and transactional outbound rows for sales, purchases, sales returns, and invoice collections. On receipt, an active paired-device and same-account check runs before decryption/dispatch; the posting, financial inbox/idempotency marker, and inbound journal state commit together. Exact transport replays do not repeat the local posting. Conflicts, missing local mappings, unsupported event types, and failed writes stay quarantined and are not acknowledged as applied. Purchase-return intentionally remains unsupported until it has a complete atomic aggregate.

This is same-party device replication, not cross-party auto-posting. A POS credit sale to another company continues through Qayd's existing bilateral accept/reject invoice flow; the recipient's purchase or ledger is not created automatically. The feature depends on referenced same-account products, accounts, and other records already being present on the receiving device. The branch does not yet provide an out-of-order dependency queue, an operator-facing quarantine/reconciliation workflow, or a full device revocation/rotation lifecycle. See [the POS multi-device E2EE safety ADR](adr/pos-e2ee-multidevice-sync.md) for exposed metadata, what is implemented, and the remaining release gates. This code is under review and is not a production release; never send financial records in plaintext to the API.

## Remaining UI and workflow scope

- The inventory movement history and stock adjustment are implemented; damaged/expired stock, batches/expiry tracking, and purchase returns still need dedicated workflows plus atomic accounting coordinators.
- Sales returns, invoice cancellation/reversal, later customer collections, discounts, tax handling, and thermal receipt printing remain outstanding.
- Product and category removal is archival/deactivation only in this slice; hard deletion is intentionally excluded to protect existing stock and accounting history. A future physical-delete action would need a guarded no-history/no-reference policy.
