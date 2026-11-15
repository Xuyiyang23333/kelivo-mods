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

/// 一条已获用户批准的应用记录。只含身份元数据，不含节点文本、截图或界面内容。
class PhoneAgentApprovedApp {
  const PhoneAgentApprovedApp({
    required this.packageName,
    required this.signingPrefix,
    required this.approvedAt,
    required this.lastApprovedAt,
    this.sourceAssistantId,
  });

  factory PhoneAgentApprovedApp.fromMap(Map<String, dynamic> map) {
    final packageName = map['package_name'];
    if (packageName is! String || packageName.isEmpty) {
      throw const PhoneAgentException(
        'invalid_response',
        'The approved app entry did not contain a package name.',
      );
    }
    final prefix = map['signing_prefix'];
    if (prefix is! String || prefix.isEmpty) {
      throw const PhoneAgentException(
        'invalid_response',
        'The approved app entry did not contain a signing prefix.',
      );
    }
    return PhoneAgentApprovedApp(
      packageName: packageName,
      signingPrefix: prefix,
      approvedAt: _nullableInt(map['approved_at']) ?? 0,
      lastApprovedAt: _nullableInt(map['last_approved_at']) ?? 0,
      sourceAssistantId: map['source_assistant_id'] is String
          ? map['source_assistant_id'] as String
          : null,
    );
  }

  final String packageName;

  /// 签名证书 SHA-256 的前 8 位十六进制字符；完整哈希不离开原生侧。
  final String signingPrefix;

  final int approvedAt;
  final int lastApprovedAt;

  /// 首次批准该应用的助手 id；白名单全局共享，这里只用于分组展示。
  final String? sourceAssistantId;

  @override
  String toString() =>
      'PhoneAgentApprovedApp($packageName, $signingPrefix, '
      'approvedAt: $approvedAt, lastApprovedAt: $lastApprovedAt, '
      'sourceAssistantId: $sourceAssistantId)';
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

int? _nullableInt(Object? value) => value is int ? value : null;
