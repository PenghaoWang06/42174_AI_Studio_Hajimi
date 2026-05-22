class CardDetectionResponse {
  const CardDetectionResponse({
    required this.imagePath,
    required this.imageUrl,
    required this.imageWidth,
    required this.imageHeight,
    required this.detections,
  });

  factory CardDetectionResponse.fromJson(Map<String, dynamic> json) {
    final detections = json['detections'] as List<dynamic>? ?? [];
    return CardDetectionResponse(
      imagePath: json['image_path'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      imageWidth: json['image_width'] as int? ?? 1,
      imageHeight: json['image_height'] as int? ?? 1,
      detections: detections
          .map((item) => DetectionBox.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String imagePath;
  final String imageUrl;
  final int imageWidth;
  final int imageHeight;
  final List<DetectionBox> detections;
}

class DetectionBox {
  const DetectionBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
    required this.className,
    required this.cropPath,
    required this.cropUrl,
  });

  factory DetectionBox.fromJson(Map<String, dynamic> json) {
    return DetectionBox(
      x1: (json['x1'] as num?)?.toDouble() ?? 0,
      y1: (json['y1'] as num?)?.toDouble() ?? 0,
      x2: (json['x2'] as num?)?.toDouble() ?? 0,
      y2: (json['y2'] as num?)?.toDouble() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      classId: json['class_id'] as int? ?? 0,
      className: json['class_name'] as String? ?? 'Business Card',
      cropPath: json['crop_path'] as String? ?? '',
      cropUrl: json['crop_url'] as String? ?? '',
    );
  }

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double confidence;
  final int classId;
  final String className;
  final String cropPath;
  final String cropUrl;
}
