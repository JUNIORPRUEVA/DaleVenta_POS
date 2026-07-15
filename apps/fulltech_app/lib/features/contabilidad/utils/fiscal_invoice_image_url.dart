import '../../../core/api/env.dart';

String resolveFiscalInvoiceImageUrl(String? imageUrl) {
  final raw = (imageUrl ?? '').trim();
  if (raw.isEmpty) return '';

  final encoded = Uri.encodeQueryComponent(raw);
  return '${Env.apiBaseUrl}/public/contabilidad/fiscal-invoices/image?url=$encoded';
}
