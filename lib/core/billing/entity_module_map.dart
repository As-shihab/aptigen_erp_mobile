// Maps an OData entity (Prisma model, lowercase) to the module `code` that
// owns it — a 1:1 copy of erp/desktop's paywall/entityModuleMap.ts. Keep the
// two in sync: a write against an entity listed here is blocked while its
// module is paid-but-unpaid for the current workplace.
const Map<String, String> entityModuleMap = {
  // HR
  'employees': 'HR',
  'employee_blacklists': 'HR',
  'designations': 'HR',
  'employee_sections': 'HR',
  'employee_types': 'HR',
  'employee_shifts': 'HR',
  'employee_groups': 'HR',
  'group_has_employees': 'HR',
  'asset_groups': 'HR',
  'assets': 'HR',
  'hiring': 'HR',
  'resumes': 'HR',
  'employee_has_assets': 'HR',
  'attendance_logs': 'HR',
  'rosters': 'HR',
  'shift_overrides': 'HR',
  'hr_policies': 'HR',
  'hr_notices': 'HR',
  'leave_types': 'HR',
  'leave_type_has_middleman': 'HR',
  'leave_requests': 'HR',
  'leave_request_approvals': 'HR',
  'leave_balances': 'HR',
  'employee_salaries': 'HR',
  'payrolls': 'HR',
  'calendar_events': 'HR',
  'employee_fingerprints': 'HR',
  'employee_off_days': 'HR',
  'hr_settings': 'HR',
  'departments': 'HR',
  'promotions': 'HR',

  // SELL
  'client_groups': 'SELL',
  'clients': 'SELL',
  'sales_orders': 'SELL',
  'sales_items': 'SELL',
  'order_payments': 'SELL',
  'order_settings': 'SELL',

  // STORE
  'store_product_categories': 'STORE',
  'store_product_sub_categories': 'STORE',
  'store_products': 'STORE',
  'store_uoms': 'STORE',
  'store_product_batches': 'STORE',
  'store_warehouses': 'STORE',
  'store_warehouse_corridors': 'STORE',
  'store_warehouse_racks': 'STORE',
  'store_warehouse_bins': 'STORE',
  'store_locations': 'STORE',
  'store_mrrs': 'STORE',
  'store_mrr_items': 'STORE',
  'store_requisitions': 'STORE',
  'store_requisition_items': 'STORE',
  'store_purchase_requisitions': 'STORE',
  'store_purchase_requisition_approvals': 'STORE',
  'store_purchase_requisition_items': 'STORE',
  'store_returns': 'STORE',
  'store_return_items': 'STORE',
  'store_mrr_returns': 'STORE',
  'store_mrr_return_items': 'STORE',
  'store_stock_movements': 'STORE',
  'store_label_templates': 'STORE',

  // PURCHASE
  'supplier_groups': 'PURCHASE',
  'suppliers': 'PURCHASE',
  'purchase_orders': 'PURCHASE',
  'purchase_order_items': 'PURCHASE',
  'purchase_order_approvals': 'PURCHASE',
  'purchase_settings': 'PURCHASE',
  'purchase_rfqs': 'PURCHASE',
  'purchase_rfq_items': 'PURCHASE',
  'purchase_rfq_quotes': 'PURCHASE',
  'purchase_rfq_quote_items': 'PURCHASE',

  // MARKET
  'market_store_followers': 'MARKET',
  'market_product_insights': 'MARKET',
  'market_listings': 'MARKET',
  'market_listing_medias': 'MARKET',
  'market_listing_views': 'MARKET',
  'store_carts': 'MARKET',
  'store_cart_items': 'MARKET',

  // NOTE
  'note_categories': 'NOTE',
  'notes': 'NOTE',
  'note_member_access': 'NOTE',
  'note_checklists': 'NOTE',
  'note_settings': 'NOTE',

  // HOSPITALITY (stays)
  'stay_categories': 'HOSPITALITY',
  'stays': 'HOSPITALITY',
  'stay_media': 'HOSPITALITY',
  'amenities': 'HOSPITALITY',
  'stay_amenities': 'HOSPITALITY',
  'reviews': 'HOSPITALITY',

  // ACCOUNTING
  'accounts': 'ACCOUNTING',
  'bank_accounts': 'ACCOUNTING',
  'journal_entries': 'ACCOUNTING',
  'journal_entry_lines': 'ACCOUNTING',
  'payment_vouchers': 'ACCOUNTING',
  'payment_requests': 'ACCOUNTING',

  // EXCEL
  'excel_groups': 'EXCEL',
  'excel_files': 'EXCEL',
  'excel_settings': 'EXCEL',

  // CHAT
  'chat_rooms': 'CHAT',
  'chat_room_members': 'CHAT',
  'chat_messages': 'CHAT',
  'chat_meetings': 'CHAT',

  // SETTINGS
  'media_categories': 'SETTINGS',
  'media_items': 'SETTINGS',
  'devices': 'SETTINGS',
  'device_requests': 'SETTINGS',
};
