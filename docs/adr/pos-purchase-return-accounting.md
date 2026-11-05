# POS purchase returns and supplier credits

**Status:** Accepted for the current POS accounting model

## Decision

A purchase return is a supplier credit note tied to a posted purchase invoice, not a cash refund. The credit note decreases the supplier payable (debit accounts payable). Stock leaves inventory at its current book carrying cost (credit inventory). Any difference between the supplier credit allocated from the original invoice and the carrying value removed is posted to the configured POS purchase-returns variance account. The supplier credit remains due/unapplied even when the original purchase was already paid; refunding cash is a separate, explicitly authorized settlement and is not performed by this workflow.

Returns are append-only and cumulative. A return must reference the exact source invoice and source lines, and may not exceed their remaining quantities or source value. Tracked items may only be returned from lots received on those original lines, and lot-level returns are capped by the unreturned receipt quantity. Invoice, supplier-credit postings, stock movements, source status, ledger entries, and the encrypted financial outbox/inbox journal are committed atomically and are idempotent on retry.

## Tax limitation and fail-closed behavior

The current POS purchase template has no mapped input-tax control account. The current purchase builder creates tax-free lines, but the invoice model can represent tax. A non-zero tax-bearing source therefore cannot be safely reversed without knowing whether that tax is recoverable and how it was posted. The purchase-return builder and SQLite transaction reject such sources before writing anything; inbound events are subject to the same database guard.

When tax support is added, the standard recommended treatment is to debit the supplier payable for the credit note, credit inventory for carrying cost, reverse recoverable input tax through its dedicated tax-control account, and post only the remaining genuine cost difference to purchase-return/price variance. The tax account and jurisdiction-specific recoverability rule must be configured before this path is enabled for taxable purchases.

## References

- [SPSCC Pressbooks: merchandise purchase returns under the perpetual inventory system](https://spscc.pressbooks.pub/spsccfinacctg/chapter/analyze-and-record-transactions-for-merchandise-purchases-using-the-perpetual-inventory-system/)
- [Lumen Learning: journal entries for inventory purchases and sales](https://courses.lumenlearning.com/suny-finaccounting/chapter/journal-entries-for-inventory-purchases-and-sales/)
- [IFRS: IAS 2 Inventories](https://www.ifrs.org/issued-standards/list-of-standards/ias-2-inventories/)
