import 'dart:io';

void main() {
  final file = File('lib/views/dashboard_overview_view.dart');
  final lines = file.readAsLinesSync();

  for (int i = 383; i <= 395; i++) {
    if (i < lines.length) {
      final line = lines[i];
      int spaces = 0;
      while (spaces < line.length && line[spaces] == ' ') spaces++;
      print('Line ${i + 1}: $spaces spaces |${line.trimLeft()}|');
    }
  }

  print('---');

  for (int i = 545; i <= 560; i++) {
    if (i < lines.length) {
      final line = lines[i];
      int spaces = 0;
      while (spaces < line.length && line[spaces] == ' ') spaces++;
      print('Line ${i + 1}: $spaces spaces |${line.trimLeft()}|');
    }
  }

  print('---');

  for (int i = 882; i <= 900; i++) {
    if (i < lines.length) {
      final line = lines[i];
      int spaces = 0;
      while (spaces < line.length && line[spaces] == ' ') spaces++;
      print('Line ${i + 1}: $spaces spaces |${line.trimLeft()}|');
    }
  }
}
