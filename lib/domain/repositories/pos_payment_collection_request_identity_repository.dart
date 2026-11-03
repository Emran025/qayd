import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_payment_collection_request_identity.dart';

abstract interface class PosPaymentCollectionRequestIdentityRepository {
  Future<Result<PosPaymentCollectionRequestIdentity>> getOrCreate({
    required String fingerprintHash,
    required PosPaymentCollectionRequestIdentity candidate,
  });

  Future<Result<void>> acknowledgeCommitted({
    required String fingerprintHash,
    required PosPaymentCollectionRequestIdentity identity,
  });

  /// Removes a pending identity only when the caller knows no posting occurred.
  Future<Result<void>> discardUncommitted({
    required String fingerprintHash,
    required PosPaymentCollectionRequestIdentity identity,
  });
}
