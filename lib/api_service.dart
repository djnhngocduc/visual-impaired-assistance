import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

class ApiService {
  final _dio = Dio(
    BaseOptions(
      baseUrl: 'https://nduc1311-llava-fastapi.hf.space/',   // ← sửa IP hoặc domain
      connectTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
    ),
  );

  Future<String> sendPrompt({
    required String prompt,
    required Uint8List imageBytes,
  }) async {
    final body = {
      'prompt': prompt,
      'image' : base64Encode(imageBytes),      // ⬅️  chuyển ảnh → Base64
    };

    final res = await _dio.post('/process', data: body);
    return (res.data['response'] as String).trim();
  }
}