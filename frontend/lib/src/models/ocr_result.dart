class OcrResult {
  const OcrResult({
    required this.provider,
    required this.rawText,
    required this.fields,
    required this.lines,
  });

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    final lines = json['lines'] as List<dynamic>? ?? [];
    return OcrResult(
      provider: json['provider'] as String? ?? '',
      rawText: json['raw_text'] as String? ?? '',
      fields: ExtractedFields.fromJson(
        json['fields'] as Map<String, dynamic>? ?? {},
      ),
      lines: lines
          .map((item) => OcrLine.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String provider;
  final String rawText;
  final ExtractedFields fields;
  final List<OcrLine> lines;
}

class ExtractedFields {
  const ExtractedFields({
    this.name,
    this.company,
    this.email,
    this.phone,
  });

  factory ExtractedFields.fromJson(Map<String, dynamic> json) {
    return ExtractedFields(
      name: json['name'] as String?,
      company: json['company'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
    );
  }

  final String? name;
  final String? company;
  final String? email;
  final String? phone;
}

class OcrLine {
  const OcrLine({
    required this.text,
    this.confidence,
  });

  factory OcrLine.fromJson(Map<String, dynamic> json) {
    return OcrLine(
      text: json['text'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  final String text;
  final double? confidence;
}
