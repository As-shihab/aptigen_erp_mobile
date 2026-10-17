enum PrinterConnectionType { bluetooth, wifi, usb }

String printerConnectionTypeLabel(PrinterConnectionType type) => switch (type) {
      PrinterConnectionType.bluetooth => 'Bluetooth',
      PrinterConnectionType.wifi => 'Wi-Fi',
      PrinterConnectionType.usb => 'USB',
    };

/// One configured receipt printer — a saved device profile (not just a bare
/// MAC address) so the same "device" concept can later grow a Wi-Fi/USB
/// connection type without reshaping the model. Only Bluetooth is wired up
/// today (`macAddress` is the one connection detail that matters); `ipAddress`
/// is reserved for a future Wi-Fi (raw TCP/IP, port 9100) printer type.
class PrinterDevice {
  final String id;
  final String name;
  final PrinterConnectionType connectionType;
  final String? macAddress;
  final String? ipAddress;
  final int paperWidthMm; // 58 or 80
  final bool fullCut;
  final bool autoCut;
  final bool isDefault;

  const PrinterDevice({
    required this.id,
    required this.name,
    required this.connectionType,
    this.macAddress,
    this.ipAddress,
    this.paperWidthMm = 58,
    this.fullCut = false,
    this.autoCut = true,
    this.isDefault = false,
  });

  /// Characters per line at normal font size — the usual 58mm/80mm thermal
  /// printer defaults (Font A, 12x24 dots/char).
  int get lineWidth => paperWidthMm >= 80 ? 48 : 32;

  PrinterDevice copyWith({
    String? name,
    int? paperWidthMm,
    bool? fullCut,
    bool? autoCut,
    bool? isDefault,
  }) =>
      PrinterDevice(
        id: id,
        name: name ?? this.name,
        connectionType: connectionType,
        macAddress: macAddress,
        ipAddress: ipAddress,
        paperWidthMm: paperWidthMm ?? this.paperWidthMm,
        fullCut: fullCut ?? this.fullCut,
        autoCut: autoCut ?? this.autoCut,
        isDefault: isDefault ?? this.isDefault,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'connectionType': connectionType.name,
        'macAddress': macAddress,
        'ipAddress': ipAddress,
        'paperWidthMm': paperWidthMm,
        'fullCut': fullCut,
        'autoCut': autoCut,
        'isDefault': isDefault,
      };

  factory PrinterDevice.fromJson(Map<String, dynamic> json) => PrinterDevice(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? 'Printer').toString(),
        connectionType: PrinterConnectionType.values.firstWhere(
          (t) => t.name == json['connectionType'],
          orElse: () => PrinterConnectionType.bluetooth,
        ),
        macAddress: json['macAddress']?.toString(),
        ipAddress: json['ipAddress']?.toString(),
        paperWidthMm: (json['paperWidthMm'] as num?)?.toInt() ?? 58,
        fullCut: json['fullCut'] == true,
        autoCut: json['autoCut'] != false,
        isDefault: json['isDefault'] == true,
      );
}
