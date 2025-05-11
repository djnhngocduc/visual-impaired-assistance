import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

class OpenRouterService {
  final Dio _dio;

  OpenRouterService(String apiKey)
      : _dio = Dio(BaseOptions(
    baseUrl: 'https://openrouter.ai/api/v1',
    connectTimeout: const Duration(seconds: 60),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    },
  ));

  /// Gửi prompt (text) kết hợp ảnh URL đến OpenRouter,
  /// trả về String content của assistant.
  Future<String> sendPrompt({
    required String prompt,
    required Uint8List jpegBytes,
    String model = 'meta-llama/llama-4-scout:free',
  }) async {
    final b64 = base64Encode(jpegBytes);
    final body = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': prompt,
            },
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$b64',
              },
            },
          ],
        }
      ],
    };

    final resp = await _dio.post(
      '/chat/completions',
      data: jsonEncode(body),
    );

    if (resp.statusCode == 200) {
      final List choices = resp.data['choices'] as List;
      final String message = choices[0]['message']['content'] as String;
      String cleaned = message
          .replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (m) => m.group(1)!)
          .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
          .replaceAll('*', '')
          .replaceAll(r'\$1', '');

      print(cleaned);
      return cleaned;
    }
    throw Exception(
      'OpenRouter API error: ${resp.statusCode} ${resp.data}',
    );
  }
}