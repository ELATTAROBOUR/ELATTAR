import 'dart:io';

void main() {
  final file = File('lib/keygen_main.dart');
  final lines = file.readAsLinesSync();
  
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.toLowerCase().contains('git')) {
      print('Line ${i + 1}: $line');
    }
  }
}
