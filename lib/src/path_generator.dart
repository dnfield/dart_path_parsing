import 'dart:async';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:path_parsing/path_parsing.dart';
import 'package:source_gen/source_gen.dart';

Builder svgPathSharedPartBuilder({String formatOutput(String code)}) {
  return new PartBuilder(
      <Generator>[new SvgPathGenerator()], '.svg_path.g.dart',
      formatOutput: formatOutput,
      header: '// ignore_for_file: non_constant_identifier_names\n'
          '// GENERATED CODE - DO NOT MODIFY BY HAND\n');
}

class FlutterPathGenProxy extends PathProxy {
  FlutterPathGenProxy() {
    code = new StringBuffer();
    code.write('new Path()');
  }

  StringBuffer code;

  @override
  void close() {
    code.write('..close()');
  }

  @override
  void cubicTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    code.write('..cubicTo($x1, $y1, $x2, $y2, $x3, $y3)');
  }

  @override
  void lineTo(double x, double y) {
    code.write('..lineTo($x, $y)');
  }

  @override
  void moveTo(double x, double y) {
    code.write('..moveTo($x, $y)');
  }

  @override
  String toString() {
    return code.toString();
  }
}

class SvgPathGenerator extends Generator {
  final TypeChecker _checker = const TypeChecker.fromRuntime(SvgPath);

  void checkField(Element field, StringBuffer buffer, String friendlyName) {
    DartObject annotation = _checker.firstAnnotationOf(field);
    if (annotation == null && field is FieldElement) {
      annotation = _checker.firstAnnotationOf(field.getter);
    }
    if (annotation != null) {
      buffer.writeln('Path _\$$friendlyName = ');
      final FlutterPathGenProxy proxy = new FlutterPathGenProxy();
      writeSvgPathDataToPath(
        annotation.getField('data').toStringValue(),
        proxy,
      );
      buffer.writeln('$proxy;');
    }
  }

  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) async {
    final StringBuffer buffer = new StringBuffer();
    for (Element el in library.allElements) {
      if (el is ClassElement) {
        for (FieldElement field in el.fields) {
          checkField(field, buffer, '${el.name}_${field.name}');
        }
      } else {
        checkField(el, buffer, el.name);
      }
    }
    return buffer.toString();
  }
}

class SvgPathGenerator2 extends GeneratorForAnnotation<SvgPath> {
  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    print(element);

    final String name = element.name;
    if (element is! FieldElement) {
      throw new InvalidGenerationSourceError('Generator cannot target `$name`.',
          todo: 'Remove the SvgPath annotation from `$name`.',
          element: element);
    }

    final FlutterPathGenProxy proxy = new FlutterPathGenProxy();
    writeSvgPathDataToPath(annotation.read('data').stringValue, proxy);

    print(proxy);
    return 'static Path $name = $proxy;';
  }
}
