import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/migrations/migration_registry.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/security/e2ee_envelope_format.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/mappers/pos_sale_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_purchase_return_sync_snapshot_codec.dart';
import 'package:qayd/data/repositories/device_sync_outbox_dao.dart';
import 'package:qayd/data/repositories/pos_financial_event_store.dart';
import 'package:qayd/data/repositories/sqlite_pos_financial_inbound_application_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_financial_outbound_posting_writer.dart';
import 'package:qayd/application/sync/pos_financial_outbound_event_preparer.dart';
import 'package:qayd/data/repositories/sqlite_pos_invoice_payment_collection_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_return_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_sale_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_sales_return_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_sync_inbound_event_journal_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_financial_apply_result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
import 'package:qayd/domain/entities/pos_financial_outbound_bundle.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/device_session.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/sync_node.dart';
import 'package:qayd/domain/repositories/sync_inbound_event_journal_repository.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/device_session_repository.dart';
import 'package:qayd/domain/services/e2ee_encryption_service.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/digital_signature.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _CurrencyRepository implements CurrencyRepository {
  _CurrencyRepository(this.currency);

  final CurrencyCode currency;

  @override
  Future<Result<CurrencyCode?>> getByCode(String code) async =>
      Success(code == currency.code ? currency : null);

  @override
  Future<Result<List<CurrencyCode>>> getAll({bool onlyActive = false}) async =>
      Success([currency]);

  @override
  Future<Result<void>> save(
    CurrencyCode currency, {
    bool isPredefined = false,
  }) async => const Success(null);

  @override
  Future<Result<void>> toggleActiveStatus(String code, bool isActive) async =>
      const Success(null);

  @override
  Future<Result<String>> getBaseCurrencyCode() async => Success(currency.code);

  @override
  Future<Result<void>> setBaseCurrencyCode(String code) async =>
      const Success(null);
}

final class _TestDeviceSessionRepository implements DeviceSessionRepository {
  _TestDeviceSessionRepository(this.sessions);

  final List<DeviceSession> sessions;

  @override
  Future<void> upsert(DeviceSession session) async =>
      throw UnimplementedError();

  @override
  Future<List<DeviceSession>> listAll() async => sessions;

  @override
  Future<List<DeviceSession>> listActive() async =>
      sessions.where((session) => session.isActive).toList(growable: false);

  @override
  Future<DeviceSession?> getById(String deviceId) async {
    for (final session in sessions) {
      if (session.deviceId == deviceId) return session;
    }
    return null;
  }

  @override
  Future<void> setActive(String deviceId, bool isActive) async =>
      throw UnimplementedError();

  @override
  Future<void> updateLastSyncSeq(String deviceId, int lastSyncSeq) async =>
      throw UnimplementedError();

  @override
  Future<void> updateLastSeen(String deviceId, DateTime at) async =>
      throw UnimplementedError();
}

final class _RecordingE2EEEncryptionService implements E2EEEncryptionService {
  final receiverPublicKeys = <String>[];
  final rawPayloads = <Map<String, dynamic>>[];

  @override
  Future<String> encryptPayload({
    required Map<String, dynamic> rawPayload,
    required CryptoKeyPair senderKeyPair,
    required String receiverPublicKeyHex,
    required String nodeId,
    required String eventType,
  }) async {
    receiverPublicKeys.add(receiverPublicKeyHex);
    rawPayloads.add(rawPayload);
    return jsonEncode({
      'version': E2EEEnvelopeFormat.version,
      'algorithm': E2EEEnvelopeFormat.algorithm,
      'node_id': nodeId,
      'event_type': eventType,
      'sender_public_key': senderKeyPair.publicKeyHex,
      'recipient_public_key': receiverPublicKeyHex,
      'ciphertext': base64Encode(utf8.encode(jsonEncode(rawPayload))),
      'signature': 'valid-test-signature',
    });
  }

  @override
  Future<Map<String, dynamic>> decryptPayload({
    required String encryptedPayload,
    required CryptoKeyPair receiverKeyPair,
    required String senderPublicKeyHex,
    required String nodeId,
    required String eventType,
  }) async => throw UnimplementedError();

  @override
  bool verifySignerAuthenticity({
    required Map<String, dynamic> decryptedPayload,
    required String senderPublicKeyHex,
    required DigitalSignature signature,
  }) => false;
}

