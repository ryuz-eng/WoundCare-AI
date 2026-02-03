import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../models/patient.dart';
import '../models/wound_record.dart';
import '../services/app_state.dart';
import '../services/database_service.dart';
import '../widgets/inline_tip.dart';
import '../widgets/wound_card.dart';
import '../widgets/progress_chart.dart';
import '../widgets/recommendation_dialog.dart';
import 'capture_screen.dart';
import 'wound_history_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final Patient patient;
  final int initialTabIndex;

  const PatientDetailScreen({
    super.key,
    required this.patient,
    this.initialTabIndex = 0,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Patient _patient;
  List<WoundRecord> _woundRecords = [];
  List<String> _woundLocations = [];
  bool _isLoading = true;
  bool _showClinicalDetails = false;
  int? _recheckDueAtMs;
  Timer? _recheckTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _patient = widget.patient;
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _recheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final db = context.read<DatabaseService>();
    final records = await db.getWoundRecordsForPatient(_patient.id);
    final locations = await db.getWoundLocationsForPatient(_patient.id);
    final prefs = await SharedPreferences.getInstance();
    final dueAt = prefs.getInt('recheck_due_${_patient.id}');
    
    setState(() {
      _woundRecords = records;
      _woundLocations = locations;
      _recheckDueAtMs = dueAt;
      _isLoading = false;
    });
    _scheduleRecheckTicker();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: AppTheme.primaryBlue,
              surfaceTintColor: Colors.transparent,
              iconTheme: const IconThemeData(color: Colors.white),
              actionsIconTheme: const IconThemeData(color: Colors.white),
              systemOverlayStyle: SystemUiOverlayStyle.light,
              title: Text(
                _patient.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primaryBlue,
                        AppTheme.primaryBlueDark,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 64),
                          Text(
                            _patient.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildInfoChip(
                                Icons.bed,
                                _patient.bedNumber ?? 'N/A',
                              ),
                              const SizedBox(width: 8),
                              _buildInfoChip(
                                Icons.local_hospital,
                                _patient.ward ?? 'N/A',
                              ),
                              if (_patient.age != null) ...[
                                const SizedBox(width: 8),
                                _buildInfoChip(
                                  Icons.cake,
                                  '${_patient.age} years',
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Export report',
                  icon: const Icon(Icons.download_rounded),
                  onPressed: _exportPatientReport,
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _editPatient,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  color: AppTheme.primaryBlue,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'History'),
                    ],
                  ),
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(),
            _buildHistoryTab(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewWoundRecord,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('New Analysis'),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaregiverSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Records: ${_woundRecords.length}  •  Locations: ${_woundLocations.length}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicalToggle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(
        onPressed: () => setState(() => _showClinicalDetails = !_showClinicalDetails),
        child: Text(
          _showClinicalDetails ? 'Hide clinical details' : 'Show clinical details',
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isCaregiver = context.watch<AppState>().isCaregiver;
    final showClinicalDetails = !isCaregiver || _showClinicalDetails;
    final latestStage =
        _woundRecords.isNotEmpty ? _woundRecords.first.predictedStage : null;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InlineTip(
              text: isCaregiver
                  ? 'Tip: Check the summary for simple next steps before a re-check.'
                  : 'Tip: Use re-checks to compare images at similar angles.',
            ),
            const SizedBox(height: 16),
            _buildOverviewSummaryCard(),
            const SizedBox(height: 16),
            if (isCaregiver) ...[
              _buildCaregiverSummary(),
              const SizedBox(height: 12),
              if (latestStage != null) ...[
                _buildRecommendationsCard(latestStage),
                const SizedBox(height: 12),
              ],
              _buildClinicalToggle(),
              const SizedBox(height: 16),
            ],

            if (_woundRecords.isNotEmpty) ...[
              _buildInsightsCard(showClinicalDetails),
              const SizedBox(height: 16),
            ],

            if (_hasTissueData()) ...[
              _buildTissueTrendCard(),
              const SizedBox(height: 16),
            ],

            if (isCaregiver) ...[
              _buildEducationSection(),
              const SizedBox(height: 16),
            ],

            if (showClinicalDetails) ...[
              // Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total Records',
                      _woundRecords.length.toString(),
                      Icons.analytics,
                      AppTheme.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Wound Locations',
                      _woundLocations.length.toString(),
                      Icons.location_on,
                      AppTheme.accentTeal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            
            // Wound Locations
            if (_woundLocations.isNotEmpty) ...[
              const Text(
                'Active Wound Locations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _woundLocations.map((location) {
                  return ActionChip(
                    label: Text(location),
                    avatar: const Icon(Icons.location_on, size: 18),
                    onPressed: () => _viewWoundHistory(location),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
            
            // Recent Records
            if (_woundRecords.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Analyses',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _tabController.animateTo(1),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._woundRecords.take(3).map((record) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildRecordTile(record),
              )),
            ],
            
            // Progress Chart (if multiple records)
            if (showClinicalDetails && _woundRecords.length >= 2) ...[
              const SizedBox(height: 24),
              const Text(
                'Wound Area Progress',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: ProgressChart(records: _woundRecords),
              ),
            ],
            
            // Empty State
            if (_woundRecords.isEmpty)
              _buildEmptyState(),
            
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_woundRecords.isEmpty) {
      return _buildEmptyState();
    }

    // Group records by location
    final groupedRecords = <String, List<WoundRecord>>{};
    for (final record in _woundRecords) {
      groupedRecords.putIfAbsent(record.location, () => []).add(record);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groupedRecords.length,
        itemBuilder: (context, index) {
          final location = groupedRecords.keys.elementAt(index);
          final records = groupedRecords[location]!;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => _viewWoundHistory(location),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              location,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${records.length} record${records.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _recheckLocation(location),
                        child: const Text('Re-check'),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: records.length,
                  itemBuilder: (context, recordIndex) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: WoundCard(
                        record: records[recordIndex],
                        onTap: () => _viewRecordDetail(records[recordIndex]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(WoundRecord record) {
    return Card(
      child: InkWell(
        onTap: () => _viewRecordDetail(record),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[200],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: File(record.imagePath).existsSync()
                      ? Image.file(
                          File(record.imagePath),
                          fit: BoxFit.cover,
                        )
                      : const Icon(Icons.image, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 12),
              
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.location,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy, HH:mm').format(record.capturedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Stage Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.getStageColor(record.predictedStage),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${record.stageName} • ${record.confidenceLabel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No wound records yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start by taking a photo of the wound',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addNewWoundRecord() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CaptureScreen(existingPatient: _patient),
      ),
    ).then((_) => _loadData());
  }

  void _viewWoundHistory(String location) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WoundHistoryScreen(
          patient: _patient,
          location: location,
        ),
      ),
    );
  }

  void _recheckLocation(String location) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          existingPatient: _patient,
          preselectedLocation: location,
        ),
      ),
    ).then((_) => _loadData());
  }

  void _viewRecordDetail(WoundRecord record) {
    final isCaregiver = context.read<AppState>().isCaregiver;
    final showClinicalDetails = !isCaregiver || _showClinicalDetails;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 300,
                      color: Colors.black,
                      child: File(record.imagePath).existsSync()
                          ? Image.file(
                              File(record.imagePath),
                              fit: BoxFit.contain,
                            )
                          : const Center(
                              child: Icon(Icons.image, size: 64, color: Colors.grey),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.getStageColor(record.predictedStage),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  record.stageName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (showClinicalDetails)
                                Text(
                                  record.formattedConfidence,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryBlue,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildDetailRow(
                            Icons.calendar_today,
                            'Date',
                            DateFormat('dd MMM yyyy, HH:mm').format(record.capturedAt),
                          ),
                          if (showClinicalDetails)
                            _buildDetailRow(
                              Icons.square_foot,
                              'Wound Area',
                              record.formattedWoundArea,
                            ),
                          _buildDetailRow(
                            Icons.badge,
                            'Captured By',
                            record.capturedBy,
                          ),
                          if (showClinicalDetails && record.triageData != null) ...[
                            const SizedBox(height: 12),
                            _buildTriageCard(record.triageData!),
                          ],
                          if (showClinicalDetails &&
                              record.notes != null &&
                              record.notes!.isNotEmpty)
                            _buildDetailRow(Icons.notes, 'Notes', record.notes!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPatient() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: _patient.name);
    final ageController =
        TextEditingController(text: _patient.age?.toString() ?? '');
    final bedController = TextEditingController(text: _patient.bedNumber ?? '');
    final wardController = TextEditingController(text: _patient.ward ?? '');
    final notesController = TextEditingController(text: _patient.notes ?? '');
    String? selectedGender = _patient.gender;

    final updated = await showDialog<Patient>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Patient'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ageController,
                    decoration: const InputDecoration(labelText: 'Age'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedGender,
                    decoration: const InputDecoration(labelText: 'Gender'),
                    items: const ['Male', 'Female', 'Other']
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (value) => selectedGender = value,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: wardController,
                    decoration: const InputDecoration(labelText: 'Ward'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bedController,
                    decoration: const InputDecoration(labelText: 'Bed Number'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;

                final ageValue = int.tryParse(ageController.text.trim());
                final updatedPatient = _patient.copyWith(
                  name: nameController.text.trim(),
                  age: ageValue,
                  gender: selectedGender,
                  bedNumber: bedController.text.trim().isEmpty
                      ? null
                      : bedController.text.trim(),
                  ward: wardController.text.trim().isEmpty
                      ? null
                      : wardController.text.trim(),
                  notes: notesController.text.trim().isEmpty
                      ? null
                      : notesController.text.trim(),
                );

                Navigator.pop(context, updatedPatient);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (updated == null) return;

    final db = context.read<DatabaseService>();
    await db.updatePatient(updated);

    if (!mounted) return;
    setState(() => _patient = updated);
    await _loadData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Patient updated')),
    );
  }

  void _scheduleRecheckTicker() {
    _recheckTimer?.cancel();
    if (_recheckDueAtMs == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_recheckDueAtMs! <= nowMs) return;
    _recheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_recheckDueAtMs == null || _recheckDueAtMs! <= now) {
        _recheckTimer?.cancel();
      }
      setState(() {});
    });
  }

  Widget _buildInsightsCard(bool showClinicalDetails) {
    final latest = _woundRecords.first;
    final previous = _woundRecords.length > 1 ? _woundRecords[1] : null;

    String trendLabel = 'No trend yet';
    String trendDetail = 'Add another analysis to see changes.';
    Color trendColor = AppTheme.textSecondary;

    if (previous != null) {
      final stageDelta = latest.predictedStage - previous.predictedStage;
      if (stageDelta < 0) {
        trendLabel = 'Improving';
        trendColor = AppTheme.success;
      } else if (stageDelta > 0) {
        trendLabel = 'Worsening';
        trendColor = AppTheme.error;
      } else {
        trendLabel = 'Stable';
        trendColor = AppTheme.warning;
      }

      trendDetail =
          'Stage ${previous.predictedStage} -> ${latest.predictedStage}';
    }

    final areaDelta = previous == null
        ? null
        : latest.woundAreaPercent - previous.woundAreaPercent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: trendColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.trending_up,
                  color: trendColor,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Trend',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    trendLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: trendColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                DateFormat('dd MMM').format(latest.capturedAt),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            trendDetail,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          if (showClinicalDetails && areaDelta != null) ...[
            const SizedBox(height: 8),
            Text(
              'Area change: ${areaDelta >= 0 ? '+' : ''}${areaDelta.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTriageCard(Map<String, dynamic> triage) {
    final risk = (triage['risk_level'] ?? 'low').toString().toLowerCase();
    final actions = ((triage['top_actions'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final flags = ((triage['flags'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .where((e) {
          final f = e.trim().toLowerCase();
          return !f.startsWith('gemini_') &&
              !f.startsWith('fallback_point=') &&
              !f.startsWith('gemini fallback') &&
              !f.startsWith('gemini blocked');
        })
        .toList();
    final source = (triage['source'] ?? 'rules').toString().toLowerCase();
    final engineLabel = source.contains('gemini')
        ? 'Gemini-assisted'
        : source.contains('bedrock')
            ? 'Bedrock-assisted'
            : 'Rules-only';

    final color = switch (risk) {
      'urgent' => AppTheme.error,
      'high' => const Color(0xFFE67E22),
      'medium' => AppTheme.warning,
      _ => AppTheme.success,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rule_outlined, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 8),
              const Text(
                'Checklist Triage',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  risk.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Engine: $engineLabel',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...actions.take(3).map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $a',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ),
                ),
          ],
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Flags: ${flags.join(' • ')}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasTissueData() {
    return _woundRecords.any((record) => record.tissuePercentages != null);
  }

  Widget _buildTissueTrendCard() {
    final records = _woundRecords
        .where((record) => record.tissuePercentages != null)
        .toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    if (records.length < 2) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tissue trend',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Granulation / Slough / Necrosis % over time',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(_buildTissueTrendData(records)),
          ),
          const SizedBox(height: 12),
          _buildTissueLegend(),
        ],
      ),
    );
  }

  LineChartData _buildTissueTrendData(List<WoundRecord> records) {
    final granulation = <FlSpot>[];
    final slough = <FlSpot>[];
    final necrosis = <FlSpot>[];

    for (var i = 0; i < records.length; i++) {
      final tissue = records[i].tissuePercentages ?? {};
      granulation.add(FlSpot(i.toDouble(), tissue['Granulation'] ?? 0));
      slough.add(FlSpot(i.toDouble(), tissue['Slough'] ?? 0));
      necrosis.add(FlSpot(i.toDouble(), tissue['Necrosis'] ?? 0));
    }

    return LineChartData(
      minY: 0,
      maxY: 100,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 20,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: AppTheme.border, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: 20,
            getTitlesWidget: (value, meta) => Text(
              value.toInt().toString(),
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= records.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  DateFormat('MM/dd').format(records[index].capturedAt),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textSecondary,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        _lineBar(granulation, const Color(0xFFEF4444)),
        _lineBar(slough, const Color(0xFFF59E0B)),
        _lineBar(necrosis, const Color(0xFF111827)),
      ],
    );
  }

  LineChartBarData _lineBar(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  Widget _buildTissueLegend() {
    return Wrap(
      spacing: 12,
      children: const [
        _LegendItem(label: 'Granulation', color: Color(0xFFEF4444)),
        _LegendItem(label: 'Slough', color: Color(0xFFF59E0B)),
        _LegendItem(label: 'Necrosis', color: Color(0xFF111827)),
      ],
    );
  }

  Widget _buildOverviewSummaryCard() {
    final hasRecords = _woundRecords.isNotEmpty;
    final latest = hasRecords ? _woundRecords.first : null;
    final stageColor = hasRecords
        ? AppTheme.getStageColor(latest!.predictedStage)
        : AppTheme.textSecondary;

    final headline = hasRecords
        ? '${latest!.stageName} • ${latest.confidenceLabel}'
        : 'No analyses yet';
    final subtext = hasRecords
        ? DateFormat('dd MMM yyyy, HH:mm').format(latest!.capturedAt)
        : 'Add an analysis to see updates.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: stageColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  color: stageColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Patient Summary',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: 13,
                        color: stageColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Last updated: $subtext',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildSummaryPill(
                'Records',
                _woundRecords.length.toString(),
              ),
              const SizedBox(width: 12),
              _buildSummaryPill(
                'Locations',
                _woundLocations.length.toString(),
              ),
            ],
          ),
          if (_recheckStatusText() != null) ...[
            const SizedBox(height: 10),
            _buildRecheckStatusPill(_recheckStatusText()!),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.primaryBlue,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String? _recheckStatusText() {
    if (_recheckDueAtMs == null) return null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final diffMs = _recheckDueAtMs! - nowMs;
    if (diffMs <= 0) return 'Re-check due now';
    final duration = Duration(milliseconds: diffMs);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return 'Re-check in $minutes:$seconds';
  }

  Widget _buildRecheckStatusPill(String text) {
    final isDue = text.contains('due now');
    final color = isDue ? AppTheme.error : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEducationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Caregiver Education',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildFaqTile(
          'What does the stage mean?',
          'Stages show how deep the wound is. Lower stages mean more superficial tissue damage.',
        ),
        _buildFaqTile(
          'When should I seek help?',
          'Seek help if there is fever, strong odor, heavy drainage, or rapid worsening.',
        ),
        _buildFaqTile(
          'How often should I recheck?',
          'Recheck daily for new wounds and every 1-2 days for existing wounds.',
        ),
      ],
    );
  }

  Widget _buildFaqTile(String title, String body) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              body,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPatientReport() async {
    if (_woundRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No records to export')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln(
      'Patient Name,Patient ID,Location,Stage,Confidence,Wound Area %,Captured At,Captured By,Notes',
    );

    for (final record in _woundRecords) {
      buffer.writeln([
        _csvField(_patient.name),
        _csvField(_patient.id),
        _csvField(record.location),
        _csvField(record.stageName),
        _csvField(record.formattedConfidence),
        _csvField(record.formattedWoundArea),
        _csvField(DateFormat('yyyy-MM-dd HH:mm').format(record.capturedAt)),
        _csvField(record.capturedBy),
        _csvField(record.notes ?? ''),
      ].join(','));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/wound_report_${_patient.id}.csv');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Wound report - ${_patient.name}',
    );
  }

  String _csvField(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsCard(int stage) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.getStageColor(stage).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.recommend,
              color: AppTheme.getStageColor(stage),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recommendations',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Based on current Stage $stage',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showRecommendations(stage),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  void _showRecommendations(int stage) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecommendationDialog(stage: stage),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendItem({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
