import 'dart:io';

// 获取系统文档目录
Future<Directory> getDocumentsDir() async {
  // 省略平台判断，直接调用 path_provider
  // 也可配合 Platform.isWindows/Platform.isMacOS
  // eg: getApplicationDocumentsDirectory()
  return Directory('${Platform.environment['USERPROFILE']}/Documents');
}

// 路径拼接，确保目录存在
Future<File> safeFile(String folder, String file) async {
  final dir = Directory(folder);
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  return File('${dir.path}/$file');
}