final _currency = CurrencyCode(
  code: 'SAR',
  nameAr: 'ريال سعودي',
  symbol: 'ر.س',
);

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      nature TEXT NOT NULL,
      parent_id TEXT,
      is_default INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      standard_classification TEXT,
      custom_classification_name TEXT,
      custom_classification_nature TEXT,
      metadata TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE vouchers (
      id TEXT PRIMARY KEY, type TEXT NOT NULL, reference_number TEXT,
      date TEXT NOT NULL, amount_minor INTEGER NOT NULL, currency_code TEXT NOT NULL,
      counterparty_id TEXT NOT NULL, affected_account_id TEXT NOT NULL,
      state TEXT NOT NULL, description TEXT, notes TEXT, tags_json TEXT NOT NULL,
      attachments_json TEXT NOT NULL, created_at TEXT NOT NULL, confirmed_at TEXT,
      settled_at TEXT, signer_phone TEXT, canonical_sender_phone TEXT,
      canonical_receiver_phone TEXT, transfer_group_id TEXT, tripartite_role TEXT,
      linked_party_id TEXT, mediator_account_id TEXT, fee_amount_minor INTEGER,
      is_contingent INTEGER NOT NULL DEFAULT 0, origin_voucher_id TEXT,
      rejection_reason TEXT, withdrawn_at TEXT, sender_status TEXT NOT NULL,
      receiver_status TEXT NOT NULL, sender_signature_hex TEXT,
      receiver_signature_hex TEXT, sender_public_key_hex TEXT,
      receiver_public_key_hex TEXT, lifecycle_status TEXT NOT NULL,
      is_inbound INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE ledger_entries (
      id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL, account_id TEXT NOT NULL,
      side TEXT NOT NULL, amount_minor INTEGER NOT NULL, currency_code TEXT NOT NULL,
      voucher_id TEXT NOT NULL, date TEXT NOT NULL, created_at TEXT NOT NULL
    )
  ''');
  await Migration040PosFoundation().up(db);
  await Migration041PosInvoiceMetadata().up(db);
  await MigrationRegistry.applyFromTo(
    db,
    fromVersion: 41,
    toVersion: MigrationRegistry.ordered.last.version,
  );
}

Future<void> _seed(Database db) async {
  await db.insert('pos_warehouses', {
    'id': 'warehouse-1',
    'code': 'POS-MAIN',
    'name': 'POS Main',
    'is_default': 1,
    'is_active': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  });
  await db.insert('pos_products', {
    'id': 'product-1',
    'sku': 'SKU-1',
    'name': 'Coffee',
    'unit_name': 'unit',
    'currency_code': _currency.code,
    'sale_price_minor': 500,
    'purchase_price_minor': 100,
    'quantity_scale': 0,
    'reorder_level_scaled': 0,
    'expiry_tracking': 0,
    'is_active': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  });
  for (final id in ['cash', 'revenue', 'cogs', 'inventory']) {
    await db.insert('accounts', {
      'id': id,
      'name': id,
      'nature': id == 'revenue' ? 'credit' : 'debit',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
  }
}

PosStockMovement _opening() => PosStockMovement.create(
  id: 'opening-1',
  productId: 'product-1',
  warehouseId: 'warehouse-1',
  type: PosStockMovementType.opening,
  direction: PosStockMovementDirection.inbound,
  quantity: PosQuantity.whole(5),
  unitCost: Money.fromMinorUnits(100, _currency),
  sourceType: 'opening',
  sourceId: 'opening-1',
  occurredAt: DateTime.utc(2026, 1, 1, 9),
  idempotencyKey: 'opening-key',
  createdAt: DateTime.utc(2026, 1, 1, 9),
);

PosAccountingPosting _posting({
  required String voucherId,
  required String invoiceId,
  required String transactionId,
  required String debitEntryId,
  required String creditEntryId,
  required VoucherType type,
  required String counterpartyId,
  required String affectedAccountId,
  required int amount,
  required DateTime date,
}) {
  final voucher = Voucher.draft(
    id: VoucherId(voucherId),
    type: type,
    date: date,
    amount: Money.fromMinorUnits(amount, _currency),
    currency: _currency,
    counterpartyId: AccountId(counterpartyId),
    affectedAccountId: AccountId(affectedAccountId),
    referenceNumber: invoiceId,
    description: 'POS sale',
    createdAt: date,
  ).confirm(date);
  final entries = EntryGenerator().generateForConfirmedVoucher(
    voucher: voucher,
    transactionId: TransactionId(transactionId),
    debitEntryId: EntryId(debitEntryId),
    creditEntryId: EntryId(creditEntryId),
    ledgerCreatedAt: date,
  );
  return PosAccountingPosting(
    sourceId: invoiceId,
    voucher: voucher,
    entries: entries,
  );
}

PosSalePosting _sale({
  bool invalidCogs = false,
  bool tracked = false,
  String productId = 'product-1',
  String? lotId,
  int quantity = 1,
  List<PosStockMovement>? stockMovements,
}) {
  final date = DateTime.utc(2026, 1, 1, 10);
  const invoiceId = 'invoice-1';
  final salesAmount = quantity * 500;
  final cogsAmount = quantity * 100;
  final line = PosInvoiceLine.create(
    id: 'line-1',
    invoiceId: invoiceId,
    productId: productId,
    productNameSnapshot: 'Coffee',
    barcodeSnapshot: '6290001',
    quantity: PosQuantity.whole(quantity),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    createdAt: date,
    expiryTrackingSnapshot: tracked,
  );
  final invoice = PosInvoice.draft(
    id: invoiceId,
    invoiceNumber: 'S-000001',
    type: PosInvoiceType.sale,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    idempotencyKey: 'sale-key-1',
    invoiceDate: date,
    now: date,
  ).post(date);
  return PosSalePosting(
    invoice: invoice,
    movements:
        stockMovements ??
        [
          PosStockMovement.create(
            id: 'sale-movement-1',
            productId: productId,
            warehouseId: 'warehouse-1',
            type: PosStockMovementType.sale,
            direction: PosStockMovementDirection.outbound,
            quantity: PosQuantity.whole(quantity),
            unitCost: Money.fromMinorUnits(100, _currency),
            sourceType: 'pos_invoice',
            sourceId: invoiceId,
            sourceLineId: 'line-1',
            lotId: lotId,
            occurredAt: date,
            idempotencyKey: 'sale-stock-key-1',
            createdAt: date,
          ),
        ],
    postings: [
      _posting(
        voucherId: 'sale-voucher-1',
        invoiceId: invoiceId,
        transactionId: 'sale-tx-1',
        debitEntryId: 'sale-debit-1',
        creditEntryId: 'sale-credit-1',
        type: VoucherType.receipt,
        counterpartyId: 'revenue',
        affectedAccountId: 'cash',
        amount: salesAmount,
        date: date,
      ),
      _posting(
        voucherId: 'cogs-voucher-1',
        invoiceId: invoiceId,
        transactionId: 'cogs-tx-1',
        // Force a ledger primary-key conflict after the second voucher write.
        debitEntryId: invalidCogs ? 'sale-debit-1' : 'cogs-debit-1',
        creditEntryId: invalidCogs ? 'sale-credit-1' : 'cogs-credit-1',
        type: VoucherType.payment,
        counterpartyId: 'cogs',
        affectedAccountId: 'inventory',
        amount: cogsAmount,
        date: date,
      ),
    ],
    payments: const [],
  );
}

({
  PosPurchaseReturnPosting posting,
  PosInvoice source,
  PosStockMovement sourceMovement,
})
_purchaseReturn() {
  final date = DateTime.utc(2026, 1, 1, 10);
  final sourceLine = PosInvoiceLine.create(
    id: 'purchase-line-1',
    invoiceId: 'purchase-invoice-1',
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(2),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    createdAt: date,
    expiryTrackingSnapshot: false,
  );
  final source = PosInvoice.draft(
    id: 'purchase-invoice-1',
    invoiceNumber: 'P-000001',
    type: PosInvoiceType.purchase,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [sourceLine],
    idempotencyKey: 'purchase-key-1',
    invoiceDate: date,
    now: date,
    counterpartyAccountId: AccountId('supplier'),
  ).post(date);
  final sourceMovement = PosStockMovement.create(
    id: 'purchase-movement-1',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.purchase,
    direction: PosStockMovementDirection.inbound,
    quantity: PosQuantity.whole(2),
    unitCost: Money.fromMinorUnits(100, _currency),
    sourceType: 'pos_invoice',
    sourceId: source.id,
    sourceLineId: sourceLine.id,
    occurredAt: date,
    idempotencyKey: 'purchase-movement-key-1',
    createdAt: date,
  );
  final returnLine = PosInvoiceLine.create(
    id: 'purchase-return-1:line:0',
    invoiceId: 'purchase-return-1',
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(1),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    sourceLineId: sourceLine.id,
    createdAt: date,
    expiryTrackingSnapshot: false,
  );
  final invoice = PosInvoice.draft(
    id: 'purchase-return-1',
    invoiceNumber: 'PR-000001',
    type: PosInvoiceType.purchaseReturn,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [returnLine],
    idempotencyKey: 'purchase-return-key-1',
    invoiceDate: date,
    now: date,
    counterpartyAccountId: AccountId('supplier'),
    sourceInvoiceId: source.id,
  ).post(date);
  final inventoryPosting = _posting(
    voucherId: 'purchase-return-voucher-inventory',
    invoiceId: invoice.id,
    transactionId: 'purchase-return-tx-inventory',
    debitEntryId: 'purchase-return-debit-inventory',
    creditEntryId: 'purchase-return-credit-inventory',
    type: VoucherType.payment,
    counterpartyId: 'payables',
    affectedAccountId: 'inventory',
    amount: 100,
    date: date,
  );
  final variancePosting = _posting(
    voucherId: 'purchase-return-voucher-variance',
    invoiceId: invoice.id,
    transactionId: 'purchase-return-tx-variance',
    debitEntryId: 'purchase-return-debit-variance',
    creditEntryId: 'purchase-return-credit-variance',
    type: VoucherType.payment,
    counterpartyId: 'payables',
    affectedAccountId: 'purchase-returns',
    amount: 400,
    date: date,
  );
  final movement = PosStockMovement.create(
    id: 'purchase-return-movement-1',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.purchaseReturn,
    direction: PosStockMovementDirection.outbound,
    quantity: PosQuantity.whole(1),
    unitCost: Money.fromMinorUnits(100, _currency),
    sourceType: 'pos_invoice',
    sourceId: invoice.id,
    sourceLineId: returnLine.id,
    reversesSourceId: source.id,
    occurredAt: date,
    idempotencyKey: 'purchase-return-stock-key-1',
    createdAt: date,
  );
  return (
    posting: PosPurchaseReturnPosting(
      invoice: invoice,
      sourceInvoiceId: source.id,
      supplierPayablesAccountId: AccountId('payables'),
      inventoryAccountId: AccountId('inventory'),
      purchaseReturnsAccountId: AccountId('purchase-returns'),
      movements: [movement],
      postings: [inventoryPosting, variancePosting],
      reason: 'supplier credit note',
    ),
    source: source,
    sourceMovement: sourceMovement,
  );
}

PosFinancialOutboundBundle _outboundBundleForSale(PosSalePosting posting) {
  final invoice = posting.invoice;
  final event = PosFinancialSyncEvent.decode(
    jsonEncode({
      'version': 2,
      'kind': 'sale',
      'owner_user_id': 7,
      'source_device_id': 'device-a',
      'target_device_id': 'device-a',
      'event_id': invoice.id,
      'aggregate_id': invoice.id,
      'idempotency_key': invoice.idempotencyKey,
      'currency_code': invoice.currency.code,
      'occurred_at': invoice.invoiceDate.toUtc().toIso8601String(),
      'total_minor': invoice.total.minorUnits,
      'lines': invoice.lines
          .map(
            (line) => {
              'product_id': line.productId,
              'quantity_scaled': line.quantity.scaledUnits,
              'quantity_scale': line.quantity.scale,
              'unit_price_minor': line.unitPrice.minorUnits,
              'total_minor': line.lineTotal.minorUnits,
            },
          )
          .toList(),
      'snapshot': PosSaleSyncSnapshotCodec.encode(posting),
    }),
  );
  final createdAt = DateTime.utc(2026, 11, 5);
  final deliveries = ['device-b', 'device-c']
      .map((target) {
        final ciphertext = 'encrypted-for-$target';
        return PosFinancialOutboundDelivery(
          nodeId: 'node-${invoice.id}-$target',
          eventType: SyncEventType.posSale.name,
          targetDeviceId: target,
          encryptedPayload: ciphertext,
          signature: base64Encode(utf8.encode('$target|$ciphertext')),
          createdAt: createdAt,
        );
      })
      .toList(growable: false);
  return PosFinancialOutboundBundle(
    event: event,
    localEncryptedPayload: 'encrypted-local-copy',
    deliveries: deliveries,
  );
}

PosFinancialOutboundBundle _outboundBundleForPurchaseReturn(
  PosPurchaseReturnPosting posting,
) {
  final invoice = posting.invoice;
  final event = PosFinancialSyncEvent.fromJson({
    'version': 2,
    'kind': 'purchaseReturn',
    'owner_user_id': 7,
    'source_device_id': 'device-a',
    'target_device_id': 'device-a',
    'event_id': invoice.id,
    'aggregate_id': invoice.id,
    'idempotency_key': invoice.idempotencyKey,
    'currency_code': invoice.currency.code,
    'occurred_at': invoice.invoiceDate.toUtc().toIso8601String(),
    'total_minor': invoice.total.minorUnits,
    'lines': invoice.lines
        .map(
          (line) => {
            'product_id': line.productId,
            'quantity_scaled': line.quantity.scaledUnits,
            'quantity_scale': line.quantity.scale,
            'unit_price_minor': line.unitPrice.minorUnits,
            'total_minor': line.lineTotal.minorUnits,
          },
        )
        .toList(),
    'snapshot': PosPurchaseReturnSyncSnapshotCodec.encode(posting),
  });
  final createdAt = DateTime.utc(2026, 11, 5);
  final deliveries = ['device-b', 'device-c']
      .map((target) {
        final ciphertext = 'encrypted-for-$target';
        return PosFinancialOutboundDelivery(
          nodeId: 'node-${invoice.id}-$target',
          eventType: SyncEventType.posPurchaseReturn.name,
          targetDeviceId: target,
          encryptedPayload: ciphertext,
          signature: base64Encode(utf8.encode('$target|$ciphertext')),
          createdAt: createdAt,
        );
      })
      .toList(growable: false);
  return PosFinancialOutboundBundle(
    event: event,
    localEncryptedPayload: 'encrypted-local-copy',
    deliveries: deliveries,
  );
}

PosFinancialSyncEvent _inboundEventForSale(PosSalePosting posting) {
  final raw = _outboundBundleForSale(posting).event.toJson();
  raw['target_device_id'] = 'device-b';
  return PosFinancialSyncEvent.fromJson(raw);
}

void main() {
  sqfliteFfiInit();

  group('PosFinancialOutboundEventPreparer', () {
    test(
      'seals the POS event for each paired device with stable routing',
      () async {
        final keyPair = CryptoKeyPair.fromHex(
          privateKeyHex: List.filled(64, '11').join(),
          publicKeyHex: List.filled(32, 'aa').join(),
        );
        final currentSession = DeviceSession(
          deviceId: 'device-a',
          publicKeyHex: keyPair.publicKeyHex,
          pairedAt: DateTime.utc(2026, 1, 1),
          lastSyncSeq: 0,
          isCurrent: true,
        );
        final targetSession = DeviceSession(
          deviceId: 'device-b',
          publicKeyHex: List.filled(32, 'bb').join(),
          pairedAt: DateTime.utc(2026, 1, 2),
          lastSyncSeq: 0,
          role: 'companion',
        );
        final sessions = _TestDeviceSessionRepository([
          currentSession,
          targetSession,
        ]);
        final encryption = _RecordingE2EEEncryptionService();
        final preparer = PosFinancialOutboundEventPreparer(
          deviceSessionRepository: sessions,
          encryptionService: encryption,
          getCurrentUserKeyPair: () async => keyPair,
          ownerUserId: 7,
          currentDeviceId: 'device-a',
        );

        final first = await preparer.prepareSale(_sale());
        final replay = await preparer.prepareSale(_sale());

        expect(first, isNotNull);
        expect(replay, isNotNull);
        expect(first!.deliveries, hasLength(1));
        expect(first.deliveries.single.targetDeviceId, 'device-b');
        expect(first.deliveries.single.eventType, SyncEventType.posSale.name);
        expect(encryption.rawPayloads, hasLength(4));
        expect(encryption.receiverPublicKeys, [
          keyPair.publicKeyHex,
          targetSession.publicKeyHex,
          keyPair.publicKeyHex,
          targetSession.publicKeyHex,
        ]);
        expect(encryption.rawPayloads[1]['source_device_id'], 'device-a');
        expect(encryption.rawPayloads[1]['target_device_id'], 'device-b');
        expect(
          E2EEEnvelopeFormat.isSupported(first.localEncryptedPayload),
          isTrue,
        );
        expect(
          E2EEEnvelopeFormat.isSupported(
            first.deliveries.single.encryptedPayload,
          ),
          isTrue,
        );
        expect(
          first.deliveries.single.signature,
          base64Encode(
            utf8.encode(
              '${first.deliveries.single.targetDeviceId}|'
              '${first.deliveries.single.encryptedPayload}',
            ),
          ),
        );
        expect(
          replay!.deliveries.single.nodeId,
          first.deliveries.single.nodeId,
        );
      },
    );

    test(
      'does not create a device event when there is no paired target',
      () async {
        final keyPair = CryptoKeyPair.fromHex(
          privateKeyHex: List.filled(64, '11').join(),
          publicKeyHex: List.filled(32, 'aa').join(),
        );
        final sessions = _TestDeviceSessionRepository([
          DeviceSession(
            deviceId: 'device-a',
            publicKeyHex: keyPair.publicKeyHex,
            pairedAt: DateTime.utc(2026, 1, 1),
            lastSyncSeq: 0,
            isCurrent: true,
          ),
        ]);
        final encryption = _RecordingE2EEEncryptionService();
        final preparer = PosFinancialOutboundEventPreparer(
          deviceSessionRepository: sessions,
          encryptionService: encryption,
          getCurrentUserKeyPair: () async => keyPair,
          ownerUserId: 7,
          currentDeviceId: 'device-a',
        );

        expect(await preparer.prepareSale(_sale()), isNull);
        expect(encryption.rawPayloads, isEmpty);
      },
    );
  });

  group('SqlitePosSalePostingRepository', () {
    late Database db;
    late SqlitePosStockMovementRepository stockRepository;
    late SqlitePosSalePostingRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await _createSchema(db);
      await _seed(db);
      final currencyRepository = _CurrencyRepository(_currency);
      stockRepository = SqlitePosStockMovementRepository(
        db,
        currencyRepository,
      );
      final voucherRepository = SqliteVoucherRepository(
        db,
        DatabaseTransactionRunner(db),
      );
      repository = SqlitePosSalePostingRepository(
        DatabaseTransactionRunner(db),
        stockRepository,
        voucherRepository,
      );
      expect((await stockRepository.append(_opening())).isSuccess, isTrue);
    });

    tearDown(() => db.close());

    test(
      'commits invoice, lines, stock, vouchers, ledger, and payments atomically',
      () async {
        final result = await repository.saveAtomically(_sale());

        expect(result.isSuccess, isTrue);
        expect((await db.query('pos_invoices')), hasLength(1));
        expect((await db.query('pos_invoice_lines')), hasLength(1));
        expect((await db.query('pos_stock_movements')), hasLength(2));
        expect((await db.query('vouchers')), hasLength(2));
        expect((await db.query('ledger_entries')), hasLength(4));
      },
    );

    test('persists a multi-lot tracked sale and replays it exactly', () async {
      await db.insert('pos_products', <String, Object?>{
        'id': 'product-2',
        'sku': 'SKU-2',
        'name': 'Tracked coffee',
        'unit_name': 'unit',
        'currency_code': _currency.code,
        'sale_price_minor': 500,
        'purchase_price_minor': 100,
        'quantity_scale': 0,
        'reorder_level_scaled': 0,
        'expiry_tracking': 1,
        'is_active': 1,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      Future<void> receiveLot({
        required String id,
        required PosDate expiryDate,
        required int quantity,
      }) async {
        final receivedAt = DateTime.utc(2026, 1, 1, 9);
        final lot = PosStockLot.create(
          id: id,
          productId: 'product-2',
          warehouseId: 'warehouse-1',
          supplierLotNumber: 'SUP-$id',
          expiryDate: expiryDate,
          receivedQuantity: PosQuantity.whole(quantity),
          unitCost: Money.fromMinorUnits(100, _currency),
          createdAt: receivedAt,
        );
        expect(
          (await stockRepository.createLotInTransaction(db, lot)).isSuccess,
          isTrue,
        );
        final receipt = await stockRepository.append(
          PosStockMovement.create(
            id: '$id:receipt',
            productId: 'product-2',
            warehouseId: 'warehouse-1',
            type: PosStockMovementType.purchase,
            direction: PosStockMovementDirection.inbound,
            quantity: PosQuantity.whole(quantity),
            unitCost: Money.fromMinorUnits(100, _currency),
            sourceType: 'test',
            sourceId: '$id:receipt',
            lotId: lot.id,
            occurredAt: receivedAt,
            idempotencyKey: '$id:receipt-key',
            createdAt: receivedAt,
          ),
        );
        expect(
          receipt.isSuccess,
          isTrue,
          reason: receipt.failureOrNull?.messageAr,
        );
      }

      const earlierLotId = 'product-2-lot-early';
      const laterLotId = 'product-2-lot-late';
      await receiveLot(
        id: earlierLotId,
        expiryDate: PosDate.fromParts(2099, 12, 31),
        quantity: 2,
      );
      await receiveLot(
        id: laterLotId,
        expiryDate: PosDate.fromParts(2100, 1, 15),
        quantity: 2,
      );
      final sale = _sale(
        tracked: true,
        productId: 'product-2',
        quantity: 3,
        stockMovements: [
          PosStockMovement.create(
            id: 'sale-movement-1',
            productId: 'product-2',
            warehouseId: 'warehouse-1',
            type: PosStockMovementType.sale,
            direction: PosStockMovementDirection.outbound,
            quantity: PosQuantity.whole(2),
            unitCost: Money.fromMinorUnits(100, _currency),
            sourceType: 'pos_invoice',
            sourceId: 'invoice-1',
            sourceLineId: 'line-1',
            lotId: earlierLotId,
            occurredAt: DateTime.utc(2026, 1, 1, 10),
            idempotencyKey: 'sale-stock-key-1',
            createdAt: DateTime.utc(2026, 1, 1, 10),
          ),
          PosStockMovement.create(
            id: 'sale-movement-2',
            productId: 'product-2',
            warehouseId: 'warehouse-1',
            type: PosStockMovementType.sale,
            direction: PosStockMovementDirection.outbound,
            quantity: PosQuantity.whole(1),
            unitCost: Money.fromMinorUnits(100, _currency),
            sourceType: 'pos_invoice',
            sourceId: 'invoice-1',
            sourceLineId: 'line-1',
            lotId: laterLotId,
            occurredAt: DateTime.utc(2026, 1, 1, 10),
            idempotencyKey: 'sale-stock-key-2',
            createdAt: DateTime.utc(2026, 1, 1, 10),
          ),
        ],
      );

      final first = await repository.saveAtomically(sale);
      final replay = await repository.saveAtomically(sale);

      expect(first.isSuccess, isTrue, reason: first.failureOrNull?.messageAr);
      expect(replay.isSuccess, isTrue, reason: replay.failureOrNull?.messageAr);
      final saleMovements = await db.query(
        'pos_stock_movements',
        where: 'movement_type = ? AND product_id = ?',
        whereArgs: ['sale', 'product-2'],
        orderBy: 'id ASC',
      );
      expect(saleMovements, hasLength(2));
      expect(saleMovements.map((row) => row['lot_id']), [
        earlierLotId,
        laterLotId,
      ]);
      expect(saleMovements.map((row) => row['quantity_scaled']), [-2, -1]);
      expect(
        (await db.query(
          'pos_stock_lots',
          orderBy: 'id ASC',
        )).map((row) => row['remaining_quantity_scaled']),
        [0, 1],
      );
      expect(
        (await db.query(
          'pos_invoice_lines',
        )).single['expiry_tracking_snapshot'],
        1,
      );
      expect(
        await db.query(
          'pos_stock_movements',
          where: 'product_id = ?',
          whereArgs: ['product-2'],
        ),
        hasLength(4),
      );
    });

    test('replays exact sale without changing persisted rows', () async {
      final sale = _sale();
      expect((await repository.saveAtomically(sale)).isSuccess, isTrue);
      final beforeInvoices = await db.query('pos_invoices');
      final beforeLines = await db.query('pos_invoice_lines');
      final beforeStock = await db.query(
        'pos_stock_movements',
        orderBy: 'id ASC',
      );
      final beforeVouchers = await db.query('vouchers', orderBy: 'id ASC');
      final beforeLedger = await db.query('ledger_entries', orderBy: 'id ASC');

      final replay = await repository.saveAtomically(sale);

      expect(replay.isSuccess, isTrue);
      expect(await db.query('pos_invoices'), equals(beforeInvoices));
      expect(await db.query('pos_invoice_lines'), equals(beforeLines));
      expect(
        await db.query('pos_stock_movements', orderBy: 'id ASC'),
        equals(beforeStock),
      );
      expect(
        await db.query('vouchers', orderBy: 'id ASC'),
        equals(beforeVouchers),
      );
      expect(
        await db.query('ledger_entries', orderBy: 'id ASC'),
        equals(beforeLedger),
      );
    });

    test(
      'rolls back stock and invoice when a voucher write is invalid',
      () async {
        final result = await repository.saveAtomically(
          _sale(invalidCogs: true),
        );

        expect(result.isFailure, isTrue);
        expect((await db.query('pos_invoices')), isEmpty);
        expect((await db.query('pos_invoice_lines')), isEmpty);
        expect((await db.query('pos_stock_movements')), hasLength(1));
        expect((await db.query('vouchers')), isEmpty);
        expect((await db.query('ledger_entries')), isEmpty);
      },
    );

    test('fails closed for a partial invoice state', () async {
      final sale = _sale();
      await db.insert('pos_invoices', PosInvoiceMapper.toRow(sale.invoice));

      final result = await repository.saveAtomically(sale);

      expect(result.isFailure, isTrue);
      expect((await db.query('pos_invoices')), hasLength(1));
      expect((await db.query('pos_stock_movements')), hasLength(1));
      expect((await db.query('vouchers')), isEmpty);
    });

    test('rejects changed payload under an existing idempotency key', () async {
      final sale = _sale();
      await db.insert('pos_invoices', PosInvoiceMapper.toRow(sale.invoice));
      final changed = PosSalePosting(
        invoice: PosInvoice.draft(
          id: sale.invoice.id,
          invoiceNumber: sale.invoice.invoiceNumber,
          type: PosInvoiceType.sale,
          warehouseId: sale.invoice.warehouseId,
          currency: _currency,
          lines: sale.invoice.lines,
          idempotencyKey: sale.invoice.idempotencyKey,
          invoiceDate: sale.invoice.invoiceDate,
          now: sale.invoice.createdAt,
        ).post(sale.invoice.invoiceDate),
        movements: sale.movements,
        postings: sale.postings,
        payments: const [],
      );

      final result = await repository.saveAtomically(changed);
      expect(result.isFailure, isTrue);
      expect((await db.query('pos_stock_movements')), hasLength(1));
    });

    test(
      'commits a sale and encrypted device deliveries exactly once',
      () async {
        final runner = DatabaseTransactionRunner(db);
        final voucherRepository = SqliteVoucherRepository(db, runner);
        for (final deviceId in ['device-b', 'device-c']) {
          await db.insert('device_sessions', {
            'device_id': deviceId,
            'public_key_hex': 'a' * 64,
            'paired_at': DateTime.utc(2026, 1, 1).toIso8601String(),
          });
        }
        final writer = SqlitePosFinancialOutboundPostingWriter(
          transactionRunner: runner,
          eventStore: PosFinancialEventStore(db),
          deviceSyncOutboxDao: DeviceSyncOutboxDao(db),
          saleRepository: repository,
          purchaseRepository: SqlitePosPurchasePostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          salesReturnRepository: SqlitePosSalesReturnPostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          purchaseReturnRepository: SqlitePosPurchaseReturnPostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          collectionRepository: SqlitePosInvoicePaymentCollectionRepository(
            runner,
            voucherRepository,
          ),
        );
        final posting = _sale();
        final bundle = _outboundBundleForSale(posting);

        final first = await writer.saveSaleWithOutboundAtomically(
          posting,
          bundle,
        );
        final replay = await writer.saveSaleWithOutboundAtomically(
          posting,
          bundle,
        );

        expect(first.isSuccess, isTrue);
        expect(replay.isSuccess, isTrue);
        expect(await db.query('pos_invoices'), hasLength(1));
        expect(await db.query('pos_stock_movements'), hasLength(2));
        expect(await db.query('pos_financial_event_outbox'), hasLength(1));
        expect(await db.query('device_sync_outbox'), hasLength(2));
      },
    );

    test(
      'commits purchase return, accounting, and encrypted device deliveries once',
      () async {
        final runner = DatabaseTransactionRunner(db);
        final voucherRepository = SqliteVoucherRepository(db, runner);
        for (final id in ['supplier', 'payables', 'purchase-returns']) {
          await db.insert('accounts', {
            'id': id,
            'name': id,
            'nature': id == 'supplier' ? 'credit' : 'debit',
            'created_at': '2026-01-01T00:00:00.000Z',
          });
        }
        for (final deviceId in ['device-b', 'device-c']) {
          await db.insert('device_sessions', {
            'device_id': deviceId,
            'public_key_hex': 'a' * 64,
            'paired_at': DateTime.utc(2026, 1, 1).toIso8601String(),
          });
        }
        final fixture = _purchaseReturn();
        await db.insert('pos_invoices', PosInvoiceMapper.toRow(fixture.source));
        await db.insert(
          'pos_invoice_lines',
          PosInvoiceMapper.lineToRow(fixture.source.lines.single),
        );
        final sourceStock = await stockRepository.append(
          fixture.sourceMovement,
        );
        expect(sourceStock.isSuccess, isTrue);
        final purchaseReturnRepository =
            SqlitePosPurchaseReturnPostingRepository(
              runner,
              stockRepository,
              voucherRepository,
            );
        final writer = SqlitePosFinancialOutboundPostingWriter(
          transactionRunner: runner,
          eventStore: PosFinancialEventStore(db),
          deviceSyncOutboxDao: DeviceSyncOutboxDao(db),
          saleRepository: repository,
          purchaseRepository: SqlitePosPurchasePostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          salesReturnRepository: SqlitePosSalesReturnPostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          purchaseReturnRepository: purchaseReturnRepository,
          collectionRepository: SqlitePosInvoicePaymentCollectionRepository(
            runner,
            voucherRepository,
          ),
        );
        final bundle = _outboundBundleForPurchaseReturn(fixture.posting);

        final first = await writer.savePurchaseReturnWithOutboundAtomically(
          fixture.posting,
          bundle,
        );
        final replay = await writer.savePurchaseReturnWithOutboundAtomically(
          fixture.posting,
          bundle,
        );

        expect(first.isSuccess, isTrue);
        expect(replay.isSuccess, isTrue);
        expect(await db.query('pos_invoices'), hasLength(2));
        expect(await db.query('pos_returns'), hasLength(1));
        expect(await db.query('pos_stock_movements'), hasLength(3));
        expect(await db.query('pos_payments'), isEmpty);
        expect(await db.query('vouchers'), hasLength(2));
        expect(await db.query('ledger_entries'), hasLength(4));
        expect(await db.query('pos_financial_event_outbox'), hasLength(1));
        expect(await db.query('device_sync_outbox'), hasLength(2));
      },
    );

    test('rolls back financial outbox when local posting fails', () async {
      final runner = DatabaseTransactionRunner(db);
      final voucherRepository = SqliteVoucherRepository(db, runner);
      for (final deviceId in ['device-b', 'device-c']) {
        await db.insert('device_sessions', {
          'device_id': deviceId,
          'public_key_hex': 'a' * 64,
          'paired_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        });
      }
      final writer = SqlitePosFinancialOutboundPostingWriter(
        transactionRunner: runner,
        eventStore: PosFinancialEventStore(db),
        deviceSyncOutboxDao: DeviceSyncOutboxDao(db),
        saleRepository: repository,
        purchaseRepository: SqlitePosPurchasePostingRepository(
          runner,
          stockRepository,
          voucherRepository,
        ),
        salesReturnRepository: SqlitePosSalesReturnPostingRepository(
          runner,
          stockRepository,
          voucherRepository,
        ),
        purchaseReturnRepository: SqlitePosPurchaseReturnPostingRepository(
          runner,
          stockRepository,
          voucherRepository,
        ),
        collectionRepository: SqlitePosInvoicePaymentCollectionRepository(
          runner,
          voucherRepository,
        ),
      );
      final posting = _sale(invalidCogs: true);
      final result = await writer.saveSaleWithOutboundAtomically(
        posting,
        _outboundBundleForSale(posting),
      );

      expect(result.isFailure, isTrue);
      expect(await db.query('pos_invoices'), isEmpty);
      expect(await db.query('pos_financial_event_outbox'), isEmpty);
      expect(await db.query('device_sync_outbox'), isEmpty);
      expect(await db.query('pos_stock_movements'), hasLength(1));
    });

    test(
      'applies inbound sale once with atomic inbox/journal and quarantines conflict',
      () async {
        final runner = DatabaseTransactionRunner(db);
        final voucherRepository = SqliteVoucherRepository(db, runner);
        final eventStore = PosFinancialEventStore(db);
        final journal = SqliteSyncInboundEventJournalRepository(db);
        final applier = SqlitePosFinancialInboundApplicationRepository(
          transactionRunner: runner,
          eventStore: eventStore,
          inboundJournal: journal,
          saleRepository: repository,
          purchaseRepository: SqlitePosPurchasePostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          salesReturnRepository: SqlitePosSalesReturnPostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          purchaseReturnRepository: SqlitePosPurchaseReturnPostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          collectionRepository: SqlitePosInvoicePaymentCollectionRepository(
            runner,
            voucherRepository,
          ),
        );

        Future<void> claim(String nodeId, String ciphertext) async {
          final result = await journal.beginProcessing(
            nodeId: nodeId,
            senderPublicKey: 'a' * 64,
            eventType: SyncEventType.posSale.name,
            payloadFingerprint: 'transport-$nodeId',
            encryptedPayload: ciphertext,
          );
          expect(result, SyncInboundEventClaim.claimed);
        }

        final posting = _sale();
        final event = _inboundEventForSale(posting);
        const ciphertext = 'opaque-e2ee-node';
        await claim('transport-1', ciphertext);
        final applied = await applier.applySaleAtomically(
          event: event,
          posting: posting,
          transportNodeId: 'transport-1',
          encryptedPayload: ciphertext,
        );
        expect(applied, PosFinancialApplyResult.applied);

        final exactReplayPosting = _sale();
        await claim('transport-2', 'opaque-e2ee-replay');
        final replay = await applier.applySaleAtomically(
          event: _inboundEventForSale(exactReplayPosting),
          posting: exactReplayPosting,
          transportNodeId: 'transport-2',
          encryptedPayload: 'opaque-e2ee-replay',
        );
        expect(replay, PosFinancialApplyResult.exactReplay);

        final changedPosting = _sale(quantity: 2);
        await claim('transport-3', 'opaque-e2ee-conflict');
        final conflict = await applier.applySaleAtomically(
          event: _inboundEventForSale(changedPosting),
          posting: changedPosting,
          transportNodeId: 'transport-3',
          encryptedPayload: 'opaque-e2ee-conflict',
        );
        expect(conflict, PosFinancialApplyResult.conflictingReplay);

        expect(await db.query('pos_invoices'), hasLength(1));
        expect(await db.query('pos_stock_movements'), hasLength(2));
        expect(await db.query('pos_financial_event_inbox'), hasLength(1));
        expect(await db.query('pos_financial_event_conflicts'), hasLength(1));
        final journalRows = await db.query(
          'sync_inbound_event_journal',
          orderBy: 'node_id ASC',
        );
        expect(journalRows.map((row) => row['state']), [
          'applied',
          'applied',
          'quarantined',
        ]);
        expect(journalRows.last['encrypted_payload'], 'opaque-e2ee-conflict');
      },
    );

    test(
      'applies inbound purchase return once with atomic journal replay',
      () async {
        final runner = DatabaseTransactionRunner(db);
        final voucherRepository = SqliteVoucherRepository(db, runner);
        for (final id in ['supplier', 'payables', 'purchase-returns']) {
          await db.insert('accounts', {
            'id': id,
            'name': id,
            'nature': id == 'supplier' ? 'credit' : 'debit',
            'created_at': '2026-01-01T00:00:00.000Z',
          });
        }
        final fixture = _purchaseReturn();
        await db.insert('pos_invoices', PosInvoiceMapper.toRow(fixture.source));
        await db.insert(
          'pos_invoice_lines',
          PosInvoiceMapper.lineToRow(fixture.source.lines.single),
        );
        final sourceStock = await stockRepository.append(
          fixture.sourceMovement,
        );
        expect(sourceStock.isSuccess, isTrue);

        final eventStore = PosFinancialEventStore(db);
        final journal = SqliteSyncInboundEventJournalRepository(db);
        final applier = SqlitePosFinancialInboundApplicationRepository(
          transactionRunner: runner,
          eventStore: eventStore,
          inboundJournal: journal,
          saleRepository: repository,
          purchaseRepository: SqlitePosPurchasePostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          salesReturnRepository: SqlitePosSalesReturnPostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          purchaseReturnRepository: SqlitePosPurchaseReturnPostingRepository(
            runner,
            stockRepository,
            voucherRepository,
          ),
          collectionRepository: SqlitePosInvoicePaymentCollectionRepository(
            runner,
            voucherRepository,
          ),
        );
        final rawEvent = _outboundBundleForPurchaseReturn(
          fixture.posting,
        ).event.toJson();
        rawEvent['target_device_id'] = 'device-b';
        final event = PosFinancialSyncEvent.fromJson(rawEvent);

        Future<void> claim(String nodeId) async {
          final result = await journal.beginProcessing(
            nodeId: nodeId,
            senderPublicKey: 'a' * 64,
            eventType: SyncEventType.posPurchaseReturn.name,
            payloadFingerprint: 'transport-$nodeId',
            encryptedPayload: 'encrypted-$nodeId',
          );
          expect(result, SyncInboundEventClaim.claimed);
        }

        await claim('purchase-return-node-1');
        final applied = await applier.applyPurchaseReturnAtomically(
          event: event,
          posting: fixture.posting,
          transportNodeId: 'purchase-return-node-1',
          encryptedPayload: 'encrypted-purchase-return-node-1',
        );
        expect(applied, PosFinancialApplyResult.applied);

        await claim('purchase-return-node-2');
        final replay = await applier.applyPurchaseReturnAtomically(
          event: event,
          posting: fixture.posting,
          transportNodeId: 'purchase-return-node-2',
          encryptedPayload: 'encrypted-purchase-return-node-2',
        );
        expect(replay, PosFinancialApplyResult.exactReplay);
        expect(await db.query('pos_invoices'), hasLength(2));
        expect(await db.query('pos_returns'), hasLength(1));
        expect(await db.query('pos_stock_movements'), hasLength(3));
        expect(await db.query('vouchers'), hasLength(2));
        expect(await db.query('ledger_entries'), hasLength(4));
        expect(await db.query('pos_financial_event_inbox'), hasLength(1));
        final journalRows = await db.query(
          'sync_inbound_event_journal',
          orderBy: 'node_id ASC',
        );
        expect(journalRows.map((row) => row['state']), ['applied', 'applied']);
      },
    );
  });
}
