library exampledasdf;

import 'package:path_parsing/path_parsing.dart';

part 'gen_test.svg_path.g.dart';

class Path {
  void lineTo(double d, double dd) {}

  void moveTo(double a, double a2) {}

  void cubicTo(double a, double b, double c, double d, double e, double f) {}

  void close() {}
}

@SvgPath('M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z')
Path get droplet => _$droplet;

class Paths {
  @SvgPath('M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z')
  Path get droplet => _$Paths_droplet;
}
