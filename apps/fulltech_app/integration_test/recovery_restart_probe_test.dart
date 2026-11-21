import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/storage/serialized_secure_storage.dart';
import 'package:daleventa_pos/features/offline/sale_attempt_recovery_screen.dart';

/// Run only after terminating the owned UAT application process. This probe
/// reads the previous run's data and performs no financial POST or deletion.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'physical process restart preserves owner, encrypted keys and incidents',
    (tester) async {
      const base = String.fromEnvironment('UAT_API_BASE');
      final target = Uri.parse(base);
      expect(['127.0.0.1', '::1', '[::1]'], contains(target.host));
      expect(target.port, 4004);
      final directory = Platform.isAndroid
          ? '${(await getApplicationSupportDirectory()).path}/recovery-evidence'
          : const String.fromEnvironment('RECOVERY_EVIDENCE_DIR');
      expect(directory, isNotEmpty);
      final previous =
          jsonDecode(
                await File(
                  '$directory/windows-persistence.json',
                ).readAsString(),
              )
              as Map;
      final storage = TokenStorage();
      if (Platform.isWindows) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      await tester.runAsync(() async {
        final user = await storage.getUserSnapshot();
        expect(user?.companyId, previous['companyId']);
        expect(user?.id, previous['userId']);
        const secure = SerializedSecureStorage();
        for (var index = 0; index < 30; index++) {
          expect(
            await secure.read(
              key: 'uat.recovery.validation.${previous['run']}.$index',
            ),
            'synthetic-$index',
          );
        }
        final incidents = await OfflineStore.instance.listPendingActions(
          companyId: user!.companyId,
          userId: user.id,
          limit: null,
        );
        expect(incidents.length, 46);
        expect(
          incidents.every((item) => !item.isAutomaticallyRetryable),
          isTrue,
        );
        final token = await storage.getAccessToken();
        expect(token, isNotEmpty);
        final network = ProviderContainer(
          overrides: [tokenStorageProvider.overrideWithValue(storage)],
        );
        final dio = network.read(dioProvider);
        expect(dio.options.baseUrl, base);
        try {
          for (final item in (previous['scenarios'] as List).whereType<Map>()) {
            if (item['name'] != 'offline-sale-restart-replay' &&
                item['name'] != 'committed-sale-lost-response') {
              continue;
            }
            final response = await dio.get(
              '/sales/attempts/${item['requestId']}/reconciliation',
              queryParameters: {'expectedTotalSold': 50},
            );
            expect(response.data['status'], 'CONFIRMED');
            expect(response.data['clientRequestId'], item['requestId']);
            expect((response.data['sale'] as Map)['id'], item['serverId']);
            expect(response.data['recordedTotalSold'], 50);
            expect(response.data['matchesExpected'], isTrue);
          }
        } finally {
          network.dispose();
        }
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SaleAttemptRecoveryScreen()),
        ),
      );
      for (
        var index = 0;
        index < 150 &&
            find
                .text('Ventas offline y operaciones de caja')
                .evaluate()
                .isEmpty;
        index++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(find.text('Ventas offline y operaciones de caja'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final view = binding.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final image = await (view.layer! as OffsetLayer).toImage(
        view.paintBounds,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      binding.reportData = {
        'platform': Platform.operatingSystem,
        'run': '${previous['run']}-restart',
        'companyId': previous['companyId'],
        'userId': previous['userId'],
        'retainedIncidents': 46,
        'restoredEncryptedKeys': 30,
        'financialPosts': 0,
        'centerScreenshotPngBase64': base64Encode(bytes!.buffer.asUint8List()),
      };
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
