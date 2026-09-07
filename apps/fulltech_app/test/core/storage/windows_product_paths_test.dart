import 'package:daleventa_pos/core/storage/windows_product_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('builds official mutable folder paths from product root', () {
    final root = p.join('C:', 'Program Files', WindowsProductPaths.productName);

    expect(
      WindowsProductPaths.pathForRoot(root, WindowsProductFolder.app),
      p.join(root, 'app'),
    );
    expect(
      WindowsProductPaths.pathForRoot(root, WindowsProductFolder.databases),
      p.join(root, 'databases'),
    );
    expect(
      WindowsProductPaths.pathForRoot(root, WindowsProductFolder.backups),
      p.join(root, 'backups'),
    );
    expect(
      WindowsProductPaths.pathForRoot(root, WindowsProductFolder.mediaCache),
      p.join(root, 'media_cache'),
    );
    expect(
      WindowsProductPaths.pathForRoot(root, WindowsProductFolder.logs),
      p.join(root, 'logs'),
    );
    expect(
      WindowsProductPaths.pathForRoot(root, WindowsProductFolder.config),
      p.join(root, 'config'),
    );
  });
}
