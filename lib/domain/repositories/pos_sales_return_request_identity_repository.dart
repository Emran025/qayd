import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_sales_return_request_identity.dart';

abstract interface class PosSalesReturnRequestIdentityRepository {
  Future<Result<PosSalesReturnRequestIdentity>> getOrCreate({
    required String fingerprintHash,
    required PosSalesReturnRequestIdentity candidate,
  });

  Future<Result<void>> acknowledgeCommitted({
    required String fingerprintHash,
    required PosSalesReturnRequestIdentity identity,
  });
}
