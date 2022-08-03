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
    expect(expectedCommands, orderedEquals(actualCommands));
  }
}

void main() {
  void assertValidPath(String input, List<String> commands) {
    final DeepTestPathProxy proxy = DeepTestPathProxy(commands);
    writeSvgPathDataToPath(input, proxy);
    proxy.validate();
  }

  test('Deep path validation', () {
    assertValidPath('M20,30 Q40,5 60,30 T100,30', <String>[
      'moveTo(20.0, 30.0)',
      'cubicTo(33.33333333333333, 13.333333333333332, 46.666666666666664, 13.333333333333332, 60.0, 30.0)',
      'cubicTo(73.33333333333333, 46.666666666666664, 86.66666666666666, 46.666666666666664, 100.0, 30.0)',
    ]);

    assertValidPath(
        'M5.5 5.5a.5 1.5 30 1 1-.866-.5.5 1.5 30 1 1 .866.5z', <String>[
      'moveTo(5.5, 5.5)',
      'cubicTo(5.231901344854459, 5.966739561631625, 4.900144629677152, 6.351285355753472, 4.630667434286423, 6.50766025048306)',
      'cubicTo(4.361190238895693, 6.664035145212647, 4.195311478208663, 6.568262191550129, 4.1960001487014535, 6.256697621943256)',
      'cubicTo(4.196688819194243, 5.945133052336383, 4.363839327080128, 5.465549035128047, 4.633999909767833, 4.999999765590259)',
      'cubicTo(4.902098457818659, 4.533259944911924, 5.233855172995966, 4.148714150790077, 5.503332368386696, 3.992339256060489)',
      'cubicTo(5.772809563777424, 3.835964361330901, 5.938688324464454, 3.9317373149934203, 5.937999653971664, 4.243301884600293)',
      'cubicTo(5.937310983478875, 4.554866454207166, 5.77016047559299, 5.034450471415502, 5.499999892905285, 5.499999740953291)',
      'close()'
    ]);
  });
}
