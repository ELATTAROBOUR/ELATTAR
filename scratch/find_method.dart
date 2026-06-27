import 'dart:io';

void main() {
  final file = File('lib/keygen_main.dart');
  final lines = file.readAsLinesSync();
  
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.contains('_generateLicense(') || line.contains('_generateLicense()') || (line.contains('_generateLicense') && line.contains('void'))) {
      print('Found at line ${i + 1}');
      for (var j = i; j < i + 60 && j < lines.length; j++) {
        print('${j + 1}: ${lines[j]}');
      }
      break;
    }
  }
}
