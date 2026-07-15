import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/company/company_settings_repository.dart';

final companyInfoRepositoryProvider = Provider<CompanyInfoRepository>((ref) {
  return CompanyInfoRepository(ref);
});

class CompanyInfo {
  const CompanyInfo({
    required this.name,
    this.rnc = '',
    this.phone = '',
    this.address = '',
    this.email = '',
    this.website = '',
    this.instagram = '',
    this.facebook = '',
    this.logoBytes,
  });

  final String name;
  final String rnc;
  final String phone;
  final String address;
  final String email;
  final String website;
  final String instagram;
  final String facebook;
  final Uint8List? logoBytes;

  factory CompanyInfo.empty() => const CompanyInfo(name: 'FULLTECH POS');
}

class CompanyInfoRepository {
  CompanyInfoRepository(this._ref);

  final Ref _ref;

  Future<CompanyInfo> getCurrentCompanyInfo() async {
    try {
      final settings = await _ref
          .read(companySettingsRepositoryProvider)
          .getSettings();
      Uint8List? logo;
      final logoBase64 = settings.logoBase64?.trim();
      if (logoBase64 != null && logoBase64.isNotEmpty) {
        try {
          logo = base64Decode(logoBase64);
        } catch (_) {
          logo = null;
        }
      }
      return CompanyInfo(
        name: settings.companyName.trim().isEmpty
            ? 'FULLTECH POS'
            : settings.companyName.trim(),
        rnc: settings.rnc.trim(),
        phone: settings.phone.trim(),
        address: settings.address.trim(),
        website: settings.websiteUrl.trim(),
        instagram: settings.instagramUrl.trim(),
        facebook: settings.facebookUrl.trim(),
        logoBytes: logo,
      );
    } catch (_) {
      return CompanyInfo.empty();
    }
  }
}
