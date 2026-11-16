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

/// 一条待用户处理的批准请求。只含应用身份与关联上下文，不含节点文本、截图或界面内容。
class PhoneAgentApprovalRequest {
  const PhoneAgentApprovalRequest({
    required this.requestId,
    required this.packageName,
    required this.createdAt,
    required this.expiresAt,
    required this.state,
    this.signingPrefix,
    this.signingAvailable = false,
    this.displayName,
    this.toolCallId,
    this.conversationId,
    this.approvalAssistantId,
    this.failureReason,
  });

  factory PhoneAgentApprovalRequest.fromMap(Map<String, dynamic> map) {
    final requestId = map['request_id'];
    if (requestId is! String || requestId.isEmpty) {
      throw const PhoneAgentException(
        'invalid_response',
        'The approval request did not contain a request id.',
      );
    }
    final packageName = map['package_name'];
    if (packageName is! String || packageName.isEmpty) {
      throw const PhoneAgentException(
        'invalid_response',
        'The approval request did not contain a package name.',
      );
    }
    return PhoneAgentApprovalRequest(
      requestId: requestId,
      packageName: packageName,
      signingPrefix: map['signing_prefix'] is String
          ? map['signing_prefix'] as String
          : null,
      signingAvailable: map['signing_available'] == true,
      displayName: map['display_name'] is String
          ? map['display_name'] as String
          : null,
      toolCallId: map['tool_call_id'] is String
          ? map['tool_call_id'] as String
          : null,
      conversationId: map['conversation_id'] is String
          ? map['conversation_id'] as String
          : null,
      approvalAssistantId: map['approval_assistant_id'] is String
          ? map['approval_assistant_id'] as String
          : null,
      createdAt: _nullableInt(map['created_at']) ?? 0,
      expiresAt: _nullableInt(map['expires_at']) ?? 0,
      state: map['state'] is String ? map['state'] as String : 'pending',
      failureReason: map['failure_reason'] is String
          ? map['failure_reason'] as String
          : null,
    );
  }

  final String requestId;
  final String packageName;

  /// 签名证书 SHA-256 前 8 位；解析失败时为 null。
  final String? signingPrefix;

  final bool signingAvailable;
  final String? displayName;

  /// 触发该请求的工具调用 id；聊天卡片据此把它挂到对应工具结果上。
  final String? toolCallId;

  final String? conversationId;
  /// 创建请求时的助手快照，作为“首次批准来源”写入白名单。与审计用的实时助手 id
  /// 语义不同。
  final String? approvalAssistantId;

  final int createdAt;
  final int expiresAt;

  /// `pending` / `approved` / `denied` / `expired` / `superseded` / `dismissed` / `failed`。
  final String state;

  /// 批准写入被拒绝时的原因（`signing_unavailable` / `signing_mismatch` / `pre_approved`）。
  final String? failureReason;

  bool get isPending => state == 'pending';

  bool get isApproved => state == 'approved';

  PhoneAgentApprovalRequest copyWith({String? state, String? failureReason}) {
    return PhoneAgentApprovalRequest(
      requestId: requestId,
      packageName: packageName,
      signingPrefix: signingPrefix,
      signingAvailable: signingAvailable,
      displayName: displayName,
      toolCallId: toolCallId,
      conversationId: conversationId,
      approvalAssistantId: approvalAssistantId,
      createdAt: createdAt,
      expiresAt: expiresAt,
      state: state ?? this.state,
      failureReason: failureReason ?? this.failureReason,
    );
  }

  @override
  String toString() =>
      'PhoneAgentApprovalRequest($requestId, $packageName, '
      'prefix: $signingPrefix, state: $state)';
}

/// 原生结构化错误。错误码为稳定的 snake_case 字符串。
///
/// [details] 是可选的结构化载荷。当前只有 `permission_required` 使用：它带上应用身份
/// （`package_name`、`signing_prefix`、`display_name`、`signing_available`、
/// `observation`），供批准卡片与通知栏展示与写入。不含节点文本、截图或界面内容。
class PhoneAgentException implements Exception {
  const PhoneAgentException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Map<String, dynamic>? details;

  /// `permission_required` 的结构化身份；其他错误码返回 null。
  PhoneAgentPermissionIdentity? get permissionIdentity {
    if (code != PhoneAgentErrorCodes.permissionRequired) return null;
    return PhoneAgentPermissionIdentity.tryParse(details);
  }

  @override
  String toString() => 'PhoneAgentException($code): $message';
}

/// 错误码常量。只列需要在 Dart 侧做分支判断的码。
class PhoneAgentErrorCodes {
  const PhoneAgentErrorCodes._();

  static const String permissionRequired = 'permission_required';
  static const String approvalNotFound = 'approval_not_found';
  static const String preApproved = 'pre_approved';
}

/// `permission_required` 的应用身份：包名、签名前缀与可选显示名。
///
/// 字段与 plan 7.5.4 允许的身份一致，**不含**节点文本、窗口标题、截图或界面内容。
/// 签名解析失败时 [signingPrefix] 为 null 且 [signingAvailable] 为 false。
class PhoneAgentPermissionIdentity {
  const PhoneAgentPermissionIdentity({
    required this.packageName,
    required this.signingPrefix,
    required this.signingAvailable,
    this.displayName,
    this.observation = false,
  });

  static PhoneAgentPermissionIdentity? tryParse(Map<String, dynamic>? details) {
    if (details == null) return null;
    final packageName = details['package_name'];
    if (packageName is! String || packageName.trim().isEmpty) return null;
    final prefix = details['signing_prefix'];
    return PhoneAgentPermissionIdentity(
      packageName: packageName,
      signingPrefix: prefix is String && prefix.isNotEmpty ? prefix : null,
      signingAvailable: details['signing_available'] == true,
      displayName: details['display_name'] is String
          ? details['display_name'] as String
          : null,
      observation: details['observation'] == true,
    );
  }

  final String packageName;

  /// 签名证书 SHA-256 的前 8 位十六进制字符；解析失败时为 null。
  final String? signingPrefix;

  final bool signingAvailable;
  final String? displayName;

  /// true 表示这次请求来自读树/截图（观察），false 表示来自输入。
  final bool observation;

  @override
  String toString() =>
      'PhoneAgentPermissionIdentity($packageName, prefix: $signingPrefix, '
      'signingAvailable: $signingAvailable, observation: $observation)';
}

int _positiveInt(Object? value, String name) {
  if (value is int && value > 0) return value;
  throw PhoneAgentException(
    'invalid_response',
    'The phone agent response contained an invalid $name.',
  );
}

int? _nullableInt(Object? value) => value is int ? value : null;
