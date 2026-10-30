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

  PosProductCategory copyWith({
    String? name,
    String? code,
    String? parentId,
    bool? isActive,
  }) {
    final nextName = name ?? this.name;
    final nextCode = code ?? this.code;
    if (nextName.trim().isEmpty || nextCode.trim().isEmpty) {
      throw InvalidPosProductException.nameRequired();
    }
    return PosProductCategory._(
      id: id,
      name: nextName.trim(),
      code: nextCode.trim().toUpperCase(),
      parentId: parentId ?? this.parentId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  PosProductCategory deactivate() => copyWith(isActive: false);

  PosProductCategory activate() => copyWith(isActive: true);
}
