import 'package:daleventa_pos/core/utils/build_phase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runOutsideBuildPhase ejecuta la acción de inmediato fuera del build', () {
    var ran = false;

    runOutsideBuildPhase(() => ran = true);

    expect(ran, isTrue);
  });

  test('isFlutterBuildPhase es false fuera de un frame de build', () {
    expect(isFlutterBuildPhase(), isFalse);
  });

  testWidgets(
    'runOutsideBuildPhase difiere la acción cuando se invoca en fase de build',
    (tester) async {
      var ranInsideBuild = false;
      var deferredInsideBuild = false;
      var buildPhaseDetected = false;
      var firstBuild = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              if (firstBuild) {
                firstBuild = false;
                buildPhaseDetected = isFlutterBuildPhase();
                runOutsideBuildPhase(() => ranInsideBuild = true);
                // Snapshot tomado DENTRO del build: aún no se ejecutó.
                deferredInsideBuild = !ranInsideBuild;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Dentro del build la acción NO se ejecuta de inmediato (se difirió).
      expect(buildPhaseDetected, isTrue);
      expect(deferredInsideBuild, isTrue);

      // Se ejecuta al final del frame, con el árbol ya consistente.
      expect(ranInsideBuild, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
