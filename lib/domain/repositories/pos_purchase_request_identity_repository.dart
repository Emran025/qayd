import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_purchase_request_identity.dart';

abstract interface class PosPurchaseRequestIdentityRepository {
  /// Gets the already persisted identity for a fingerprint, or stores [candidate]
  /// before any purchase write is attempted.
  Future<Result<PosPurchaseRequestIdentity>> getOrCreate({
    required String fingerprintHash,
    required PosPurchaseRequestIdentity candidate,
  });

  /// Removes the retained intent only after the UI has received the successful
  /// result. Until then an app restart can safely replay a committed transaction
  /// and recover its confirmation instead of creating a duplicate.
  Future<Result<void>> acknowledgeCommitted({
    required String fingerprintHash,
    required PosPurchaseRequestIdentity identity,
  });
}
