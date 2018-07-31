// Copyright (c) 2016, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build_runner/build_runner.dart';
import 'package:source_gen/source_gen.dart';
import 'package:path_parsing/builder.dart';

/// Build the generated files in the built_value chat example.
Future main(List<String> args) async {
  await build(
    <BuilderApplication>[
      new BuilderApplication.forBuilder(
        'svg_path',
        [svgPath],
        (_) => true,
      )
    ],
    buildDirs: ['example'],
    deleteFilesByDefault: true,
  );
}
