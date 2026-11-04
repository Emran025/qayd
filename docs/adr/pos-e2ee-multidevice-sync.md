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
- Unknown, unsupported, rejected, and delegated events remain quarantined with their ciphertext available for local review; they are not acknowledged as applied. An unpaired sender remains pending so that a later explicit pairing can permit retry.
- Credential-bootstrap and P2P-handshake nodes are not consumed by the general sync processor. Until their dedicated processors are connected, the general processor must not acknowledge them.
- Keep cryptographic algorithms and key derivation in the existing reviewed libsodium implementation. Do not implement custom cryptography or silently downgrade envelope versions.

## Important limitation

This journal is a durable safety gate, not an atomic inbox/outbox protocol. The domain handler and journal's `markApplied` are not yet committed in one shared SQLite transaction. A process crash after a handler commits but before the journal records `applied` can cause a replay. Existing handler-specific idempotency remains necessary, and a future POS processor must make its business mutation, deduplication marker, and acknowledgement eligibility atomic.

This increment does **not** enable POS financial replication. There is still no transactional outbox tied to POS posting, no inbound POS sale/purchase/return/payment application, no unified voucher/ledger idempotency reference, no device-level revocation check bound into the signed envelope, and no offline inventory reconciliation workflow. Do not claim exactly-once delivery, full multi-device E2EE POS sync, or production readiness from these changes.

## Decisions required before enabling financial events

1. Device identity and lifecycle: pairing approval, per-device key ownership, revocation/rotation, lost-device response, backup/recovery, and the effect of revocation on old ciphertext.
2. Envelope v2: authenticated schema/version, event ID, source device ID, sequence/causal context, idempotency/business fingerprint, and downgrade/replay rules. Device authorization must be checked before dispatch.
3. First POS vertical slice and transactional boundary: which product, stock, sale/purchase/return, and collection events are included, and how outbox creation shares the posting transaction.
4. Inbound atomicity and duplicate accounting: share source/idempotency references with Voucher/Ledger events so POS and accounting projections cannot post the same effect twice.
5. Offline conflicts: preserve both immutable events, detect oversell, and route conflicts to an explicit authorized reconciliation action; never silently overwrite a posted sale or stock history.
6. Failure and restore semantics: prove crash-before/after-commit replay behavior and SQLCipher backup/restore behavior on two trusted devices.

## Required evidence before production activation

Tests must cover two-device encryption/decryption, unpaired and revoked devices, tampering and version downgrade, exact and conflicting replays, unsupported-event quarantine, out-of-order delivery, crash boundaries, opaque relay payloads and logs, shared POS/Ledger idempotency, and offline same-stock conflicts. iOS simulator assertions must actually run; a successful iOS compile is not sufficient.
