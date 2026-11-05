# ADR: POS multi-device E2EE sync safety boundary

**Status:** Proposed; not an approval to enable financial POS replication.

**Related issue:** [#86](https://github.com/Emran025/qayd/issues/86).
**Scope:** Flutter client and local SQLCipher database only. No `qayd_api` changes.

## Context

Qayd already uses libsodium sealed boxes and Ed25519 signatures for selected sync events. That proves the confidentiality and authenticity of those envelopes; it does not prove that POS products, stock, invoices, payments, or returns are replicated between devices. The existing credit-invoice chat event carries a snapshot and PDF for a conversation and does not apply a second sale or ledger posting.

A multi-device POS protocol is safety-critical: independent offline sales can race for the same stock, and applying a sale plus its voucher/ledger representation twice would corrupt accounting history. The server must remain a blind relay and must not receive decrypted business records or private keys.

## Threat model and exposed metadata

Assume the relay can read, retain, reorder, duplicate, delay, or drop event envelopes and can submit malformed or unsupported envelopes. A non-paired or revoked device may attempt to inject or decrypt future events. A client may restart between receiving an event, applying it locally, and acknowledging it.

The relay-facing `SyncNode` currently contains routing and transport metadata outside the E2EE envelope. This can include node/event identifiers, sender and recipient account/phone/WhatsApp hints, public keys, device/session identifiers, client timestamps, sync state, and envelope size. These fields are not confidential merely because the body is encrypted. Any future protocol change must minimize and document the exact fields needed for routing.

Product/customer names, prices, quantities, invoice and payment details, stock levels, signatures over business snapshots, and PDF bytes must remain inside the authenticated ciphertext. Private keys must remain in device secure storage and must never be sent to the relay.

## Decision for this safety increment

- Keep the relay blind; do not add POS plaintext fields, tables, or endpoints to `qayd_api`.
- Persist inbound processing state in the local SQLCipher database. Store the event ID, a SHA-256 fingerprint of its routing/authentication context and ciphertext, safe event metadata, and the original encrypted envelope only for quarantined events. Never store decrypted business payloads or raw exception text in the journal.
- Claim an event before invoking a handler. An exact replay of an applied event may be acknowledged without applying it again. A same-ID/different-fingerprint event is rejected. An event already being processed is neither applied nor acknowledged by a second caller.
- Unknown, unsupported, rejected, and delegated events remain quarantined with their ciphertext available for local review; they are not acknowledged as applied. Generic external-counterparty events from an unpaired sender may remain pending for pairing, but a POS financial event without an active same-account paired-device session is quarantined and is not auto-retried.
- Credential-bootstrap and P2P-handshake nodes are not consumed by the general sync processor. Until their dedicated processors are connected, the general processor must not acknowledge them.
- Keep cryptographic algorithms and key derivation in the existing reviewed libsodium implementation. Do not implement custom cryptography or silently downgrade envelope versions.

## Implemented boundary and remaining limitations

This feature increment implements a same-account, active-paired-device path for POS sales, purchases, sales returns, and invoice collections. Each recipient gets a distinct E2EE envelope. The outbound posting, financial event record, and device outbox rows share the local SQLite transaction. On receipt, the POS business mutation, financial inbox/idempotency record, and generic inbound journal `applied` state share one transaction. The transport may deliver more than once; an exact event replay is acknowledged without repeating its local financial effect, while a conflicting replay is retained as a quarantine and is not acknowledged as applied.

The processor checks that sender and recipient account IDs match the current account, the target device is this device, and the sender is a currently active paired device before decrypting or dispatching. Authenticated event version, device IDs, event kind, canonical digest, and the full posting snapshot are validated. Missing local mappings, conflicting history, or a failed atomic posting abort the write and retain the encrypted event for review. Purchase-return remains explicitly unsupported because it has no atomic POS aggregate; it is quarantined without acknowledgement. A credit sale to a different company continues through Qayd's bilateral accept/reject invoice flow and does not create an automatic purchase or ledger posting for the other company.

This is exactly-once **local effect** through idempotent transactional application, not exactly-once network delivery. The code is on a review branch and is not a production release. The device registry's active flag is checked, but a complete device enrollment/revocation/rotation and lost-device response is not part of this increment. The receiver must already have compatible same-account products, accounts, and other referenced records; there is no independent catalog synchronization or stable-ID remapping. Events blocked by missing data or stock conflicts are durably retained, but a dedicated review/reconciliation UI, explicit stock-conflict workflow, and out-of-order dependency queue remain future work. The existing quarantine does not silently overwrite history or post a partial transaction.

## Decisions still required before production activation

1. Device lifecycle: complete approval, revocation/rotation, lost-device, backup/recovery, and old-ciphertext policies around the paired-session check already used by this branch.
2. Causal ordering and conflict recovery: define sequence/dependency handling for out-of-order events and an authorized manual workflow for stock conflicts, without rewriting immutable postings.
3. Data availability: decide and verify how referenced catalog/account records are kept aligned across same-account devices; missing mappings currently fail closed.
4. Manual review: provide an operator-facing view and authorized resolution action for quarantined financial events. Until then, the retained ciphertext is available for review but not through a complete accounting workflow.
5. Failure and restore semantics: extend transaction rollback/replay tests with end-to-end two-device recovery and SQLCipher backup/restore validation.

## Evidence required before production activation

This branch has local tests for v2 event canonicalization and snapshots, encrypted per-device outbox preparation, atomic sale/purchase/sales-return/collection repositories, exact and conflicting replay, transaction rollback, active-pair authorization, and quarantine without ACK. The full Flutter suite and analyzer must pass, and iOS simulator assertions must actually run. Before production activation, still verify a real two-device encrypted exchange, unpaired/revoked-key cases, tampering and downgrade rejection, out-of-order delivery, crash/restore boundaries, opaque relay payloads/logs, and offline same-stock conflict review. A successful compile or CI run alone is not a substitute for this release evidence.
