import 'store_util.dart';

class StockMovementRow {
  final int id;
  final String type; // IN | OUT | ADJUST
  final double quantity;
  final double? balanceAfter;
  final String? referenceType;
  final int? referenceId;
  final String? remarks;
  final String createdAt;
  final String productName;
  final String locationPath;
  final String? batchNo;

  const StockMovementRow({
    required this.id,
    required this.type,
    required this.quantity,
    this.balanceAfter,
    this.referenceType,
    this.referenceId,
    this.remarks,
    required this.createdAt,
    required this.productName,
    required this.locationPath,
    this.batchNo,
  });

  factory StockMovementRow.fromJson(Map json) => StockMovementRow(
        id: toNum(json['id']),
        type: (json['type'] ?? '').toString(),
        quantity: toDouble(json['quantity']),
        balanceAfter: toDoubleOrNull(json['balance_after']),
        referenceType: toStringOrNull(json['reference_type']),
        referenceId: toIntOrNull(json['reference_id']),
        remarks: toStringOrNull(json['remarks']),
        createdAt: (json['created_at'] ?? '').toString(),
        productName: ((json['product'] as Map?)?['name'] ?? '—').toString(),
        locationPath: ((json['location'] as Map?)?['path'] ?? '—').toString(),
        batchNo: toStringOrNull((json['batch'] as Map?)?['batch_no']),
      );
}
