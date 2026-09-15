import 'dart:io';

void main() {
  final dir = Directory('c:/Users/user/Downloads/onsite_app_compile_fixes/onsite_app/frontend/lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  
  for (final file in files) {
    var content = file.readAsStringSync();
    
    // Find Center( child: Column( children:
    final regex = RegExp(r'Center\(\s*child:\s*Column\(\s*children:');
    if (regex.hasMatch(content)) {
      print('Found in ${file.path}');
      content = content.replaceAll(regex, 'Center(\nchild: Column(\nmainAxisSize: MainAxisSize.min,\nchildren:');
      file.writeAsStringSync(content);
    }
  }
}
