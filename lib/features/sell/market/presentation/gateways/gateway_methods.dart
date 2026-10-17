import 'package:flutter/material.dart';
import '../banners/form_kit.dart';

// Payment method metadata — mirrors erp/desktop's Gateways.tsx METHODS.

class GatewayMethod {
  final String id;
  final String label;
  final String hint;
  final IconData icon;
  final List<String> providers;
  final bool needsAccount;
  const GatewayMethod(this.id, this.label, this.hint, this.icon, {this.providers = const [], this.needsAccount = false});
}

const gatewayMethods = <GatewayMethod>[
  GatewayMethod('cash', 'Cash on delivery', 'Buyer pays the rider on delivery.', Icons.payments_outlined),
  GatewayMethod('card', 'Card', 'Paid online at checkout.', Icons.credit_card_outlined,
      providers: ['Stripe', 'SSLCommerz', 'aamarPay', 'ShurjoPay']),
  GatewayMethod('mobile', 'Mobile wallet', 'Buyer sends money and enters the transaction ID.', Icons.smartphone_outlined,
      providers: ['bKash', 'Nagad', 'Rocket', 'Upay'], needsAccount: true),
  GatewayMethod('bank', 'Bank transfer', 'Buyer transfers to your account and enters the reference.', Icons.account_balance_outlined,
      needsAccount: true),
];

GatewayMethod gatewayMethod(String? id) => gatewayMethods.firstWhere((m) => m.id == id, orElse: () => gatewayMethods.first);

/// Full PUT / POST body for a gateway row (never partial).
Map<String, dynamic> gatewayBody(Map<String, dynamic> g) => {
      'method': g['method'] ?? 'cash',
      'provider': orNull('${g['provider'] ?? ''}'),
      'label': orNull('${g['label'] ?? ''}'),
      'account_name': orNull('${g['account_name'] ?? ''}'),
      'account_number': orNull('${g['account_number'] ?? ''}'),
      'instructions': orNull('${g['instructions'] ?? ''}'),
      'sort_order': g['sort_order'] is num ? (g['sort_order'] as num).toInt() : int.tryParse('${g['sort_order']}') ?? 0,
      'is_active': g['is_active'] == true,
    };
