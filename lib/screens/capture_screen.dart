// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../config/theme.dart';
import '../models/patient.dart';
import '../services/app_state.dart';
import '../services/database_service.dart';
import '../services/image_service.dart';
import '../utils/constants.dart';
import '../widgets/inline_tip.dart';

import 'camera_capture_screen.dart';
import 'analysis_screen.dart';

class CaptureScreen extends StatefulWidget {
  final Patient? existingPatient;
  final String? preselectedLocation;

  const CaptureScreen({
    super.key,
    this.existingPatient,
    this.preselectedLocation,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imageService = ImageService();

  File? _selectedImage;

  bool _isNewPatient = true;
  Patient? _selectedPatient;
  List<Patient> _existingPatients = [];

  final _patientNameController = TextEditingController();
  final _patientAgeController = TextEditingController();
  final _bedNumberController = TextEditingController();
  final _wardController = TextEditingController();
  final _capturedByController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedGender;
  String? _selectedWoundLocation;
  String? _qualityWarning;
  bool _isCheckingQuality = false;
  bool _isUploading = false;
  String _painLevel = 'none';
  String _odor = 'none';
  String _exudateAmount = 'none';
  String _exudateType = 'serous';
  String _periwoundRedness = 'none';
  String _warmthOrSwelling = 'no';
  String _feverOrChills = 'no';
  String _woundChange48h = 'same';
  static const Set<String> _painLevels = {
    'none',
    'mild',
    'moderate',
    'severe',
  };
  static const Set<String> _odorLevels = {'none', 'mild', 'strong'};
  static const Set<String> _exudateAmounts = {
    'none',
    'low',
    'moderate',
    'heavy',
  };
  static const Set<String> _exudateTypes = {
    'serous',
    'purulent',
    'bloody',
    'mixed',
  };
  static const Set<String> _rednessLevels = {'none', 'mild', 'spreading'};
  static const Set<String> _yesNo = {'yes', 'no'};
  static const Set<String> _woundChange = {'better', 'same', 'worse'};

  @override
  void initState() {
    super.initState();
    _loadExistingPatients();

    if (widget.existingPatient != null) {
      _isNewPatient = false;
      _selectedPatient = widget.existingPatient;
      _populatePatientFields(widget.existingPatient!);
    }
    if (widget.preselectedLocation != null) {
      _selectedWoundLocation = widget.preselectedLocation;
    }
  }

  Future<void> _loadExistingPatients() async {
    final db = context.read<DatabaseService>();
    final patients = await db.getAllPatients();
    setState(() => _existingPatients = patients);
  }

  void _populatePatientFields(Patient patient) {
    _patientNameController.text = patient.name;
    _patientAgeController.text = patient.age?.toString() ?? '';
    _bedNumberController.text = patient.bedNumber ?? '';
    _wardController.text = patient.ward ?? '';
    _selectedGender = patient.gender;
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _patientAgeController.dispose();
    _bedNumberController.dispose();
    _wardController.dispose();
    _capturedByController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isCaregiver = context.watch<AppState>().isCaregiver;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const InlineTip(
                      text: 'Tip: Use even lighting and fill the frame with the wound.',
                    ),
                    const SizedBox(height: 16),
                    _buildImageSection(),
                    const SizedBox(height: 16),
                    _buildCaptureGuide(),
                    const SizedBox(height: 16),
                    _buildCaptureChecklist(),
                    const SizedBox(height: 32),

                    _buildSectionTitle('Patient'),
                    const SizedBox(height: 12),
                    _buildPatientToggle(),
                    const SizedBox(height: 20),

                    _isNewPatient
                        ? _buildNewPatientForm(isCaregiver)
                        : _buildExistingPatientSelector(),

                    const SizedBox(height: 32),

                    _buildSectionTitle('Wound Details'),
                    const SizedBox(height: 16),
                    _buildWoundDetailsSection(isCaregiver),
                    if (!isCaregiver) ...[
                      const SizedBox(height: 24),
                      _buildSectionTitle('Clinical Checklist'),
                      const SizedBox(height: 12),
                      _buildClinicalChecklistCard(),
                    ],

                    const SizedBox(height: 40),
                    _buildAnalyzeButton(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // APP BAR
  // ---------------------------------------------------------------------------

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: AppTheme.background,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Icon(Icons.arrow_back, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: const FlexibleSpaceBar(
        title: Text(
          'New Analysis',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        titlePadding: EdgeInsets.only(left: 60, bottom: 16),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // IMAGE SECTION
  // ---------------------------------------------------------------------------

  Widget _buildImageSection() {
    return GestureDetector(
      onTap: _selectImage,
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _selectedImage != null
                ? AppTheme.primaryBlue
                : AppTheme.border,
            width: _selectedImage != null ? 2 : 1,
          ),
        ),
        child: _selectedImage == null
            ? _buildImagePlaceholder()
            : _buildImagePreview(),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.add_a_photo_rounded,
            size: 40,
            color: AppTheme.primaryBlue,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Capture Wound Image',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'Use camera for best consistency',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildImageSourceChip(Icons.camera_alt_rounded, 'Camera', true),
            const SizedBox(width: 12),
            _buildImageSourceChip(Icons.photo_library_rounded, 'Gallery', false),
          ],
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.file(_selectedImage!, fit: BoxFit.cover),
        ),
        if (_isCheckingQuality || _qualityWarning != null)
          Positioned(
            top: 56,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _qualityWarning == null
                        ? Icons.hourglass_top
                        : Icons.warning_amber_rounded,
                    color: _qualityWarning == null
                        ? Colors.white
                        : AppTheme.warning,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _qualityWarning ?? 'Checking image quality...',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          top: 12,
          right: 12,
          child: Row(
            children: [
              _buildImageActionButton(
                Icons.refresh_rounded,
                _retakeFromCamera,
              ),
              const SizedBox(width: 8),
              _buildImageActionButton(
                Icons.close_rounded,
                () => setState(() {
                  _selectedImage = null;
                  _qualityWarning = null;
                  _isCheckingQuality = false;
                }),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.success, size: 18),
                SizedBox(width: 8),
                Text(
                  'Image ready for analysis',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // IMAGE HELPERS
  // ---------------------------------------------------------------------------

  Widget _buildImageActionButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _buildImageSourceChip(
      IconData icon, String label, bool isCamera) {
    return GestureDetector(
      onTap: () async {
        if (isCamera) {
          final file = await Navigator.push<File>(
            context,
            MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
          );
          if (file != null) await _setSelectedImage(file);
        } else {
          final file = await _imageService.pickFromGallery();
          if (file != null) await _setSelectedImage(file);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryBlue),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FORM SECTIONS
  // ---------------------------------------------------------------------------

  Widget _buildSectionTitle(String title) =>
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));

  Widget _buildCaptureChecklist() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Before you capture',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          _ChecklistItem(icon: Icons.check_circle_outline, text: 'Remove dressing and clean area'),
          _ChecklistItem(icon: Icons.check_circle_outline, text: 'Ensure full wound is visible'),
          _ChecklistItem(icon: Icons.check_circle_outline, text: 'Use good lighting, avoid glare'),
          _ChecklistItem(icon: Icons.check_circle_outline, text: 'Hold camera steady'),
        ],
      ),
    );
  }

  Widget _buildCaptureGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Capture guide',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildGuideChip(Icons.clean_hands, 'Prepare'),
              const SizedBox(width: 8),
              _buildGuideChip(Icons.camera_alt_outlined, 'Capture'),
              const SizedBox(width: 8),
              _buildGuideChip(Icons.fact_check_outlined, 'Review'),
            ],
          ),
          const SizedBox(height: 10),
            Text(
              'Keep the camera 20-30 cm away and avoid shadows.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _showCaptureTips,
              child: const Text('View tips'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryBlue),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.primaryBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientToggle() {
    return Row(
      children: [
        Expanded(
          child: ChoiceChip(
            label: const Text('New Patient'),
            selected: _isNewPatient,
            onSelected: (_) => setState(() {
              _isNewPatient = true;
              _selectedPatient = null;
            }),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ChoiceChip(
            label: const Text('Existing'),
            selected: !_isNewPatient,
            onSelected: (_) => setState(() => _isNewPatient = false),
          ),
        ),
      ],
    );
  }

  Widget _buildNewPatientForm(bool isCaregiver) {
    return Column(
      children: [
        _buildTextField(
          controller: _patientNameController,
          label: 'Patient Name',
          icon: Icons.person_outline,
          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
        ),
        if (!isCaregiver) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _patientAgeController,
                  label: 'Age',
                  icon: Icons.cake_outlined,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  value: _selectedGender,
                  label: 'Gender',
                  icon: Icons.wc_outlined,
                  items: const ['Male', 'Female', 'Other'],
                  onChanged: (v) => setState(() => _selectedGender = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _wardController,
                  label: 'Ward',
                  icon: Icons.local_hospital_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _bedNumberController,
                  label: 'Bed Number',
                  icon: Icons.bed_outlined,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildExistingPatientSelector() {
    if (_existingPatients.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 48, color: AppTheme.textTertiary),
            const SizedBox(height: 12),
            const Text(
              'No existing patients',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() {
                _isNewPatient = true;
                _selectedPatient = null;
              }),
              child: const Text('Create New Patient'),
            ),
          ],
        ),
      );
    }

    String subtitleFor(Patient p) {
      final parts = <String>[];
      if ((p.ward ?? '').trim().isNotEmpty) parts.add('Ward ${p.ward!.trim()}');
      if ((p.bedNumber ?? '').trim().isNotEmpty) parts.add('Bed ${p.bedNumber!.trim()}');
      return parts.isEmpty ? '' : parts.join(' • ');
    }

    // 2-line widget (ONLY for the dropdown menu items)
    Widget menuItemTwoLines(Patient p) {
      final sub = subtitleFor(p);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      );
    }

    // 1-line widget (for CLOSED state to avoid overflow)
    Widget selectedOneLine(Patient p) {
      final sub = subtitleFor(p);
      final text = sub.isEmpty ? p.name : '${p.name}  —  $sub';
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      );
    }

    return SizedBox(
      height: 64, // ✅ forces enough height so it will never overflow
      child: DropdownButtonFormField<String>(
        value: _selectedPatient?.id,
        isExpanded: true,

        // ✅ IMPORTANT: allow menu items to be taller than 48
        itemHeight: null,

        validator: (v) => v == null ? 'Please select a patient' : null,

        decoration: const InputDecoration(
          labelText: 'Select Patient',
          prefixIcon: Icon(Icons.person_search_outlined),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),

        // ✅ closed display = one line (prevents overflow)
        selectedItemBuilder: (context) {
          return _existingPatients.map((p) {
            return Align(
              alignment: Alignment.centerLeft,
              child: selectedOneLine(p),
            );
          }).toList();
        },

        // ✅ menu items = two lines
        items: _existingPatients.map((p) {
          return DropdownMenuItem<String>(
            value: p.id,
            child: menuItemTwoLines(p),
          );
        }).toList(),

        onChanged: (id) {
          if (id == null) return;
          final patient = _existingPatients.firstWhere((p) => p.id == id);
          setState(() => _selectedPatient = patient);
          _populatePatientFields(patient);
        },
      ),
    );
  }

  Widget _patientDropdownItem(Patient p) {
  final parts = <String>[];

  if (p.ward != null && p.ward!.trim().isNotEmpty) {
    parts.add('Ward ${p.ward!.trim()}');
  }
  if (p.bedNumber != null && p.bedNumber!.trim().isNotEmpty) {
    parts.add('Bed ${p.bedNumber!.trim()}');
  }

  final subtitle = parts.isEmpty ? 'No ward/bed info' : parts.join(' • ');

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.textSecondary,
        ),
      ),
    ],
  );
}

  Widget _buildWoundDetailsSection(bool isCaregiver) {
    return Column(
      children: [
        _buildDropdown(
          value: _selectedWoundLocation,
          label: 'Wound Location',
          icon: Icons.location_on_outlined,
          items: AppConstants.woundLocations,
          onChanged: (v) => setState(() => _selectedWoundLocation = v),
          validator: (v) => v == null ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _capturedByController,
          label: 'Captured By',
          icon: Icons.badge_outlined,
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        if (!isCaregiver) ...[
          const SizedBox(height: 16),
          _buildTextField(
            controller: _notesController,
            label: 'Notes (Optional)',
            icon: Icons.notes_outlined,
            maxLines: 3,
          ),
        ],
      ],
    );
  }

  Widget _buildClinicalChecklistCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _buildChecklistDropdown(
            label: 'Pain level',
            value: _painLevel,
            options: const ['none', 'mild', 'moderate', 'severe'],
            onChanged: (v) => setState(() => _painLevel = v!),
          ),
          const SizedBox(height: 12),
          _buildChecklistDropdown(
            label: 'Odor',
            value: _odor,
            options: const ['none', 'mild', 'strong'],
            onChanged: (v) => setState(() => _odor = v!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildChecklistDropdown(
                  label: 'Exudate amount',
                  value: _exudateAmount,
                  options: const ['none', 'low', 'moderate', 'heavy'],
                  onChanged: (v) => setState(() => _exudateAmount = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildChecklistDropdown(
                  label: 'Exudate type',
                  value: _exudateType,
                  options: const ['serous', 'purulent', 'bloody', 'mixed'],
                  onChanged: (v) => setState(() => _exudateType = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildChecklistDropdown(
            label: 'Periwound redness',
            value: _periwoundRedness,
            options: const ['none', 'mild', 'spreading'],
            onChanged: (v) => setState(() => _periwoundRedness = v!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildChecklistDropdown(
                  label: 'Warmth/swelling',
                  value: _warmthOrSwelling,
                  options: const ['no', 'yes'],
                  onChanged: (v) => setState(() => _warmthOrSwelling = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildChecklistDropdown(
                  label: 'Fever/chills',
                  value: _feverOrChills,
                  options: const ['no', 'yes'],
                  onChanged: (v) => setState(() => _feverOrChills = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildChecklistDropdown(
            label: 'Wound change (48h)',
            value: _woundChange48h,
            options: const ['better', 'same', 'worse'],
            onChanged: (v) => setState(() => _woundChange48h = v!),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: options
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }

  // ---------------------------------------------------------------------------
  // INPUT BUILDERS (THIS FIXES THE UI)
  // ---------------------------------------------------------------------------

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String label,
    required IconData icon,
    required List<String> items,
    List<String>? itemLabels, // ✅ add this
    required Function(String?) onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      items: items.asMap().entries.map((entry) {
        final index = entry.key;
        final itemValue = entry.value;
        final displayText = itemLabels != null && index < itemLabels.length
            ? itemLabels[index]
            : itemValue;

        return DropdownMenuItem(
          value: itemValue, 
          child: Text(displayText), 
        );
      }).toList(),
      onChanged: onChanged,
    );
  }


  // ---------------------------------------------------------------------------
  // ACTION
  // ---------------------------------------------------------------------------

  Widget _buildAnalyzeButton() {
    final isDisabled = _selectedImage == null || _isCheckingQuality || _isUploading;
    final buttonText = _isCheckingQuality
        ? 'Checking image...'
        : _isUploading
            ? 'Uploading image...'
            : 'Analyze Wound';
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        icon: _isUploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.analytics_rounded),
        label: Text(
          buttonText,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        onPressed: isDisabled ? null : _proceedToAnalysis,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Future<void> _retakeFromCamera() async {
  final file = await Navigator.push<File>(
    context,
    MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
  );

  if (!mounted) return;
  if (file != null) {
    await _setSelectedImage(file);
  }
}

  Future<void> _selectImage() async {
    final file = await _imageService.showPickerDialog(context);
    if (file != null) await _setSelectedImage(file);
  }

  Future<void> _setSelectedImage(File file) async {
    setState(() {
      _selectedImage = file;
      _qualityWarning = null;
      _isCheckingQuality = true;
    });
    await _analyzeImageQuality(file);
  }

  Future<void> _analyzeImageQuality(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        if (!mounted) return;
        setState(() {
          _qualityWarning = 'Unable to check image quality.';
          _isCheckingQuality = false;
        });
        return;
      }

      const stride = 10;
      double total = 0;
      int count = 0;

      for (int y = 0; y < decoded.height; y += stride) {
        for (int x = 0; x < decoded.width; x += stride) {
          final pixel = decoded.getPixel(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();
          total += (0.2126 * r) + (0.7152 * g) + (0.0722 * b);
          count++;
        }
      }

      final avg = count == 0 ? 0 : total / count;
      String? warning;
      if (avg < 60) {
        warning = 'Image looks too dark. Increase lighting.';
      } else if (avg > 200) {
        warning = 'Image looks too bright. Reduce glare.';
      }

      if (!mounted) return;
      setState(() {
        _qualityWarning = warning;
        _isCheckingQuality = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _qualityWarning = 'Unable to check image quality.';
        _isCheckingQuality = false;
      });
    }
  }

  String _contentTypeForPath(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.jpg' || ext == '.jpeg') return 'image/jpeg';
    if (ext == '.png') return 'image/png';
    return 'application/octet-stream';
  }

  String _extForPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return ext.isEmpty ? 'bin' : ext;
  }

  Future<Map<String, dynamic>> _requestUploadInit({
    required String contentType,
    required String ext,
  }) async {
    final response = await http.post(
      Uri.parse(AppConstants.uploadInitUrl),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contentType': contentType,
        'ext': ext,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Upload init failed: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Uint8List> _encryptBytes(
    Uint8List plainBytes,
    String plaintextKeyB64,
    String ivB64,
  ) async {
    final algorithm = AesGcm.with256bits();
    final keyBytes = base64Decode(plaintextKeyB64);
    final iv = base64Decode(ivB64);
    final secretKey = SecretKey(keyBytes);

    final secretBox = await algorithm.encrypt(
      plainBytes,
      secretKey: secretKey,
      nonce: iv,
    );

    final output =
        Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
    output.setAll(0, secretBox.cipherText);
    output.setAll(secretBox.cipherText.length, secretBox.mac.bytes);
    return output;
  }

  Future<void> _uploadEncryptedBytes({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final response = await http.put(
      Uri.parse(uploadUrl),
      headers: {
        'Content-Type': contentType,
        'x-amz-server-side-encryption': 'aws:kms',
        'x-amz-server-side-encryption-aws-kms-key-id': AppConstants.kmsKeyArn,
      },
      body: bytes,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload failed: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> _saveUploadMetadata({
    required String s3Key,
    required String encryptedKeyB64,
    required String ivB64,
    required String encAlg,
    required String contentType,
    required Patient patient,
    required File file,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final doc = FirebaseFirestore.instance.collection('wound_uploads').doc();
    final fileSize = await file.length();

    await doc.set({
      'userId': userId,
      'patientId': patient.id,
      'woundLocation': _selectedWoundLocation,
      's3Key': s3Key,
      'encryptedKeyB64': encryptedKeyB64,
      'ivB64': ivB64,
      'encAlg': encAlg,
      'contentType': contentType,
      'ciphertextFormat': 'ciphertext+tag',
      'tagLength': 16,
      'originalFileName': p.basename(file.path),
      'originalByteLength': fileSize,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<_UploadMetadata?> _uploadEncryptedImage(File file, Patient patient) async {
    setState(() => _isUploading = true);
    try {
      final contentType = _contentTypeForPath(file.path);
      final ext = _extForPath(file.path);
      final init = await _requestUploadInit(
        contentType: contentType,
        ext: ext,
      );

      final uploadUrl = init['uploadUrl'] as String;
      final s3Key = init['s3Key'] as String;
      final plaintextKeyB64 = init['plaintextKeyB64'] as String;
      final encryptedKeyB64 = init['encryptedKeyB64'] as String;
      final ivB64 = init['ivB64'] as String;
      final encAlg = (init['encAlg'] as String?) ?? 'AES-256-GCM';

      final plainBytes = await file.readAsBytes();
      final encryptedBytes = await _encryptBytes(
        plainBytes,
        plaintextKeyB64,
        ivB64,
      );

      await _uploadEncryptedBytes(
        uploadUrl: uploadUrl,
        bytes: encryptedBytes,
        contentType: contentType,
      );

      await _saveUploadMetadata(
        s3Key: s3Key,
        encryptedKeyB64: encryptedKeyB64,
        ivB64: ivB64,
        encAlg: encAlg,
        contentType: contentType,
        patient: patient,
        file: file,
      );

      return _UploadMetadata(
        s3Key: s3Key,
        encryptedKeyB64: encryptedKeyB64,
        ivB64: ivB64,
        contentType: contentType,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _proceedToAnalysis() async {
    if (!_formKey.currentState!.validate()) return;
    final isCaregiver = context.read<AppState>().isCaregiver;
    if (!isCaregiver && !_validateClinicalChecklistForNurse()) {
      return;
    }
    if (_qualityWarning != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Image quality warning'),
          content: Text(
            '$_qualityWarning\n\nRetake the photo for better accuracy.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Retake'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    final patient = _isNewPatient
        ? Patient(
            name: _patientNameController.text.trim(),
            age: int.tryParse(_patientAgeController.text.trim()),
            gender: _selectedGender,
            bedNumber: _bedNumberController.text.trim().isEmpty
                ? null
                : _bedNumberController.text.trim(),
            ward: _wardController.text.trim().isEmpty
                ? null
                : _wardController.text.trim(),
          )
        : _selectedPatient!;

    final uploaded = await _uploadEncryptedImage(_selectedImage!, patient);
    if (uploaded == null) return;

    final checklistPayload = _normalizedChecklistPayload();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisScreen(
          imageFile: _selectedImage!,
          patient: patient,
          woundLocation: _selectedWoundLocation!,
          capturedBy: _capturedByController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          s3Key: uploaded.s3Key,
          encryptedKeyB64: uploaded.encryptedKeyB64,
          ivB64: uploaded.ivB64,
          contentType: uploaded.contentType,
          checklistData: isCaregiver ? const {} : checklistPayload,
        ),
      ),
    );
  }

  bool _validateClinicalChecklistForNurse() {
    bool valid(String value, Set<String> allowed) => allowed.contains(
          value.trim().toLowerCase(),
        );

    final checks = <Map<String, dynamic>>[
      {'ok': valid(_painLevel, _painLevels), 'msg': 'Invalid pain level value.'},
      {'ok': valid(_odor, _odorLevels), 'msg': 'Invalid odor value.'},
      {
        'ok': valid(_exudateAmount, _exudateAmounts),
        'msg': 'Invalid exudate amount value.',
      },
      {
        'ok': valid(_exudateType, _exudateTypes),
        'msg': 'Invalid exudate type value.',
      },
      {
        'ok': valid(_periwoundRedness, _rednessLevels),
        'msg': 'Invalid periwound redness value.',
      },
      {
        'ok': valid(_warmthOrSwelling, _yesNo),
        'msg': 'Invalid warmth/swelling value.',
      },
      {
        'ok': valid(_feverOrChills, _yesNo),
        'msg': 'Invalid fever/chills value.',
      },
      {
        'ok': valid(_woundChange48h, _woundChange),
        'msg': 'Invalid wound change (48h) value.',
      },
    ];

    for (final check in checks) {
      if (check['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(check['msg'].toString())),
        );
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _normalizedChecklistPayload() {
    String pick(
      String value,
      Set<String> allowed,
      String fallback,
    ) {
      final normalized = value.trim().toLowerCase();
      return allowed.contains(normalized) ? normalized : fallback;
    }

    return <String, dynamic>{
      'pain_level': pick(_painLevel, _painLevels, 'none'),
      'odor': pick(_odor, _odorLevels, 'none'),
      'exudate_amount': pick(_exudateAmount, _exudateAmounts, 'none'),
      'exudate_type': pick(_exudateType, _exudateTypes, 'serous'),
      'periwound_redness': pick(_periwoundRedness, _rednessLevels, 'none'),
      'warmth_or_swelling': pick(_warmthOrSwelling, _yesNo, 'no'),
      'fever_or_chills': pick(_feverOrChills, _yesNo, 'no'),
      'wound_change_48h': pick(_woundChange48h, _woundChange, 'same'),
    };
  }

  void _showCaptureTips() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Photo tips',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 12),
            _ChecklistItem(
              icon: Icons.tips_and_updates_outlined,
              text: 'Use even lighting and avoid shadows or glare.',
            ),
            _ChecklistItem(
              icon: Icons.straighten,
              text: 'Keep the camera 20-30 cm from the wound.',
            ),
            _ChecklistItem(
              icon: Icons.crop_free,
              text: 'Include the full wound in the frame.',
            ),
            _ChecklistItem(
              icon: Icons.check_circle_outline,
              text: 'Retake if the preview looks blurry or dark.',
            ),
            SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _UploadMetadata {
  final String s3Key;
  final String encryptedKeyB64;
  final String ivB64;
  final String contentType;

  const _UploadMetadata({
    required this.s3Key,
    required this.encryptedKeyB64,
    required this.ivB64,
    required this.contentType,
  });
}

class _ChecklistItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ChecklistItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

}
