# QAYD (قيد) : The Sovereign Financial Engine

<div align="center">
  <br>
  <b>Sovereign. Local-First. Cryptographically Governed. Mathematically Pure.</b>
  <br>
  <i>A double-entry accounting engine for personal finance and bilateral mediation.</i>
  <br>
</div>

---

> **Notice to System Auditors, Core Developers, and Principal Architects:**  
> Qayd is not a simple expense tracker. It is a highly opinionated, strictly governed financial engine. It categorically rejects the modern paradigm of cloud-hosted, softly typed, inherently imprecise financial platforms. Instead, it returns absolute data sovereignty to the user through mechanical enforcement, cryptographic identity, and an uncompromising adherence to formal accounting doctrine.
>
> This README serves as the high-level technical gateway to the application. For the complete ontological breakdown of every architectural constraint, you **must** read the comprehensive [System Philosophy & Accounting Doctrine](qayd_system_philosophy.md).

---

## 🏛 1. Foundational Architecture & Sovereignty

### The Local-First Imperative

Qayd is built on the declaration that financial records are a user’s absolute property. The database is stored exclusively on the user's device. The remote server is strictly a relay node for End-to-End Encrypted (E2EE) Sync Events—**the server is completely blind to your financial data.** It cannot post a debit. It cannot post a credit.

### Cryptographic Security & The Three-Factor Key

The application’s data is managed via `sqflite_sqlcipher`, encrypted with AES-256-CBC at the page level before writing to disk. The derivation of this database key is a strict three-factor process:

1. **The Mnemonic:** Your BIP-39 phrase (The user's exclusive property and final authority).
2. **Local Salt:** Device-bound cryptographic salt.
3. **Server Salt:** Provisioned upon registration.

There is **no administrative override**. If you lose your Mnemonic, your data is cryptographically inaccessible forever. Qayd guarantees privacy through structural impossibility of access by unauthorized parties.

### The Temporal Sentinel

Qayd integrates a Monotonic Clock Guard. Because precise temporal ordering is required for an immutable ledger, the system constantly samples NTP time and persists the UTC epoch. Rolling a system clock backward by more than 60 seconds triggers an immediate Tamper Detection lockdown.

---

## ⚖️ 2. The Monetary & Accounting Doctrine

Qayd is physically incapable of loose accounting. It subjects every transaction to mathematically infallible rigor.

### The Absolute Rejection of Floating-Point

Modern financial bugs stem from standard IEEE 754 precision errors. Qayd categorically rejects floating-point types (`double`). Every monetary value is represented by a strictly constrained `Money` object, stored as an `int` representing exact minor units (e.g., 100 minor units = 1.00 currency unit).

### The Currency Lock

Adding different currencies is mathematically invalid without introducing volatile, time-sensitive exchange rates. Qayd structurally prevents cross-currency arithmetic at the compiler/domain level. Any attempt to mathematically combine mismatching currencies throws a fatal `CurrencyMismatchException`.

### Pure Determinism: The Entry Generator

Ledger lines are never manually written. The `EntryGenerator` is a mathematically pure function with zero configuration switches. Given a `receipt` or `payment` Voucher, it strictly computes the balancing Debits and Credits and posts them natively.

* The accounting inequality $ΣDebit(T) = ΣCredit(T)$ is structurally built-in, not something audited retroactively.

### 10-Pillar Ontological Taxonomy

A user's financial ecosystem is constrained to exactly 10 permanent classifications (e.g., `liquidAssets`, `payables`, `personalExpenses`, `remittanceFees`). Account "natures" (Debit/Credit) are immutable upon creation, guaranteeing that historical data cannot be retroactively perverted via reclassification.

---

## 📜 3. The Voucher Protocol & Bilateral Commitments

In classical accounting, the document comes before the entry. In Qayd, a `Voucher` is the irreducible atom of financial reality. Ledger entries depend entirely upon Vouchers; Vouchers do not depend on Ledger entries.

### Cryptographic Signatures & Non-Repudiation

Bilateral agreements between parties are sealed using local `Ed25519` private keys. When Party A claims Party B owes them money, Party B must accept. This generates a `SignableReceipt`—a canonical byte-payload combining the amount, currency, parties, normalized date, and UUID. It is hashed via SHA-512 and signed, forming an irrefutable cryptographic commitment.

### Finite State Automaton

A voucher journeys through a rigid lifecycle automaton governed by strict transition laws:

* `Draft` ➔ `Confirmed` ➔ `Settled`
* *or* ➔ `Withdrawn` (Terminal State)

Transitions are one-way. A settled voucher cannot revert. Backward motion is fundamentally prohibited by unbypassable domain exceptions.

### The Conversational Epistemology of Debt

Disputes and negotiations over a voucher are handled gracefully. A `rejected` voucher can be superseded by a resubmitted "correction." Qayd maintains `originVoucherId` links to thread the entire history of a transaction negotiation. The ledger is treated as a chronological dialogue.

---

## 🌉 4. The Automated Bridge (Personal Finance)

While Qayd enforces brutal double-entry mechanics under the hood, the UX operates smoothly as an intuitive personal expense tracker. This is achieved via **The Automated Bridge**.

When managing day-to-day spending, all transactions automatically route through the singular **Root Liquid Assets** account (the system axiom). Qayd dynamically translates "I spent 100 on Groceries" into a synchronized two-voucher pipeline:

1. An external `Payment` (Cash routing out to a provider/shop).
2. An internal classification `Receipt` (Routing to your specific `personalExpenses` account).

This creates pristine, balanced double-entry accounting trails while requiring zero manual posting from the user.

---

## 📊 5. Dimensional Cost Centers & Analytics

Cost Centers in Qayd are strictly analytical metadata. The system creates a hard division between **Financial Accounting** (formal ledger balances) and **Management Accounting** (spending analytics).

* **Flat Topology:** Cost centers are leaves, not trees. They do not duplicate the Chart of Accounts hierarchy.
* **Cost vs. Profit Polarity:** A cost center is permanently defined as either a `cost` pool (consuming resources) or a `profit` pool (generating resources).
* **The Semantic Taxonomy:** The 11 core tracking dimensions (Income, Housing, Nutrition, Transportation, Education, Family, etc.) represent a formalized sociological structure of human spending prioritized inherently from survival needs down to discretionary lifestyle.

---

## 🔄 6. Tripartite Transfer Mediation (SWIFT-Protocol Analogy)

Qayd natively models complex financial mediation. Much like the correspondent banking architecture developed by SWIFT, Qayd permits a user to officially mediate a transfer: Party A ➔ You ➔ Party B.

* **Causal Ordering Locks (`isContingent`):** An intermediary's payout voucher leg is structurally, permanently locked until the receipt voucher leg successfully clears. A mediator simply cannot register a payout to Party B before the ledger confirms they have received the exact funds from Party A.
* **Fee Economics:** Mediators can charge service fees. If specified, Qayd auto-generates a dedicated Revenue account and a third-party fee `Receipt` voucher to mathematically reconcile the mediation spread.

---

## 💻 7. Architecture & Codebase Technology

Qayd employs a strict Clean Architecture pattern (`Domain` → `Application` → `Infrastructure` → `Presentation`) ensuring the financial models are completely isolated from the UI constraints.

* **Application Framework:** Flutter / Dart (Multi-platform Native)
* **Local Storage Provider:** `sqflite_sqlcipher` (Native AES-256 encrypted SQLite)
* **Security & Cryptography:** Ed25519 digital signatures, PBKDF2 stretch-keys, SHA-512 hashing, Monotonic system-clock guards.
* **Networking & Synchronization:** E2EE Event Payload Sync against blind-relay server nodes.

---

## 📑 8. Developer & Contributor Covenant

If you are modifying, extending, or auditing Qayd, you are bound by the following laws:

1. **You must internalize the philosophy:** No piece of code is arbitrary. Read the [System Philosophy & Accounting Doctrine](qayd_system_philosophy.md) before designing any feature.
2. **Honor Immutability:** Never expose `set` accessors or mutators on Domain Entities. Respect the distinction between factory methodologies like `restore` (rehydrating history) vs `draft` (passing semantic creation guards).
3. **Never Bypass the Engine:** The `EntryGenerator` is untouchable. Never attempt to write directly to the `ledger_entries` layer. All financial changes, without exception, must originate from a `Voucher` state transition representing a localized event in time.

#### *The integrity of the Qayd local ledger is absolute.*

> [!TIP]
> Production Android releases are built by `.github/workflows/build-release.yml` from a tag such as `v1.2.3` or `v1.2.3+45`. The workflow injects production values from GitHub Actions secrets, validates the signed APK, and publishes APK, AAB, debug symbols, and checksums. Do not commit production values or rely on `config_prod.json`; that file is intentionally ignored by Git. See [Android release deployment](docs/android-release-deployment.md) for the required repository configuration.
