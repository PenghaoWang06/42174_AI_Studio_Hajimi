import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/card_detection.dart';
import '../models/contact.dart';
import '../models/ocr_result.dart';

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '${base.path}$path',
      queryParameters: query,
    );
  }

  String absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '$baseUrl$path';
  }

  Future<void> healthCheck() async {
    final response = await http.get(_uri('/health'));
    _ensureSuccess(response);
  }

  Future<CardDetectionResponse> detectCard(XFile file) async {
    final bytes = await file.readAsBytes();
    final request = http.MultipartRequest('POST', _uri('/cards/detect'));
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: _imageFilename(file),
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _ensureSuccess(response);
    return CardDetectionResponse.fromJson(_decodeMap(response.body));
  }

  Future<OcrResult> extractCard({
    required String imagePath,
    required String provider,
  }) async {
    final response = await http.post(
      _uri('/cards/extract'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'image_path': imagePath,
        'provider': provider,
      }),
    );
    _ensureSuccess(response);
    return OcrResult.fromJson(_decodeMap(response.body));
  }

  Future<Contact> createContact(ContactPayload payload) async {
    final response = await http.post(
      _uri('/contacts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload.toJson()),
    );
    _ensureSuccess(response);
    return Contact.fromJson(_decodeMap(response.body));
  }

  Future<Contact> updateContact(int contactId, ContactPayload payload) async {
    final response = await http.put(
      _uri('/contacts/$contactId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload.toJson()),
    );
    _ensureSuccess(response);
    return Contact.fromJson(_decodeMap(response.body));
  }

  Future<void> deleteContact(int contactId) async {
    final response = await http.delete(_uri('/contacts/$contactId'));
    _ensureSuccess(response);
  }

  Future<List<Contact>> listContacts({String query = ''}) async {
    final path = query.trim().isEmpty ? '/contacts' : '/contacts/search';
    final response = await http.get(
      _uri(
        path,
        query.trim().isEmpty ? null : {'q': query.trim()},
      ),
    );
    _ensureSuccess(response);
    final data = _decodeMap(response.body);
    final items = data['items'] as List<dynamic>? ?? [];
    return items
        .map((item) => Contact.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    try {
      final data = _decodeMap(response.body);
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) {
        throw ApiException(detail);
      }
    } catch (error) {
      if (error is ApiException) {
        rethrow;
      }
    }

    throw ApiException('Request failed with status ${response.statusCode}');
  }

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('Expected a JSON object');
  }

  String _imageFilename(XFile file) {
    final name = file.name.trim();
    final lowerName = name.toLowerCase();
    final hasSupportedSuffix = lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.webp');
    if (name.isNotEmpty && hasSupportedSuffix) {
      return name;
    }
    return 'camera_capture.jpg';
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PickedImage {
  const PickedImage({
    required this.file,
    required this.bytes,
  });

  final XFile file;
  final Uint8List bytes;
}
