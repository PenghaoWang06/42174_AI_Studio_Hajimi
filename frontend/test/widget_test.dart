import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:snapfolio_frontend/src/core/api_client.dart';
import 'package:snapfolio_frontend/src/models/card_detection.dart';
import 'package:snapfolio_frontend/src/models/contact.dart';
import 'package:snapfolio_frontend/src/models/ocr_result.dart';
import 'package:snapfolio_frontend/src/screens/home_screen.dart';

void main() {
  testWidgets('SnapFolio app renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          apiClient: _FakeApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SnapFolio Business Card Scanner'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
  });

  testWidgets('saved contact opens the detail page',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          apiClient: _FakeApiClient(
            contacts: const [
              Contact(
                id: 1,
                name: 'Ada Lovelace',
                company: 'Analytical Engines',
                email: 'ada@example.com',
                phone: '+1 555 0100',
                rawText: 'Ada Lovelace\nAnalytical Engines',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();

    expect(find.text('Contact details'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Crop'), findsOneWidget);
    expect(find.text('Raw OCR text'), findsOneWidget);
    expect(find.text('Gallery'), findsNothing);
  });

  testWidgets('saved contact edit page includes image tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          apiClient: _FakeApiClient(
            contacts: const [
              Contact(
                id: 1,
                name: 'Ada Lovelace',
                company: 'Analytical Engines',
                email: 'ada@example.com',
                phone: '+1 555 0100',
                rawText: 'Ada Lovelace\nAnalytical Engines',
                imagePath: 'uploads/card.jpg',
                cropPath: 'crops/card_crop.jpg',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit saved contact'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Crop'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
  });
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient({this.contacts = const []});

  final List<Contact> contacts;

  @override
  String get baseUrl => 'http://127.0.0.1:8000';

  @override
  String absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '$baseUrl$path';
  }

  @override
  Future<void> healthCheck() async {}

  @override
  Future<List<Contact>> listContacts({String query = ''}) async {
    return contacts;
  }

  @override
  Future<Contact> createContact(ContactPayload payload) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteContact(int contactId) {
    throw UnimplementedError();
  }

  @override
  Future<CardDetectionResponse> detectCard(XFile file) {
    throw UnimplementedError();
  }

  @override
  Future<OcrResult> extractCard({
    required String imagePath,
    required String provider,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Contact> updateContact(int contactId, ContactPayload payload) {
    throw UnimplementedError();
  }
}
