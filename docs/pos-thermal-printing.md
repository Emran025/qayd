# POS thermal receipt printing status

## Current implementation boundary

Receipt content is formatted from the immutable posted invoice and its recorded payment snapshots. The formatter includes the invoice number and date, stored counterparty account ID when present, item names/quantities/prices, recorded discounts and taxes only when non-zero, total, paid amount, balance due, and recorded payment methods. A deferred balance is explicitly identified as credit due. Reprints receive a visible `إعادة طباعة` marker.

The print use case accepts only a posted sales invoice that is neither voided nor returned. It passes a printer-independent receipt layout to a single `PosReceiptPrinter` port. It does not depend on, call, or receive sale posting, payment posting, inventory movement, discount calculation, or accounting services. Reprinting is repeatable and does not mutate the invoice. Known platform failures are mapped to safe retry messages; unexpected exception text is not surfaced or logged.

The content model preserves right-to-left text and tells adapters to rasterize Arabic when native glyph support is not verified. The 58 mm (nominal 384-dot) and 80 mm (nominal 576-dot) layouts are software test targets only; those dot counts are not a hardware compatibility claim. PDF export/share remains the supported printing fallback.

## Physical hardware matrix — not yet tested

| OS/platform | Transport | Printer model / command language | Paper width | Physical result |
| --- | --- | --- | --- | --- |
| None selected | None selected | None selected | 58 mm target, unverified | Not tested |
| None selected | None selected | None selected | 80 mm target, unverified | Not tested |

No Bluetooth, USB, network, Android, iOS, desktop, or web printer support is claimed. No vendor plugin or platform permission path has been enabled because there is no selected device profile or hardware available to validate it.

## Required before enabling or merging hardware support

Select and test a concrete OS/device, transport, printer make/model and command language, and paper width. On that exact combination, verify permission granted/denied, successful connection, connection failure, timeout, disconnect during print, out-of-paper, retry, Arabic RTL and mixed digits, discounts/tax, partial payment and credit due, and safe reprint from invoice history. Confirm that a failed print never affects the saved sale, balances, stock or ledger, and that the repeat copy uses the saved invoice snapshot. Record the actual model and tested OS/transport here. Until that matrix is filled and CI passes, keep the default adapter unavailable and retain PDF/share as the only supported output.

## Known snapshot limitation

The current invoice stores a counterparty account ID but no counterparty display-name snapshot. The receipt therefore shows the stored ID rather than looking up a potentially changed account name. Adding historical name snapshots requires a separate persistence/data migration decision and is outside this hardware-free portion.
