// Headless PDF → PNG rasterizer using the pdfium.dll bundled by the `printing`
// plugin (downloaded during `flutter build windows`).
//
// Renders every sample PDF in `tool/pdf_renders/` to PNGs next to it, so the
// unified Purchase Order design can be inspected visually.
//
// Run with: dart run tool/pdf_raster.dart
// (requires build\windows\x64\runner\Debug\pdfium.dll from a windows build)
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi;
import 'package:image/image.dart' as img;

final Pointer<ffi.Utf8> _nullPtr = Pointer<ffi.Utf8>.fromAddress(0);

typedef _InitLibraryNative = Void Function();
typedef _InitLibraryDart = void Function();
typedef _LoadMemDocNative = Pointer<Void> Function(
  Pointer<Void> data,
  Int32 size,
  Pointer<ffi.Utf8> password,
);
typedef _LoadMemDocDart = Pointer<Void> Function(
  Pointer<Void> data,
  int size,
  Pointer<ffi.Utf8> password,
);
typedef _GetPageCountNative = Int32 Function(Pointer<Void> doc);
typedef _GetPageCountDart = int Function(Pointer<Void> doc);
typedef _LoadPageNative = Pointer<Void> Function(Pointer<Void> doc, Int32 index);
typedef _LoadPageDart = Pointer<Void> Function(Pointer<Void> doc, int index);
typedef _GetPageWidthNative = Double Function(Pointer<Void> page);
typedef _GetPageWidthDart = double Function(Pointer<Void> page);
typedef _GetPageHeightNative = Double Function(Pointer<Void> page);
typedef _GetPageHeightDart = double Function(Pointer<Void> page);
typedef _BitmapCreateNative = Pointer<Void> Function(
  Int32 w,
  Int32 h,
  Int32 alpha,
);
typedef _BitmapCreateDart = Pointer<Void> Function(int w, int h, int alpha);
typedef _RenderPageNative = Void Function(
  Pointer<Void> bitmap,
  Pointer<Void> page,
  Int32 x,
  Int32 y,
  Int32 sizeX,
  Int32 sizeY,
  Int32 rotate,
  Int32 flags,
);
typedef _RenderPageDart = void Function(
  Pointer<Void> bitmap,
  Pointer<Void> page,
  int x,
  int y,
  int sizeX,
  int sizeY,
  int rotate,
  int flags,
);
typedef _BitmapGetBufferNative = Pointer<Uint8> Function(Pointer<Void> bitmap);
typedef _BitmapGetBufferDart = Pointer<Uint8> Function(Pointer<Void> bitmap);
typedef _BitmapGetStrideNative = Int32 Function(Pointer<Void> bitmap);
typedef _BitmapGetStrideDart = int Function(Pointer<Void> bitmap);
typedef _BitmapDestroyNative = Void Function(Pointer<Void> bitmap);
typedef _BitmapDestroyDart = void Function(Pointer<Void> bitmap);
typedef _ClosePageNative = Void Function(Pointer<Void> page);
typedef _ClosePageDart = void Function(Pointer<Void> page);
typedef _CloseDocNative = Void Function(Pointer<Void> doc);
typedef _CloseDocDart = void Function(Pointer<Void> doc);
typedef _DestroyLibraryNative = Void Function();
typedef _DestroyLibraryDart = void Function();

