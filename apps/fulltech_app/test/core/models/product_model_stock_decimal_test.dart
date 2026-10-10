import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión: `fromJson` prioriza `stockDecimal`, y `copyWith(stock:)` no lo
/// actualizaba, así que un producto ajustado y luego serializado/deserializado
/// (caché offline incluida) revivia el stock VIEJO.
void main() {
  test('copyWith(stock:) mantiene stockDecimal sincronizado tras el viaje JSON', () {
    final original = ProductModel(
      id: 'p-1',
      nombre: 'Café',
      precio: 100,
      costo: 50,
      stock: 5,
    );

    final updated = original.copyWith(stock: 12);
    final roundTrip = ProductModel.fromJson(updated.toJson());

    expect(roundTrip.stock, 12);
    expect(updated.stockDecimal, '12.0');
  });

  test('copyWith conserva la precisión cuando el stock NO cambia', () {
    final original = ProductModel(
      id: 'p-2',
      nombre: 'Tela',
      precio: 100,
      costo: 50,
      stock: 10.5,
      stockDecimal: '10.500',
    );

    final same = original.copyWith(nombre: 'Tela premium');

    expect(same.stockDecimal, '10.500');
    expect(ProductModel.fromJson(same.toJson()).stock, 10.5);
  });

  test('un ajuste decimal sobrevive la serialización', () {
    final original = ProductModel(
      id: 'p-3',
      nombre: 'Harina',
      precio: 100,
      costo: 50,
      stock: 20,
    );

    final updated = original.copyWith(stock: 22.375);
    final roundTrip = ProductModel.fromJson(updated.toJson());

    expect(roundTrip.stock, 22.375);
    expect(roundTrip.stockDecimal, '22.375');
  });

  test('stockDecimal explícito sigue ganando sobre la derivación', () {
    final original = ProductModel(
      id: 'p-4',
      nombre: 'Yarda',
      precio: 100,
      costo: 50,
      stock: 5,
    );

    final updated = original.copyWith(stock: 6, stockDecimal: '6.000');

    expect(updated.stockDecimal, '6.000');
    expect(ProductModel.fromJson(updated.toJson()).stock, 6);
  });

  test('sin argumento stock no se toca el decimal existente', () {
    final original = ProductModel(
      id: 'p-5',
      nombre: 'Libra',
      precio: 100,
      costo: 50,
      stock: 3,
      stockDecimal: '3.000',
    );

    final renamed = original.copyWith(categoria: 'Abarrotes');

    expect(renamed.stock, 3);
    expect(renamed.stockDecimal, '3.000');
  });
}
