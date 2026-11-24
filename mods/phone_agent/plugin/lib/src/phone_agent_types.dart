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

/// 截图中标注的最近一次坐标点击落点（归一化 `[0, 1]` 坐标）。
class PhoneAgentTapMarker {
  const PhoneAgentTapMarker({
    required this.index,
    required this.action,
    required this.x,
    required this.y,
  });

  factory PhoneAgentTapMarker.fromMap(Map<Object?, Object?> map) {
    final index = _positiveInt(map['index'], 'recentTaps.index');
    final action = map['action'];
    if (action is! String || action.isEmpty) {
      throw const PhoneAgentException(
        'invalid_response',
        'The phone agent response contained an invalid recentTaps.action.',
      );
    }
    return PhoneAgentTapMarker(
      index: index,
      action: action,
      x: _normalizedDouble(map['x'], 'recentTaps.x'),
      y: _normalizedDouble(map['y'], 'recentTaps.y'),
    );
  }

  final int index;
  final String action;
  final double x;
  final double y;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'index': index,
    'action': action,
    'x': x,
    'y': y,
  };
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
    this.recentTaps = const <PhoneAgentTapMarker>[],
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
    final rawRecentTaps = map['recentTaps'];
    final recentTaps = <PhoneAgentTapMarker>[];
    if (rawRecentTaps is List) {
      for (final item in rawRecentTaps) {
        if (item is Map) {
          recentTaps.add(PhoneAgentTapMarker.fromMap(item));
        }
      }
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
      recentTaps: List<PhoneAgentTapMarker>.unmodifiable(recentTaps),
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

  /// 本次截图上已标注的同窗口近期坐标点击落点。
  final List<PhoneAgentTapMarker> recentTaps;

  @override
  String toString() =>
      'PhoneAgentScreenshot(${bytes.length} bytes, '
      'image: ${imageWidth}x$imageHeight, '
      'screen: ${screenWidth}x$screenHeight, package: $packageName, '
      'recentTaps: ${recentTaps.length})';
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

double _normalizedDouble(Object? value, String name) {
  if (value is num && value.isFinite) {
    final normalized = value.toDouble();
    if (normalized >= 0.0 && normalized <= 1.0) return normalized;
  }
  throw PhoneAgentException(
    'invalid_response',
    'The phone agent response contained an invalid $name.',
  );
}
