import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/patient.dart';
import '../services/database_service.dart';
import '../services/image_service.dart';
import '../utils/constants.dart';
import 'analysis_screen.dart';

class CaptureScreen extends StatefulWidget {
  final Patient? existingPatient;

  const CaptureScreen({super.key, this.existingPatient});

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

  @override
  void initState() {
    super.initState();
    _loadExistingPatients();

    if (widget.existingPatient != null) {
      _isNewPatient = false;
      _selectedPatient = widget.existingPatient;
      _populatePatientFields(widget.existingPatient!);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
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
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'New Analysis',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 60, bottom: 16),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image Selection
                    _buildImageSection(),
                    const SizedBox(height: 32),

                    // Patient Toggle
                    _buildSectionTitle('Patient'),
                    const SizedBox(height: 12),
                    _buildPatientToggle(),
                    const SizedBox(height: 20),

                    // Patient Form or Selector
                    if (_isNewPatient)
                      _buildNewPatientForm()
                    else
                      _buildExistingPatientSelector(),

                    const SizedBox(height: 32),

                    // Wound Details
                    _buildSectionTitle('Wound Details'),
                    const SizedBox(height: 16),
                    _buildWoundDetailsSection(),

                    const SizedBox(height: 40),

                    // Analyze Button
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildImageSection() {
    return GestureDetector(
      onTap: _selectImage,
      child: Container(
        width: double.infinity,
        height: 280,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _selectedImage != null ? AppTheme.primaryBlue : AppTheme.border,
            width: _selectedImage != null ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: _selectedImage != null ? _buildImagePreview() : _buildImagePlaceholder(),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Image.file(_selectedImage!, fit: BoxFit.cover),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Row(
            children: [
              _buildImageActionButton(Icons.refresh_rounded, _selectImage),
              const SizedBox(width: 8),
              _buildImageActionButton(
                Icons.close_rounded,
                () => setState(() => _selectedImage = null),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Image ready for analysis',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageActionButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.add_a_photo_rounded,
            size: 48,
            color: AppTheme.primaryBlue,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Tap to capture or select image',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Take a photo or choose from gallery',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),
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

  Widget _buildImageSourceChip(IconData icon, String label, bool isCamera) {
    return GestureDetector(
      onTap: () => _pickImage(fromCamera: isCamera),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.primaryBlue),
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

  Widget _buildPatientToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(child: _buildToggleOption('New Patient', _isNewPatient, () {
            setState(() {
              _isNewPatient = true;
              _selectedPatient = null;
            });
          })),
          Expanded(child: _buildToggleOption('Existing', !_isNewPatient, () {
            setState(() => _isNewPatient = false);
          })),
        ],
      ),
    );
  }

  Widget _buildToggleOption(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewPatientForm() {
    return Column(
      children: [
        _buildTextField(
          controller: _patientNameController,
          label: 'Patient Name',
          icon: Icons.person_outline,
          validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
        ),
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
                items: ['Male', 'Female', 'Other'],
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
            const Text('No existing patients', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _isNewPatient = true),
              child: const Text('Create New Patient'),
            ),
          ],
        ),
      );
    }

    return _buildDropdown(
      value: _selectedPatient?.id,
      label: 'Select Patient',
      icon: Icons.person_search_outlined,
      items: _existingPatients.map((p) => p.id).toList(),
      itemLabels: _existingPatients.map((p) => '${p.name}${p.bedNumber != null ? ' (Bed ${p.bedNumber})' : ''}').toList(),
      onChanged: (id) {
        final patient = _existingPatients.firstWhere((p) => p.id == id);
        setState(() => _selectedPatient = patient);
        _populatePatientFields(patient);
      },
      validator: (v) => v == null ? 'Please select a patient' : null,
    );
  }

  Widget _buildWoundDetailsSection() {
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
          label: 'Captured By (Your Name)',
          icon: Icons.badge_outlined,
          validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _notesController,
          label: 'Notes (Optional)',
          icon: Icons.notes_outlined,
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String label,
    required IconData icon,
    required List<String> items,
    List<String>? itemLabels,
    required Function(String?) onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary),
      ),
      items: items.asMap().entries.map((entry) {
        return DropdownMenuItem(
          value: entry.value,
          child: Text(itemLabels?[entry.key] ?? entry.value),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildAnalyzeButton() {
    final isReady = _selectedImage != null;
    
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: isReady ? _proceedToAnalysis : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isReady ? null : AppTheme.surfaceVariant,
          foregroundColor: isReady ? null : AppTheme.textTertiary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isReady ? Icons.analytics_rounded : Icons.camera_alt_outlined),
            const SizedBox(width: 12),
            Text(
              isReady ? 'Analyze Wound' : 'Select Image First',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectImage() async {
    final file = await _imageService.showPickerDialog(context);
    if (file != null) setState(() => _selectedImage = file);
  }

  Future<void> _pickImage({required bool fromCamera}) async {
    final file = fromCamera
        ? await _imageService.pickFromCamera()
        : await _imageService.pickFromGallery();
    if (file != null) setState(() => _selectedImage = file);
  }

  Future<void> _proceedToAnalysis() async {
    if (_selectedImage == null) return;
    if (!_formKey.currentState!.validate()) return;

    Patient patient;
    if (_isNewPatient) {
      patient = Patient(
        name: _patientNameController.text.trim(),
        age: int.tryParse(_patientAgeController.text),
        gender: _selectedGender,
        bedNumber: _bedNumberController.text.trim().isEmpty ? null : _bedNumberController.text.trim(),
        ward: _wardController.text.trim().isEmpty ? null : _wardController.text.trim(),
      );
      final db = context.read<DatabaseService>();
      await db.insertPatient(patient);
    } else {
      patient = _selectedPatient!;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnalysisScreen(
            imageFile: _selectedImage!,
            patient: patient,
            woundLocation: _selectedWoundLocation!,
            capturedBy: _capturedByController.text.trim(),
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          ),
        ),
      );
    }
  }
}