void main() {
  final pdfiumPath = File(
    r'build\windows\x64\runner\Debug\pdfium.dll',
  ).absolute;
  if (!pdfiumPath.existsSync()) {
    stderr.writeln('pdfium.dll not found at ${pdfiumPath.path}');
    stderr.writeln('Run `flutter build windows --debug` first.');
    exitCode = 1;
    return;
  }

  final lib = DynamicLibrary.open(pdfiumPath.path);
  final init = lib.lookupFunction<_InitLibraryNative, _InitLibraryDart>(
    'FPDF_InitLibrary',
  );
  final loadMem = lib.lookupFunction<_LoadMemDocNative, _LoadMemDocDart>(
    'FPDF_LoadMemDocument',
  );
  final pageCount = lib.lookupFunction<_GetPageCountNative, _GetPageCountDart>(
    'FPDF_GetPageCount',
  );
  final loadPage = lib.lookupFunction<_LoadPageNative, _LoadPageDart>(
    'FPDF_LoadPage',
  );
  final pageWidth = lib.lookupFunction<_GetPageWidthNative, _GetPageWidthDart>(
    'FPDF_GetPageWidth',
  );
  final pageHeight = lib.lookupFunction<_GetPageHeightNative, _GetPageHeightDart>(
    'FPDF_GetPageHeight',
  );
  final bmpCreate = lib.lookupFunction<_BitmapCreateNative, _BitmapCreateDart>(
    'FPDFBitmap_Create',
  );
  final render = lib.lookupFunction<_RenderPageNative, _RenderPageDart>(
    'FPDF_RenderPageBitmap',
  );
  final getBuffer = lib.lookupFunction<_BitmapGetBufferNative, _BitmapGetBufferDart>(
    'FPDFBitmap_GetBuffer',
  );
  final getStride = lib.lookupFunction<_BitmapGetStrideNative, _BitmapGetStrideDart>(
    'FPDFBitmap_GetStride',
  );
  final bmpDestroy = lib.lookupFunction<_BitmapDestroyNative, _BitmapDestroyDart>(
    'FPDFBitmap_Destroy',
  );
  final closePage = lib.lookupFunction<_ClosePageNative, _ClosePageDart>(
    'FPDF_ClosePage',
  );
  final closeDoc = lib.lookupFunction<_CloseDocNative, _CloseDocDart>(
    'FPDF_CloseDocument',
  );
  final destroyLib = lib.lookupFunction<_DestroyLibraryNative, _DestroyLibraryDart>(
    'FPDF_DestroyLibrary',
  );

  stdout.writeln('STEP init');
  init();

  const dpi = 150.0;
  final scale = dpi / 72.0;
  final dir = Directory('tool/pdf_renders');
  final pdfs = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.pdf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final rendered = <String>[];
  for (final pdf in pdfs) {
    stdout.writeln('STEP processing ${pdf.path}');
    final bytes = pdf.readAsBytesSync();
    final dataPtr = ffi.calloc<Uint8>(bytes.length);
    dataPtr.asTypedList(bytes.length).setAll(0, bytes);
    final doc = loadMem(dataPtr.cast(), bytes.length, _nullPtr);
    if (doc.address == 0) {
      stderr.writeln('FPDF_LoadMemDocument failed for ${pdf.path}');
      ffi.calloc.free(dataPtr);
      continue;
    }
    stdout.writeln('STEP loaded doc');

    final count = pageCount(doc);
    stdout.writeln('STEP pageCount=$count');
    for (var pageIndex = 0; pageIndex < count; pageIndex++) {
      final page = loadPage(doc, pageIndex);
      if (page.address == 0) continue;
      final widthPt = pageWidth(page);
      final heightPt = pageHeight(page);
      final sizeX = (widthPt * scale).round();
      final sizeY = (heightPt * scale).round();
      final bmp = bmpCreate(sizeX, sizeY, 1);
      render(bmp, page, 0, 0, sizeX, sizeY, 0, 0);
      stdout.writeln('STEP rendered page ${pageIndex + 1} ${sizeX}x$sizeY');

      final stride = getStride(bmp);
      final buf = getBuffer(bmp);
      final raw = buf.asTypedList(stride * sizeY);

      // pdfium buffer is BGR(A) → convert to RGBA.
      final rgba = Uint8List(sizeX * sizeY * 4);
      for (var y = 0; y < sizeY; y++) {
        for (var x = 0; x < sizeX; x++) {
          final src = y * stride + x * 4;
          final dst = (y * sizeX + x) * 4;
          rgba[dst] = raw[src + 2]; // R
          rgba[dst + 1] = raw[src + 1]; // G
          rgba[dst + 2] = raw[src]; // B
          rgba[dst + 3] = raw[src + 3]; // A
        }
      }

      final image = img.Image.fromBytes(
        width: sizeX,
        height: sizeY,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      final png = Uint8List.fromList(img.encodePng(image));
      final outName =
          '${pdf.path.substring(0, pdf.path.length - 4)}-page${pageIndex + 1}.png';
      File(outName).writeAsBytesSync(png);
      rendered.add(outName);

      bmpDestroy(bmp);
      closePage(page);
    }
    closeDoc(doc);
    // pdfium keeps a reference to the source buffer for the lifetime of the
    // document, so it must stay alive until after closeDoc.
    ffi.calloc.free(dataPtr);
  }

  destroyLib();
  stdout.writeln('RASTERIZED ${rendered.length} PNGs:');
  for (final f in rendered) {
    stdout.writeln('  $f');
  }
}
