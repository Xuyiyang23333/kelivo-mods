import 'paths.dart';

/// Flutter 在合成树中自动生成、且不参与 Mod 内容哈希的已跟踪文件。
///
/// 只列根项目实际生成的注册文件；依赖目录中的示例工程不在允许范围内。
const Set<String> flutterGeneratedBuildArtifacts = <String>{
  'linux/flutter/generated_plugin_registrant.cc',
  'linux/flutter/generated_plugin_registrant.h',
  'linux/flutter/generated_plugins.cmake',
  'macos/Flutter/GeneratedPluginRegistrant.swift',
  'windows/flutter/generated_plugin_registrant.cc',
  'windows/flutter/generated_plugin_registrant.h',
  'windows/flutter/generated_plugins.cmake',
};

/// 判断已跟踪文件是否属于允许变化的 Flutter 构建产物。
///
/// `pubspec.lock` 允许出现在任意嵌套包中；注册文件只允许上述精确路径。
bool isAllowedBuildArtifact(String repoRelativePath) {
  final normalized = toPosixPath(repoRelativePath);
  if (basename(normalized) == 'pubspec.lock') return true;
  return flutterGeneratedBuildArtifacts.contains(normalized);
}
