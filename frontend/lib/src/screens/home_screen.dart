import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' hide XFile;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/browser_camera_capture.dart';
import '../models/card_detection.dart';
import '../models/contact.dart';
import '../models/ocr_result.dart';

enum _WorkspacePage { home, review, detail }

Future<XFile> _normalizeCameraCapture(
  XFile file,
  CameraLensDirection lensDirection,
) async {
  if (lensDirection != CameraLensDirection.front) {
    return file;
  }

  final bytes = await file.readAsBytes();
  final flippedBytes = await _flipImageHorizontally(bytes);
  return XFile.fromData(
    flippedBytes,
    name: 'camera_capture.png',
    mimeType: 'image/png',
    length: flippedBytes.length,
  );
}

Future<Uint8List> _flipImageHorizontally(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();

  canvas.translate(image.width.toDouble(), 0);
  canvas.scale(-1, 1);
  canvas.drawImage(image, Offset.zero, paint);

  final picture = recorder.endRecording();
  final flippedImage = await picture.toImage(image.width, image.height);
  final byteData = await flippedImage.toByteData(
    format: ui.ImageByteFormat.png,
  );

  image.dispose();
  flippedImage.dispose();

  if (byteData == null) {
    throw StateError('Unable to encode camera image');
  }

  return byteData.buffer.asUint8List();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.apiClient,
    super.key,
  });

  final ApiClient apiClient;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _rawTextController = TextEditingController();
  final _searchController = TextEditingController();

  XFile? _selectedFile;
  Uint8List? _selectedBytes;
  CardDetectionResponse? _detection;
  int? _selectedDetectionIndex;
  OcrResult? _ocrResult;
  Contact? _editingContact;
  Contact? _detailContact;
  List<Contact> _contacts = const [];
  _WorkspacePage _page = _WorkspacePage.home;
  String _ocrProvider = 'openai';
  String _status = 'Ready';
  bool _apiOnline = false;
  bool _isDetecting = false;
  bool _isExtracting = false;
  bool _isSaving = false;
  bool _isLoadingContacts = false;
  bool _isOpeningCamera = false;
  int? _deletingContactId;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _checkApi();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _rawTextController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  DetectionBox? get _selectedDetection {
    final detection = _detection;
    final index = _selectedDetectionIndex;
    if (detection == null || index == null) {
      return null;
    }
    if (index < 0 || index >= detection.detections.length) {
      return null;
    }
    return detection.detections[index];
  }

  Future<void> _checkApi() async {
    try {
      await widget.apiClient.healthCheck();
      setState(() {
        _apiOnline = true;
      });
    } catch (error) {
      setState(() {
        _apiOnline = false;
        _status = error.toString();
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 92);
    if (file == null) {
      return;
    }
    await _selectImage(file, 'Selected ${file.name}');
  }

  Future<void> _openCamera() async {
    setState(() {
      _isOpeningCamera = true;
      _status = 'Opening camera';
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        await _openBrowserCameraFallback('No camera found.');
        return;
      }

      if (!mounted) {
        return;
      }

      final file = await showDialog<XFile>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _CameraCaptureDialog(cameras: cameras),
      );
      if (file != null) {
        await _selectImage(file, 'Captured image');
      } else {
        setState(() {
          _status = 'Camera closed';
        });
      }
    } on CameraException catch (error) {
      await _openBrowserCameraFallback(error.description ?? error.code);
    } catch (error) {
      await _openBrowserCameraFallback(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningCamera = false;
        });
      }
    }
  }

  Future<void> _openBrowserCameraFallback(String message) async {
    if (!mounted) {
      return;
    }

    if (!isBrowserCameraCaptureSupported) {
      setState(() {
        _status = message;
      });
      return;
    }

    final file = await captureWithBrowserCamera(
      context,
      initialError: message,
    );
    if (!mounted) {
      return;
    }
    if (file != null) {
      await _selectImage(file, 'Captured image');
    } else {
      setState(() {
        _status = message;
      });
    }
  }

  Future<void> _selectImage(XFile file, String status) async {
    final bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedFile = file;
      _selectedBytes = bytes;
      _detection = null;
      _selectedDetectionIndex = null;
      _ocrResult = null;
      _editingContact = null;
      _detailContact = null;
      _page = _WorkspacePage.home;
      _clearForm();
      _status = status;
    });
  }

  Future<void> _detectCard() async {
    final file = _selectedFile;
    if (file == null) {
      return;
    }
    setState(() {
      _isDetecting = true;
      _status = 'Detecting business card';
    });
    try {
      final detection = await widget.apiClient.detectCard(file);
      setState(() {
        _detection = detection;
        _selectedDetectionIndex = detection.detections.isEmpty ? null : 0;
        _ocrResult = null;
        _page = detection.detections.isEmpty
            ? _WorkspacePage.home
            : _WorkspacePage.review;
        _status = detection.detections.isEmpty
            ? 'No business card detected'
            : '${detection.detections.length} detection result(s)';
      });
    } catch (error) {
      setState(() {
        _status = error.toString();
      });
    } finally {
      setState(() {
        _isDetecting = false;
      });
    }
  }

  Future<void> _extractText() async {
    final detection = _selectedDetection;
    if (detection == null) {
      return;
    }
    setState(() {
      _isExtracting = true;
      _status = 'Extracting text';
    });
    try {
      final result = await widget.apiClient.extractCard(
        imagePath: detection.cropPath,
        provider: _ocrProvider,
      );
      setState(() {
        _ocrResult = result;
        _editingContact = null;
        _fillFormFromOcr(result);
        _status = 'Extracted ${result.lines.length} text line(s)';
      });
    } catch (error) {
      setState(() {
        _status = error.toString();
      });
    } finally {
      setState(() {
        _isExtracting = false;
      });
    }
  }

  Future<void> _saveContact() async {
    final editingContact = _editingContact;
    final payload = ContactPayload(
      name: _nameController.text,
      company: _companyController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      rawText: _rawTextController.text,
      imagePath: editingContact?.imagePath ?? _detection?.imagePath,
      cropPath: editingContact?.cropPath ?? _selectedDetection?.cropPath,
    );

    setState(() {
      _isSaving = true;
      _status = editingContact == null ? 'Saving contact' : 'Updating contact';
    });
    try {
      if (editingContact == null) {
        await widget.apiClient.createContact(payload);
      } else {
        await widget.apiClient.updateContact(editingContact.id, payload);
      }
      await _loadContacts();
      setState(() {
        _editingContact = null;
        _detailContact = null;
        _ocrResult = null;
        _selectedFile = null;
        _selectedBytes = null;
        _detection = null;
        _selectedDetectionIndex = null;
        _page = _WorkspacePage.home;
        _clearForm();
        _status = editingContact == null ? 'Contact saved' : 'Contact updated';
      });
    } catch (error) {
      setState(() {
        _status = error.toString();
      });
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _confirmDeleteContact(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete contact'),
          content: Text(
            'Delete ${contact.name ?? contact.email ?? 'this contact'}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteContact(contact);
    }
  }

  Future<void> _deleteContact(Contact contact) async {
    setState(() {
      _deletingContactId = contact.id;
      _status = 'Deleting contact';
    });
    try {
      await widget.apiClient.deleteContact(contact.id);
      if (_editingContact?.id == contact.id) {
        _editingContact = null;
        _clearForm();
        _page = _WorkspacePage.home;
      }
      if (_detailContact?.id == contact.id) {
        _detailContact = null;
        _page = _WorkspacePage.home;
      }
      await _loadContacts();
      setState(() {
        _status = 'Contact deleted';
      });
    } catch (error) {
      setState(() {
        _status = error.toString();
      });
    } finally {
      setState(() {
        _deletingContactId = null;
      });
    }
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoadingContacts = true;
    });
    try {
      final contacts = await widget.apiClient.listContacts(
        query: _searchController.text,
      );
      setState(() {
        _contacts = contacts;
      });
    } catch (error) {
      setState(() {
        _status = error.toString();
      });
    } finally {
      setState(() {
        _isLoadingContacts = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), _loadContacts);
  }

  void _startEditingContact(Contact contact) {
    setState(() {
      _selectedFile = null;
      _selectedBytes = null;
      _detection = null;
      _selectedDetectionIndex = null;
      _ocrResult = null;
      _editingContact = contact;
      _detailContact = null;
      _page = _WorkspacePage.review;
      _fillFormFromContact(contact);
      _status = 'Editing contact';
    });
  }

  void _cancelEditingContact() {
    setState(() {
      _editingContact = null;
      _detailContact = null;
      _page = _WorkspacePage.home;
      _clearForm();
      _status = 'Ready';
    });
  }

  void _returnHome() {
    setState(() {
      _page = _WorkspacePage.home;
      _editingContact = null;
      _detailContact = null;
      _ocrResult = null;
      _clearForm();
      _status = 'Ready';
    });
  }

  void _fillFormFromOcr(OcrResult result) {
    _nameController.text = result.fields.name ?? '';
    _companyController.text = result.fields.company ?? '';
    _emailController.text = result.fields.email ?? '';
    _phoneController.text = result.fields.phone ?? '';
    _rawTextController.text = result.rawText;
  }

  void _showContactDetail(Contact contact) {
    setState(() {
      _selectedFile = null;
      _selectedBytes = null;
      _detection = null;
      _selectedDetectionIndex = null;
      _ocrResult = null;
      _editingContact = null;
      _detailContact = contact;
      _page = _WorkspacePage.detail;
      _clearForm();
      _status = 'Viewing contact';
    });
  }

  void _fillFormFromContact(Contact contact) {
    _nameController.text = contact.name ?? '';
    _companyController.text = contact.company ?? '';
    _emailController.text = contact.email ?? '';
    _phoneController.text = contact.phone ?? '';
    _rawTextController.text = contact.rawText ?? '';
  }

  void _clearForm() {
    _nameController.clear();
    _companyController.clear();
    _emailController.clear();
    _phoneController.clear();
    _rawTextController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SnapFolio Business Card Scanner'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(_apiOnline ? 'API connected' : 'API offline'),
              avatar: Icon(
                _apiOnline ? Icons.check_circle : Icons.error,
                color: _apiOnline ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: switch (_page) {
                  _WorkspacePage.home => _buildHomePage(),
                  _WorkspacePage.review => _buildReviewPage(),
                  _WorkspacePage.detail => _buildDetailPage(),
                },
              ),
            ),
            _StatusBar(message: _status),
          ],
        ),
      ),
    );
  }

  Widget _buildHomePage() {
    return SingleChildScrollView(
      key: const ValueKey('home-page'),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDetectPanel(),
              const SizedBox(height: 16),
              _buildContactsPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewPage() {
    final editingContact = _editingContact;
    final isEditing = editingContact != null;

    return SingleChildScrollView(
      key: const ValueKey('review-page'),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _returnHome,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Home'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit saved contact' : 'OCR review',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (editingContact != null)
                _buildEditContactLayout(editingContact)
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;
                    final ocrPanel = _buildOcrPanel();
                    final form = _buildContactForm();
                    if (!isWide) {
                      return Column(
                        children: [
                          ocrPanel,
                          const SizedBox(height: 16),
                          form,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: ocrPanel),
                        const SizedBox(width: 16),
                        SizedBox(width: 430, child: form),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditContactLayout(Contact contact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        final form = _buildContactForm();
        final images = _buildContactImageTabs(contact);
        if (!isWide) {
          return Column(
            children: [
              form,
              const SizedBox(height: 16),
              images,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 430, child: form),
            const SizedBox(width: 16),
            Expanded(child: images),
          ],
        );
      },
    );
  }

  Widget _buildDetailPage() {
    final contact = _detailContact;
    if (contact == null) {
      return SingleChildScrollView(
        key: const ValueKey('empty-detail-page'),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: _returnHome,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Home'),
                ),
                const SizedBox(height: 24),
                const Text('Contact not found'),
              ],
            ),
          ),
        ),
      );
    }

    final deleting = _deletingContactId == contact.id;

    return SingleChildScrollView(
      key: ValueKey('detail-page-${contact.id}'),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: deleting ? null : _returnHome,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Home'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      contact.name ?? 'Unnamed contact',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed:
                        deleting ? null : () => _startEditingContact(contact),
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    onPressed:
                        deleting ? null : () => _confirmDeleteContact(contact),
                    icon: deleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    tooltip: deleting ? 'Deleting' : 'Delete',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 980;
                  final images = _buildContactImageTabs(contact);
                  final details = _buildContactDetails(contact);
                  if (!isWide) {
                    return Column(
                      children: [
                        details,
                        const SizedBox(height: 16),
                        images,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 430, child: details),
                      const SizedBox(width: 16),
                      Expanded(child: images),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactImageTabs(Contact contact) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.white,
              child: TabBar(
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor:
                    Theme.of(context).colorScheme.onSurfaceVariant,
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: const [
                  Tab(text: 'Original'),
                  Tab(text: 'Crop'),
                ],
              ),
            ),
            SizedBox(
              height: 420,
              child: TabBarView(
                children: [
                  _StoredImagePreview(
                    label: 'Original image',
                    imageUrl: _storageUrl(contact.imagePath),
                  ),
                  _StoredImagePreview(
                    label: 'Cropped card',
                    imageUrl: _storageUrl(contact.cropPath),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactDetails(Contact contact) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _DetailField(label: 'Name', value: contact.name),
            _DetailField(label: 'Company', value: contact.company),
            _DetailField(label: 'Email', value: contact.email),
            _DetailField(label: 'Phone', value: contact.phone),
            _DetailField(label: 'Original path', value: contact.imagePath),
            _DetailField(label: 'Crop path', value: contact.cropPath),
            const SizedBox(height: 12),
            Text(
              'Raw OCR text',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              contact.rawText?.isNotEmpty == true ? contact.rawText! : 'None',
            ),
          ],
        ),
      ),
    );
  }

  String? _storageUrl(String? relativePath) {
    final trimmed = relativePath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final normalizedPath = trimmed.replaceAll('\\', '/');
    final cleanPath = normalizedPath.startsWith('/storage/')
        ? normalizedPath.substring('/storage/'.length)
        : normalizedPath;
    return widget.apiClient.absoluteUrl('/storage/$cleanPath');
  }

  Widget _buildDetectPanel() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
                OutlinedButton.icon(
                  onPressed: _isOpeningCamera ? null : _openCamera,
                  icon: _isOpeningCamera
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera),
                  label: Text(_isOpeningCamera ? 'Opening' : 'Camera'),
                ),
                FilledButton.icon(
                  onPressed: _selectedFile == null || _isDetecting
                      ? null
                      : _detectCard,
                  icon: _isDetecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.crop_free),
                  label: Text(_isDetecting ? 'Detecting' : 'Detect card'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildImagePreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildOcrPanel() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _ocrProvider,
                  items: const [
                    DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                    DropdownMenuItem(value: 'easyocr', child: Text('EasyOCR')),
                  ],
                  onChanged: _isExtracting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _ocrProvider = value);
                          }
                        },
                ),
                FilledButton.icon(
                  onPressed: _selectedDetection == null || _isExtracting
                      ? null
                      : _extractText,
                  icon: _isExtracting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner),
                  label: Text(_isExtracting ? 'Extracting' : 'Run OCR'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildImagePreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    final bytes = _selectedBytes;
    final detection = _detection;

    if (bytes == null) {
      return const _EmptyPreview();
    }

    if (detection == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 520),
          width: double.infinity,
          color: Colors.white,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      );
    }

    final aspectRatio = detection.imageWidth / detection.imageHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: Colors.white,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(bytes, fit: BoxFit.fill),
                      for (var index = 0;
                          index < detection.detections.length;
                          index++)
                        _buildDetectionBox(
                          detection.detections[index],
                          index,
                          constraints.biggest,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          detection.detections.isEmpty
              ? 'No business card detected.'
              : '${detection.detections.length} card candidate(s). Tap a box before OCR.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildDetectionBox(DetectionBox box, int index, Size size) {
    final detection = _detection;
    if (detection == null) {
      return const SizedBox.shrink();
    }

    final left = box.x1 / detection.imageWidth * size.width;
    final top = box.y1 / detection.imageHeight * size.height;
    final width = (box.x2 - box.x1) / detection.imageWidth * size.width;
    final height = (box.y2 - box.y1) / detection.imageHeight * size.height;
    final selected = index == _selectedDetectionIndex;
    final accentColor = Theme.of(context).colorScheme.primary;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: InkWell(
        onTap: () => setState(() => _selectedDetectionIndex = index),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.16)
                : accentColor.withValues(alpha: 0.08),
            border: Border.all(
              color:
                  selected ? accentColor : accentColor.withValues(alpha: 0.72),
              width: 2,
            ),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                '${box.className} ${(box.confidence * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactForm() {
    final isEditing = _editingContact != null;
    final canSave = !_isSaving && (_ocrResult != null || isEditing);

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'Edit contact' : 'Review contact',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (isEditing) ...[
                  TextButton.icon(
                    onPressed: _isSaving ? null : _cancelEditingContact,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  onPressed: canSave ? _saveContact : null,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(isEditing ? Icons.update : Icons.save),
                  label: Text(
                    _isSaving ? 'Saving' : (isEditing ? 'Update' : 'Save'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _TextField(controller: _nameController, label: 'Name'),
            const SizedBox(height: 12),
            _TextField(controller: _companyController, label: 'Company'),
            const SizedBox(height: 12),
            _TextField(controller: _emailController, label: 'Email'),
            const SizedBox(height: 12),
            _TextField(controller: _phoneController, label: 'Phone'),
            const SizedBox(height: 12),
            TextField(
              controller: _rawTextController,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(labelText: 'Raw OCR text'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved contacts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _isLoadingContacts ? null : _loadContacts,
                  icon: _isLoadingContacts
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search contacts',
              ),
            ),
            const SizedBox(height: 12),
            if (_contacts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('No contacts found')),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _contacts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final contact = _contacts[index];
                  final selected = _editingContact?.id == contact.id ||
                      _detailContact?.id == contact.id;
                  final deleting = _deletingContactId == contact.id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    selected: selected,
                    onTap: () => _showContactDetail(contact),
                    title: Text(contact.name ?? 'Unnamed contact'),
                    subtitle: Text(
                      [
                        contact.company,
                        contact.email,
                        contact.phone,
                      ]
                          .whereType<String>()
                          .where((value) => value.isNotEmpty)
                          .join('\n'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: deleting
                              ? null
                              : () => _startEditingContact(contact),
                          icon: const Icon(Icons.edit),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          onPressed: deleting
                              ? null
                              : () => _confirmDeleteContact(contact),
                          icon: deleting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.delete_outline),
                          tooltip: deleting ? 'Deleting' : 'Delete',
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraCaptureDialog extends StatefulWidget {
  const _CameraCaptureDialog({required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<_CameraCaptureDialog> createState() => _CameraCaptureDialogState();
}

class _CameraCaptureDialogState extends State<_CameraCaptureDialog> {
  static const _resolutionFallbacks = <ResolutionPreset>[
    ResolutionPreset.high,
    ResolutionPreset.medium,
    ResolutionPreset.low,
  ];

  CameraController? _controller;
  Future<void>? _initializeFuture;
  int _cameraIndex = 0;
  int _initializeGeneration = 0;
  bool _isInitializing = false;
  bool _isTakingPicture = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeCamera(0);
  }

  @override
  void dispose() {
    _initializeGeneration++;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera(int index) async {
    if (index < 0 || index >= widget.cameras.length || _isTakingPicture) {
      return;
    }

    final generation = ++_initializeGeneration;
    final previousController = _controller;
    setState(() {
      _cameraIndex = index;
      _controller = null;
      _initializeFuture = null;
      _isInitializing = true;
      _errorMessage = null;
    });

    await previousController?.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    CameraException? lastCameraError;
    Object? lastError;

    for (final resolutionPreset in _resolutionFallbacks) {
      if (!mounted || generation != _initializeGeneration) {
        return;
      }

      final controller = CameraController(
        widget.cameras[index],
        resolutionPreset,
        enableAudio: false,
      );
      final initializeFuture = controller.initialize();

      setState(() {
        _controller = controller;
        _initializeFuture = initializeFuture;
      });

      try {
        await initializeFuture;
        if (!mounted || generation != _initializeGeneration) {
          await controller.dispose();
          return;
        }
        setState(() {
          _isInitializing = false;
          _errorMessage = null;
        });
        return;
      } on CameraException catch (error) {
        lastCameraError = error;
        await controller.dispose();
      } catch (error) {
        lastError = error;
        await controller.dispose();
      }

      if (!mounted || generation != _initializeGeneration) {
        return;
      }

      setState(() {
        if (identical(_controller, controller)) {
          _controller = null;
          _initializeFuture = null;
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    if (mounted && generation == _initializeGeneration) {
      setState(() {
        _controller = null;
        _initializeFuture = null;
        _isInitializing = false;
        _errorMessage = _cameraStartupError(lastCameraError, lastError);
      });
    }
  }

  String _cameraStartupError(CameraException? cameraError, Object? error) {
    final details = cameraError?.description ?? cameraError?.code;
    final fallbackDetails = error?.toString();
    final message = details?.isNotEmpty == true ? details : fallbackDetails;
    final cameraName = _cameraLabel(_cameraIndex);

    if (message == null || message.isEmpty) {
      return 'Unable to start $cameraName. Select another camera or try again.';
    }

    return 'Unable to start $cameraName: $message';
  }

  String _cameraLabel(int index) {
    final camera = widget.cameras[index];
    final name = camera.name.trim();
    final label = name.isEmpty ? 'Camera ${index + 1}' : name;
    return '$label (${_lensDirectionLabel(camera.lensDirection)})';
  }

  String _lensDirectionLabel(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.front:
        return 'front';
      case CameraLensDirection.back:
        return 'back';
      case CameraLensDirection.external:
        return 'external';
    }
  }

  Future<void> _retryCamera() async {
    if (_isTakingPicture || _isInitializing) {
      return;
    }
    await _initializeCamera(_cameraIndex);
  }

  Future<void> _selectCamera(int? index) async {
    if (index == null ||
        index == _cameraIndex ||
        _isTakingPicture ||
        _isInitializing) {
      return;
    }
    await _initializeCamera(index);
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2 || _isTakingPicture || _isInitializing) {
      return;
    }
    final nextIndex = (_cameraIndex + 1) % widget.cameras.length;
    await _initializeCamera(nextIndex);
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isInitializing ||
        _isTakingPicture) {
      return;
    }

    setState(() {
      _isTakingPicture = true;
      _errorMessage = null;
    });

    try {
      final capturedFile = await controller.takePicture();
      final file = await _normalizeCameraCapture(
        capturedFile,
        widget.cameras[_cameraIndex].lensDirection,
      );
      if (mounted) {
        Navigator.of(context).pop<XFile>(file);
      }
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.description ?? error.code;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
    }
  }

  Future<void> _useBrowserCapture() async {
    if (!isBrowserCameraCaptureSupported ||
        _isTakingPicture ||
        _isInitializing) {
      return;
    }

    final previousController = _controller;
    setState(() {
      _initializeGeneration++;
      _controller = null;
      _initializeFuture = null;
      _isInitializing = false;
    });
    await previousController?.dispose();

    if (!mounted) {
      return;
    }

    final file = await captureWithBrowserCamera(
      context,
      initialError: _errorMessage,
    );
    if (mounted && file != null) {
      Navigator.of(context).pop<XFile>(file);
    } else if (mounted) {
      await _initializeCamera(_cameraIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final canCapture = controller != null &&
        controller.value.isInitialized &&
        !_isInitializing &&
        !_isTakingPicture &&
        _errorMessage == null;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Camera',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _isInitializing || _isTakingPicture
                        ? null
                        : _retryCamera,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Retry camera',
                  ),
                  IconButton(
                    onPressed: widget.cameras.length < 2 ||
                            _isInitializing ||
                            _isTakingPicture
                        ? null
                        : _switchCamera,
                    icon: const Icon(Icons.cameraswitch),
                    tooltip: 'Switch camera',
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(_cameraIndex),
                initialValue: _cameraIndex,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Camera device',
                ),
                items: [
                  for (var index = 0; index < widget.cameras.length; index++)
                    DropdownMenuItem<int>(
                      value: index,
                      child: Text(
                        _cameraLabel(index),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: widget.cameras.length < 2 ||
                        _isInitializing ||
                        _isTakingPicture
                    ? null
                    : _selectCamera,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: Colors.black,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _buildPreview(controller),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isTakingPicture
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  if (isBrowserCameraCaptureSupported) ...[
                    OutlinedButton.icon(
                      onPressed: _isTakingPicture ? null : _useBrowserCapture,
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Browser capture'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    onPressed: canCapture ? _takePicture : null,
                    icon: _isTakingPicture
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(_isTakingPicture ? 'Capturing' : 'Capture'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(CameraController? controller) {
    if (controller == null || _initializeFuture == null) {
      if (_errorMessage != null) {
        return const Center(
          child: Icon(Icons.videocam_off, color: Colors.white, size: 48),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError ||
            _errorMessage != null ||
            !controller.value.isInitialized) {
          return const Center(
            child: Icon(Icons.videocam_off, color: Colors.white, size: 48),
          );
        }
        final preview = CameraPreview(controller);
        if (widget.cameras[_cameraIndex].lensDirection !=
            CameraLensDirection.front) {
          return preview;
        }
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(-1, 1, 1),
          child: preview,
        );
      },
    );
  }
}

class _StoredImagePreview extends StatelessWidget {
  const _StoredImagePreview({
    required this.label,
    required this.imageUrl,
  });

  final String label;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return Center(child: Text('No $label available'));
    }

    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return Center(child: Text('Unable to load $label'));
          },
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim();
    final displayValue = text == null || text.isEmpty ? 'None' : text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(displayValue),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: const Text('No image selected'),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Text(message),
    );
  }
}
