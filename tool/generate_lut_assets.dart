import 'dart:io';

import 'package:image/image.dart' as img;

import '../lib/features/editor/beauty_engine/presets/lut_square_table.dart';

void main() {
  final outDir = Directory('assets/filters/lut');
  outDir.createSync(recursive: true);

  _write(outDir, 'natural.png', LutSquareTable.buildNatural());
  _write(
    outDir,
    'cinema_teal_orange.png',
    LutSquareTable.buildCinemaTealOrange(),
  );

  stdout.writeln('LUT assets gerados em ${outDir.path}');
}

void _write(Directory dir, String name, img.Image image) {
  File('${dir.path}/$name').writeAsBytesSync(img.encodePng(image));
}
