// Ollama HTTP API 客户端
//
// 借鉴 AppFlowy Vault 的本地 Ollama 集成方案：
// 所有 LLM 推理通过本地 Ollama HTTP API 完成，Dart 端仅负责请求编排与 UI。
// 来源: https://github.com/AppFlowy/AppFlowy
//
// Ollama API 文档: https://github.com/ollama/ollama/blob/main/docs/api.md
// - POST /api/generate  单轮生成（流式/非流式）
// - POST /api/chat      多轮对话（流式/非流式）
// - POST /api/embeddings 文本向量化
// - GET  /api/tags      列出本地已安装模型

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Ollama 调用异常
class OllamaException implements Exception {
  final String message;
  final int? statusCode;

  const OllamaException(this.message, {this.statusCode});

  @override
  String toString() =>
      'OllamaException($statusCode): $message';
}

/// Ollama HTTP API 客户端
///
/// 设计要点：
/// 1. 所有请求带超时（默认 120s，生成式模型推理较慢）
/// 2. 流式生成基于 NDJSON（每行一个 JSON 对象），支持取消
/// 3. [isAvailable] 用于在 UI 层判断是否展示 AI 入口
class OllamaClient {
  OllamaClient({
    String baseUrl = 'http://localhost:11434',
    String model = 'llama3',
    Duration timeout = const Duration(seconds: 120),
    http.Client? httpClient,
  })  : _baseUrl = baseUrl,
        _model = model,
        _timeout = timeout,
        _httpClient = httpClient ?? http.Client();

  String _baseUrl;
  String _model;
  final Duration _timeout;
  final http.Client _httpClient;

  /// 当前 Ollama 服务地址
  String get baseUrl => _baseUrl;

