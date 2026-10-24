import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product_category.dart';
import 'package:qayd/domain/repositories/pos_product_category_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class SqlitePosProductCategoryRepository
    implements PosProductCategoryRepository {
  SqlitePosProductCategoryRepository(this._db);
  final Database _db;

  @override
  Future<Result<List<PosProductCategory>>> list({bool activeOnly = true}) async {
    try {
      final rows = await _db.query(
        'pos_product_categories',
        where: activeOnly ? 'is_active = 1' : null,
        orderBy: 'name COLLATE NOCASE ASC',
      );
      return Success(rows.map(_mapRow).toList(growable: false));
    } on DatabaseException {
      return FailureResult(DatabaseFailure(messageAr: AppStrings.posProductReadFailed));
    }
  }

  @override
  Future<Result<void>> save(PosProductCategory category) async {
    try {
      await _db.insert(
        'pos_product_categories',
        {
          'id': category.id,
          'name': category.name,
          'code': category.code,
          'parent_id': category.parentId,
          'is_active': category.isActive ? 1 : 0,
          'created_at': category.createdAt.toUtc().toIso8601String(),
          'updated_at': category.updatedAt.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return const Success(null);
    } on DatabaseException {
      return FailureResult(DatabaseFailure(messageAr: AppStrings.posProductSaveFailed));
    }
  }

  @override
  Future<Result<void>> deactivate(String id) async {
    try {
      final used = await _db.query(
        'pos_products',
        columns: ['id'],
        where: 'category_id = ? LIMIT 1',
        whereArgs: [id],
      );
      if (used.isNotEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posProductCategoryInUse),
        );
      }
      final count = await _db.update(
        'pos_product_categories',
        {'is_active': 0, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      return count == 0
          ? FailureResult(ValidationFailure(messageAr: AppStrings.posProductNotFound))
          : const Success(null);
    } on DatabaseException {
      return FailureResult(DatabaseFailure(messageAr: AppStrings.posProductSaveFailed));
    }
  }

  PosProductCategory _mapRow(Map<String, Object?> row) =>
      PosProductCategory.restore(
        id: row['id']! as String,
        name: row['name']! as String,
        code: row['code']! as String,
        parentId: row['parent_id'] as String?,
        isActive: (row['is_active'] as num).toInt() == 1,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
}
