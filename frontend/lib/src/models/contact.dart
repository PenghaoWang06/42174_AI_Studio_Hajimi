class Contact {
  const Contact({
    required this.id,
    this.name,
    this.company,
    this.email,
    this.phone,
    this.rawText,
    this.imagePath,
    this.cropPath,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String?,
      company: json['company'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      rawText: json['raw_text'] as String?,
      imagePath: json['image_path'] as String?,
      cropPath: json['crop_path'] as String?,
    );
  }

  final int id;
  final String? name;
  final String? company;
  final String? email;
  final String? phone;
  final String? rawText;
  final String? imagePath;
  final String? cropPath;
}

class ContactPayload {
  const ContactPayload({
    this.name,
    this.company,
    this.email,
    this.phone,
    this.rawText,
    this.imagePath,
    this.cropPath,
  });

  final String? name;
  final String? company;
  final String? email;
  final String? phone;
  final String? rawText;
  final String? imagePath;
  final String? cropPath;

  Map<String, dynamic> toJson() {
    return {
      'name': _blankToNull(name),
      'company': _blankToNull(company),
      'email': _blankToNull(email),
      'phone': _blankToNull(phone),
      'raw_text': _blankToNull(rawText),
      'image_path': _blankToNull(imagePath),
      'crop_path': _blankToNull(cropPath),
    };
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