  /// 动态切换 Ollama 服务地址（由设置页调用）
  set baseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) _baseUrl = trimmed;
  }

  /// 当前使用的生成模型
  String get model => _model;

  /// 动态切换生成模型（由设置页调用）
  set model(String value) {
    if (value.trim().isNotEmpty) _model = value.trim();
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  /// 检查 Ollama 服务是否可用
  ///
  /// 通过 GET /api/tags 探测，成功返回 true。
  /// 任何网络错误或非 2xx 状态码均视为不可用，避免抛出异常打断 UI。
  Future<bool> isAvailable() async {
    try {
      final resp = await _httpClient
          .get(_uri('/api/tags'))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// 列出本地已安装模型
  ///
  /// 返回模型名称列表（如 ['llama3', 'mistral', 'nomic-embed-text']）。
  Future<List<String>> listModels() async {
    final resp = await _httpClient
        .get(_uri('/api/tags'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw OllamaException(
        '列出模型失败',
        statusCode: resp.statusCode,
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final models = data['models'] as List<dynamic>? ?? [];
    return models
        .map((m) => (m as Map<String, dynamic>)['name'] as String?)
        .whereType<String>()
        .toList();
  }

  /// 单轮生成（非流式）
  ///
  /// [prompt] 用户提示词；[system] 系统提示词（可选）；
  /// [maxTokens] 限制生成 token 数（可选，Ollama 通过 options.num_predict 传入）。
  Future<String> generate({
    required String prompt,
    String? system,
    int? maxTokens,
  }) async {
    final body = <String, dynamic>{
      'model': _model,
      'prompt': prompt,
      'stream': false,
    };
    if (system != null && system.isNotEmpty) {
      body['system'] = system;
    }
    if (maxTokens != null) {
      body['options'] = {'num_predict': maxTokens};
    }
    final resp = await _httpClient
        .post(
          _uri('/api/generate'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw OllamaException(
        '生成失败: ${resp.body}',
        statusCode: resp.statusCode,
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    // Ollama /api/generate 非流式响应字段为 response
    return (data['response'] as String?) ?? '';
  }

  /// 多轮对话（非流式）
  ///
  /// 简化版：将 [prompt] 作为单条 user 消息发送到 /api/chat。
  /// 复杂多轮上下文由调用方拼接后通过 [system] 注入。
  Future<String> chat({
    required String prompt,
    String? system,
    int? maxTokens,
  }) async {
    final messages = <Map<String, String>>[];
    if (system != null && system.isNotEmpty) {
      messages.add({'role': 'system', 'content': system});
    }
    messages.add({'role': 'user', 'content': prompt});
    final body = <String, dynamic>{
      'model': _model,
      'messages': messages,
      'stream': false,
    };
    if (maxTokens != null) {
      body['options'] = {'num_predict': maxTokens};
    }
    final resp = await _httpClient
        .post(
          _uri('/api/chat'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw OllamaException(
        '对话失败: ${resp.body}',
        statusCode: resp.statusCode,
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final message = data['message'] as Map<String, dynamic>?;
    return (message?['content'] as String?) ?? '';
  }

  /// 流式生成
  ///
  /// 返回逐 token 输出的 Stream，调用方可监听并实时渲染。
  /// 取消方式：取消 StreamSubscription 即可终止读取；
  /// 配合 [CancelToken] 可主动中断底层 HTTP 连接。
  Stream<String> generateStream({
    required String prompt,
    String? system,
    int? maxTokens,
    CancelToken? cancelToken,
  }) {
    final controller = StreamController<String>();
    final client = http.Client();
    cancelToken?.bind(() {
      if (!controller.isClosed) {
        controller.addError(const OllamaException('生成已取消'));
        controller.close();
      }
      client.close();
    });
    () async {
      try {
        final body = <String, dynamic>{
          'model': _model,
          'prompt': prompt,
          'stream': true,
        };
        if (system != null && system.isNotEmpty) {
          body['system'] = system;
        }
        if (maxTokens != null) {
          body['options'] = {'num_predict': maxTokens};
        }
        final request = http.Request('POST', _uri('/api/generate'));
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
        final response = await client.send(request).timeout(_timeout);
        if (response.statusCode != 200) {
          final bodyText = await response.stream.bytesToString();
          controller.addError(OllamaException(
            '流式生成失败: $bodyText',
            statusCode: response.statusCode,
          ));
          await controller.close();
          return;
        }
        // NDJSON: 每行一个 JSON 对象，字段 response 为当前 token 片段
        await for (final chunk in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (controller.isClosed) break;
          if (chunk.isEmpty) continue;
          try {
            final data = jsonDecode(chunk) as Map<String, dynamic>;
            final piece = data['response'] as String?;
            if (piece != null && piece.isNotEmpty) {
              controller.add(piece);
            }
            // done=true 表示生成结束
            if (data['done'] == true) {
              break;
            }
          } catch (_) {
            // 单行解析失败时跳过，避免整体中断
            continue;
          }
        }
        if (!controller.isClosed) await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      } finally {
        client.close();
      }
    }();
    return controller.stream;
  }

  /// 文本向量化
  ///
  /// 调用 /api/embeddings 端点，返回浮点向量。
  /// [model] 默认使用 nomic-embed-text，可由 EmbeddingService 覆盖。
  Future<List<double>> embed({
    required String text,
    String? model,
  }) async {
    final body = <String, dynamic>{
      'model': model ?? 'nomic-embed-text',
      'prompt': text,
    };
    final resp = await _httpClient
        .post(
          _uri('/api/embeddings'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw OllamaException(
        '向量化失败: ${resp.body}',
        statusCode: resp.statusCode,
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final embedding = data['embedding'] as List<dynamic>? ?? [];
    return embedding.map((e) => (e as num).toDouble()).toList();
  }

  void dispose() {
    _httpClient.close();
  }
}

/// 取消令牌
///
/// 用于主动取消流式生成：调用 [cancel] 触发绑定的回调，
/// 关闭底层 HTTP 连接并结束 Stream。
class CancelToken {
  void Function()? _onCancel;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  /// 绑定取消回调（由 OllamaClient 内部调用）
  void bind(void Function() onCancel) {
    _onCancel = onCancel;
    if (_isCancelled) {
      _onCancel?.call();
    }
  }

  /// 触发取消
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _onCancel?.call();
  }
}
