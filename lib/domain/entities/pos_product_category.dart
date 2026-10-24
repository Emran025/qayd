import 'package:qayd/domain/exceptions/invalid_pos_product_exception.dart';

/// Stable product taxonomy node. Categories are archived, never deleted, once used.
final class PosProductCategory {
  const PosProductCategory._({
    required this.id,
    required this.name,
    required this.code,
    required this.parentId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PosProductCategory.create({
    required String id,
    required String name,
    required String code,
    String? parentId,
    DateTime? now,
  }) {
    final normalizedName = name.trim();
    final normalizedCode = code.trim().toUpperCase();
    if (id.trim().isEmpty || normalizedName.isEmpty || normalizedCode.isEmpty) {
      throw InvalidPosProductException.nameRequired();
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    return PosProductCategory._(
      id: id.trim(),
      name: normalizedName,
      code: normalizedCode,
      parentId: parentId?.trim().isEmpty == true ? null : parentId?.trim(),
      isActive: true,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory PosProductCategory.restore({
    required String id,
    required String name,
    required String code,
    required String? parentId,
    required bool isActive,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    final category = PosProductCategory.create(
      id: id,
      name: name,
      code: code,
      parentId: parentId,
      now: createdAt,
    );
    return PosProductCategory._(
      id: category.id,
      name: category.name,
      code: category.code,
      parentId: category.parentId,
      isActive: isActive,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  final String id;
  final String name;
  final String code;
  final String? parentId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  PosProductCategory deactivate() => PosProductCategory._(
        id: id,
        name: name,
        code: code,
        parentId: parentId,
        isActive: false,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
}
