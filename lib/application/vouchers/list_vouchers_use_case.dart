import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/vouchers/dtos/list_vouchers_input.dart';
import 'package:qayd/application/vouchers/dtos/list_vouchers_output.dart';
import 'package:qayd/application/vouchers/dtos/voucher_summary_dto.dart';
import 'package:qayd/application/vouchers/voucher_filter_mapper.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/value_objects/voucher_query_filter.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/collateral_repository.dart';

class ListVouchersUseCase {
  ListVouchersUseCase(
    this._voucherRepository,
    this._accountRepository,
    this._collateralRepository,
  );

  final VoucherRepository _voucherRepository;
  final AccountRepository _accountRepository;
  final CollateralRepository _collateralRepository;

  Future<Result<ListVouchersOutput>> call(ListVouchersInput input) async {
    try {
      final accountsR = await _accountRepository.getAll(activeOnly: false);
      if (accountsR.isFailure) {
        return FailureResult(accountsR.failureOrNull!);
      }
      final nameById = {
        for (final a in accountsR.valueOrNull!) a.id.value: a.name,
      };

      final mappedFilter = VoucherFilterMapper.toDomain(input.advancedFilter);
      final domainFilter = VoucherQueryFilter(
        state: mappedFilter?.state,
        type: mappedFilter?.type,
        dateRange: mappedFilter?.dateRange,
        counterpartyId: mappedFilter?.counterpartyId,
        affectedAccountId: mappedFilter?.affectedAccountId,
        costCenterId: mappedFilter?.costCenterId,
        involvedRootAccountId: mappedFilter?.involvedRootAccountId,
        involvedCounterRootAccountId:
            mappedFilter?.involvedCounterRootAccountId,
        isInternalOnly: mappedFilter?.isInternalOnly,
        excludeTripartite: input.excludeTripartite,
        onlyTripartite: input.onlyTripartite,
      );
      final q = input.searchQuery?.trim() ?? '';
      final Result<List<Voucher>> r = q.isEmpty
          ? await _voucherRepository.getAll(
              filter: domainFilter,
              limit: input.limit,
              offset: input.offset,
            )
          : await _voucherRepository.search(
              queryText: q,
              filter: domainFilter,
            );
      if (r.isFailure) {
        return FailureResult(r.failureOrNull!);
      }
      final list = r.valueOrNull!;
      
      // Bulk lookup of which vouchers have collateral
      final Set<String> collateralVoucherIds = {};
      if (list.isNotEmpty) {
        final collR = await _collateralRepository.getVoucherIdsWithCollateral(
          list.map((v) => v.id).toList(),
        );
        if (collR.isSuccess) {
          collateralVoucherIds.addAll(collR.valueOrNull!);
        }
      }

      return Success(
        ListVouchersOutput(
          accountNamesById: nameById,
          vouchers: list
              .map(
                (v) => VoucherSummaryDto(
                  id: v.id.value,
                  typeCode: v.type.name,
                  stateCode: v.state.name,
                  dateIso: v.date.toIso8601String(),
                  createdAtIso: v.createdAt.toIso8601String(),
                  amountMinorUnits: v.amount.minorUnits,
                  currencyCode: v.currency.code,
                  currencyNameAr: v.currency.nameAr,
                  currencySymbol: v.currency.symbol,
                  currencyDigits: v.currency.fractionalDigits,
                  counterpartyAccountId: v.counterpartyId.value,
                  counterpartyName: nameById[v.counterpartyId.value] ??
                      v.counterpartyId.value,
                  affectedAccountId: v.affectedAccountId.value,
                  affectedName: nameById[v.affectedAccountId.value] ??
                      v.affectedAccountId.value,
                  isTripartite: v.isTripartite,
                  transferGroupId: v.tripartiteMeta?.transferGroupId,
                  tripartiteRole: v.tripartiteMeta?.role.columnValue,
                  linkedPartyId: v.tripartiteMeta?.linkedPartyId.value,
                  isContingent: v.isContingent,
                  hasCollateral: collateralVoucherIds.contains(v.id.value),
                  senderStatusCode: v.senderStatus.name,
                  receiverStatusCode: v.receiverStatus.name,
                  originVoucherId: v.originVoucherId?.value,
                  reversalCount: v.reversalCount,
                  firstChildId: v.firstChildId?.value,
                  description: v.description,
                ),
              )
              .toList(growable: false),
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
