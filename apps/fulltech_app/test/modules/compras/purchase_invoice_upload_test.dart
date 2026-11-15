import 'dart:typed_data';
import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/modules/compras/data/purchases_repository.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'factura se envía como multipart con archivo, suplidor y datos opcionales',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.method, 'POST');
            expect(request.path, ApiRoutes.purchaseInvoices);
            final form = request.data as FormData;
            expect(Map.fromEntries(form.fields), {
              'supplierId': 'supplier',
              'invoiceNumber': 'FC-01',
              'notes': 'Prueba',
            });
            expect(form.files.single.key, 'file');
            final file = form.files.single.value;
            expect(file.filename, 'factura.pdf');
            expect(file.length, 4);
            expect(file.contentType.toString(), 'application/pdf');
            handler.resolve(
              Response(
                requestOptions: request,
                data: {
                  'id': 'invoice',
                  'supplier': {'id': 'supplier', 'commercialName': 'Proveedor'},
                  'fileName': 'factura.pdf',
                  'fileUrl': '/uploads/factura.pdf',
                  'mimeType': 'application/pdf',
                  'fileSize': 4,
                  'invoiceNumber': 'FC-01',
                },
              ),
            );
          },
        ),
      );
      final invoice = await PurchasesRepository(dio).uploadInvoice(
        file: PlatformFile(
          name: 'factura.pdf',
          size: 4,
          bytes: Uint8List.fromList([37, 80, 68, 70]),
        ),
        supplierId: 'supplier',
        invoiceNumber: ' FC-01 ',
        notes: ' Prueba ',
      );
      expect(invoice.id, 'invoice');
      expect(invoice.supplier.id, 'supplier');
      expect(invoice.fileUrl, '/uploads/factura.pdf');
    },
  );

  test('archivo sin bytes se rechaza antes de enviar', () async {
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (_, handler) => requests++),
    );
    await expectLater(
      PurchasesRepository(dio).uploadInvoice(
        file: PlatformFile(name: 'factura.pdf', size: 0),
        supplierId: 'supplier',
      ),
      throwsA(isA<ApiException>()),
    );
    expect(requests, 0);
  });

  test('un fallo del servidor se comunica como error de subida', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.reject(
            DioException(
              requestOptions: request,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: request,
                statusCode: 413,
                data: {'message': 'Archivo demasiado grande'},
              ),
            ),
          );
        },
      ),
    );
    await expectLater(
      PurchasesRepository(dio).uploadInvoice(
        file: PlatformFile(name: 'factura.pdf', size: 1, bytes: Uint8List(1)),
        supplierId: 'supplier',
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
