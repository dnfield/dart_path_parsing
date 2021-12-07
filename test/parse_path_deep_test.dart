import 'package:path_parsing/path_parsing.dart';
import 'package:test/test.dart';

class DeepTestPathProxy extends PathProxy {
  DeepTestPathProxy(this.expectedCommands);

  final List<String> expectedCommands;
  final List<String> actualCommands = <String>[];

  @override
  void close() {
    actualCommands.add('close()');
  }

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    actualCommands.add('cubicTo($x1, $y1, $x2, $y2, $x3, $y3)');
  }

  @override
  void lineTo(double x, double y) {
    actualCommands.add('lineTo($x, $y)');
  }

  @override
  void moveTo(double x, double y) {
    actualCommands.add('moveTo($x, $y)');
  }

  void validate() {
    expect(actualCommands, orderedEquals(expectedCommands));
  }
}

void main() {
  void assertValidPath(String input, List<String> commands) {
    final DeepTestPathProxy proxy = DeepTestPathProxy(commands);
    writeSvgPathDataToPath(input, proxy);
    proxy.validate();
  }

  // test('Deep path validation', () {
  //   assertValidPath('M20,30 Q40,5 60,30 T100,30', <String>[
  //     'moveTo(20.0, 30.0)',
  //     'cubicTo(33.33333333333333, 13.333333333333332, 46.666666666666664, 13.333333333333332, 60.0, 30.0)',
  //     'cubicTo(73.33333333333333, 46.666666666666664, 86.66666666666666, 46.666666666666664, 100.0, 30.0)',
  //   ]);
  // });

  test('Arc 1', () {
    assertValidPath(
      'M 15 15.5 A 0.5 1.5 0 1 1  14,15.5 A 0.5 1.5 0 1 1  15 15.5 z',
      <String>[
        'moveTo(15.0, 15.5)',
        'cubicTo(15.0, 16.32842758668219, 14.776142374915397, 17.000000461935997, 14.5, 17.000000461935997)',
        'cubicTo(14.223857625084603, 17.000000461935997, 14.0, 16.32842758668219, 14.0, 15.500000461935997)',
        'cubicTo(14.0, 14.671573337189807, 14.223857625084603, 14.000000461935997, 14.5, 14.000000461935997)',
        'cubicTo(14.776142374915397, 14.000000461935997, 15.0, 14.671573337189807, 15.0, 15.500000461935997)',
        'close()'
      ],
    );
  });

  test('Arc 2', () {
    assertValidPath(
      'M97.325 34.818a2.143 2.143 0 100-4.286 2.143 2.143 0 000 4.286z',
      <String>[
        'moveTo(97.325, 34.818)',
        'cubicTo(98.50862885295136, 34.81812293973836, 99.46822048142015, 33.85863261475589, 99.46822048142015, 32.67499810206613)',
        'cubicTo(99.46822048142015, 31.491363589376355, 98.50862885295136, 30.53187326439389, 97.32499434685802, 30.531998226542708)',
        'cubicTo(96.14153655073771, 30.532123170035373, 95.18222070648729, 31.491540299350355, 95.18222070648729, 32.67499810206613)',
        'cubicTo(95.18222070648729, 33.85845590478189, 96.14153655073771, 34.81787303409686, 97.32499434685802, 34.81799797758954)',
        'close()'
      ],
    );
  });
}
