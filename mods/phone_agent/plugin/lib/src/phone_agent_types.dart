import 'dart:typed_data';

/// 独立手机 Agent 原生服务的可用状态。
class PhoneAgentStatus {
  const PhoneAgentStatus({
    required this.supported,
    required this.enabled,
    required this.connected,
    required this.androidSdkInt,
  });

  factory PhoneAgentStatus.fromMap(Map<String, dynamic> map) {
    return PhoneAgentStatus(
      supported: map['supported'] == true,
      enabled: map['enabled'] == true,
      connected: map['connected'] == true,
      androidSdkInt: _positiveInt(map['androidSdkInt'], 'androidSdkInt'),
    );
  }

  /// 当前系统是否支持截图所需的 API 30+。
  final bool supported;

  /// 用户是否在系统无障碍设置中启用了独立服务。
  final bool enabled;

  /// 服务是否已连接并可以立即执行请求。
  final bool connected;

  final int androidSdkInt;

  bool get ready => enabled && connected;

  @override
  String toString() =>
      'PhoneAgentStatus(supported: $supported, enabled: $enabled, '
      'connected: $connected, androidSdkInt: $androidSdkInt)';
}

/// 一次截图结果。坐标以 [screenWidth] × [screenHeight] 为基准。
class PhoneAgentScreenshot {
  const PhoneAgentScreenshot({
    required this.bytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.screenWidth,
    required this.screenHeight,
    this.packageName,
  });

  factory PhoneAgentScreenshot.fromMap(Map<String, dynamic> map) {
    final rawBytes = map['bytes'];
    final bytes = switch (rawBytes) {
      Uint8List value => value,
      List<int> value => Uint8List.fromList(value),
      _ => null,
    };
    if (bytes == null || bytes.isEmpty) {
      throw const PhoneAgentException(
        'invalid_response',
        'The screenshot result did not contain image bytes.',
      );
    }
    return PhoneAgentScreenshot(
      bytes: bytes,
      imageWidth: _positiveInt(map['imageWidth'], 'imageWidth'),
      imageHeight: _positiveInt(map['imageHeight'], 'imageHeight'),
      screenWidth: _positiveInt(map['screenWidth'], 'screenWidth'),
      screenHeight: _positiveInt(map['screenHeight'], 'screenHeight'),
      packageName: map['packageName'] is String
          ? map['packageName'] as String
          : null,
    );
  }

  final Uint8List bytes;

  /// 缩放后图片的宽高，长边不超过 1600。
  final int imageWidth;
  final int imageHeight;

  /// 截图对应的物理屏幕宽高。
  final int screenWidth;
  final int screenHeight;

  /// 截图时的前台包名。
  final String? packageName;

  @override
  String toString() =>
      'PhoneAgentScreenshot(${bytes.length} bytes, '
      'image: ${imageWidth}x$imageHeight, '
      'screen: ${screenWidth}x$screenHeight, package: $packageName)';
}

/// 原生结构化错误。错误码为稳定的 snake_case 字符串。
class PhoneAgentException implements Exception {
  const PhoneAgentException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'PhoneAgentException($code): $message';
}

int _positiveInt(Object? value, String name) {
  if (value is int && value > 0) return value;
  throw PhoneAgentException(
    'invalid_response',
    'The phone agent response contained an invalid $name.',
  );
}
