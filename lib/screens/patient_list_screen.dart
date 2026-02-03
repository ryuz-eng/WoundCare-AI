import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../models/patient.dart';
import '../services/app_state.dart';
import '../services/database_service.dart';
import '../widgets/inline_tip.dart';
import '../widgets/stage_badge.dart';
import 'patient_detail_screen.dart';
import 'capture_screen.dart';

enum PatientSortMode { severity, recent }

class PatientListScreen extends StatefulWidget {
  final VoidCallback? onDataChanged;
  final bool showOverdueOnly;

  const PatientListScreen({
    super.key,
    this.onDataChanged,
    this.showOverdueOnly = false,
  });

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  List<Patient> _patientsByRecent = [];
  List<Patient> _patientsBySeverity = [];
  List<Patient> _filteredPatients = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String? _lastRoleId;
  Map<String, int?> _latestStageByPatientId = {};
  Map<String, String?> _latestConfidenceLabelByPatientId = {};
  Map<String, int?> _recheckDueByPatientId = {};
  PatientSortMode _sortMode = PatientSortMode.severity;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final roleId = context.watch<AppState>().role?.name ?? 'default';
    if (_lastRoleId != roleId) {
      _lastRoleId = roleId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadPatients();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final patients = await db.getAllPatients();
    final stageMap = <String, int?>{};
    final confidenceLabelMap = <String, String?>{};
    final recheckMap = <String, int?>{};
    final results = await Future.wait(
      patients.map((p) => db.getLatestWoundRecord(p.id)),
    );
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < patients.length; i++) {
      final record = results[i];
      stageMap[patients[i].id] = record?.predictedStage;
      confidenceLabelMap[patients[i].id] = record?.confidenceLabel;
      recheckMap[patients[i].id] = prefs.getInt('recheck_due_${patients[i].id}');
    }
    final indexedPatients = patients.asMap().entries.map((entry) {
      return (entry.key, entry.value);
    }).toList();
    indexedPatients.sort((a, b) {
      final stageA = stageMap[a.$2.id] ?? 0;
      final stageB = stageMap[b.$2.id] ?? 0;
      if (stageA != stageB) {
        return stageB.compareTo(stageA); // Stage 4 first
      }
      return a.$1.compareTo(b.$1); // preserve original order
    });
    final sortedPatients = indexedPatients.map((entry) => entry.$2).toList();
    final source = _sortMode == PatientSortMode.severity
        ? sortedPatients
        : patients;
    final overdueFiltered = _applyOverdueFilter(source, recheckMap);
    final filtered = _filterList(overdueFiltered, _searchController.text);
    setState(() {
      _patientsByRecent = patients;
      _patientsBySeverity = sortedPatients;
      _filteredPatients = filtered;
      _latestStageByPatientId = stageMap;
      _latestConfidenceLabelByPatientId = confidenceLabelMap;
      _recheckDueByPatientId = recheckMap;
      _isLoading = false;
    });
  }

  void _filterPatients(String query) {
    setState(() {
      _filteredPatients = _filterList(_currentSource(), query);
    });
  }

  List<Patient> _currentSource() {
    final source = _sortMode == PatientSortMode.severity
        ? _patientsBySeverity
        : _patientsByRecent;
    return _applyOverdueFilter(source);
  }

  List<Patient> _applyOverdueFilter(
    List<Patient> source, [
    Map<String, int?>? dueMap,
  ]) {
    if (!widget.showOverdueOnly) return source;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final map = dueMap ?? _recheckDueByPatientId;
    return source.where((patient) {
      final dueAt = map[patient.id];
      return dueAt != null && dueAt <= nowMs;
    }).toList();
  }

  List<Patient> _filterList(List<Patient> source, String query) {
    if (query.trim().isEmpty) return source;
    final q = query.toLowerCase();
    return source.where((p) {
      return p.name.toLowerCase().contains(q) ||
          (p.bedNumber?.toLowerCase().contains(q) ?? false) ||
          (p.ward?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showOverdueOnly)
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: const Icon(Icons.arrow_back, size: 18),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Overdue Re-checks',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'Patients',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    widget.showOverdueOnly
                        ? '${_filteredPatients.length} overdue'
                        : '${_filteredPatients.length} patient${_filteredPatients.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _filterPatients,
                      decoration: InputDecoration(
                        hintText: 'Search by name, ward, or bed...',
                        prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterPatients('');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const InlineTip(
                    text: 'Tip: Use Severity to surface urgent cases first.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Severity'),
                        selected: _sortMode == PatientSortMode.severity,
                        onSelected: (_) {
                          setState(() {
                            _sortMode = PatientSortMode.severity;
                            _filteredPatients = _filterList(
                              _currentSource(),
                              _searchController.text,
                            );
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Recent'),
                        selected: _sortMode == PatientSortMode.recent,
                        onSelected: (_) {
                          setState(() {
                            _sortMode = PatientSortMode.recent;
                            _filteredPatients = _filterList(
                              _currentSource(),
                              _searchController.text,
                            );
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Patient List
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _filteredPatients.isEmpty
                  ? SliverFillRemaining(child: _buildEmptyState())
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildPatientCard(_filteredPatients[index]),
                            );
                          },
                          childCount: _filteredPatients.length,
                        ),
                      ),
                    ),
          
          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildPatientCard(Patient patient) {
    return GestureDetector(
      onTap: () => _navigateToPatient(patient),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(
                  _getInitials(patient.name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (patient.ward != null) _buildInfoChip(Icons.local_hospital_outlined, patient.ward!),
                      if (patient.ward != null && patient.bedNumber != null) const SizedBox(width: 12),
                      if (patient.bedNumber != null) _buildInfoChip(Icons.bed_outlined, 'Bed ${patient.bedNumber}'),
                    ],
                  ),
                ],
              ),
            ),
            
            // Arrow
            if (_latestStageByPatientId[patient.id] != null) ...[
              StageBadge(
                stage: _latestStageByPatientId[patient.id]!,
                confidenceLabel:
                    _latestConfidenceLabelByPatientId[patient.id],
              ),
              const SizedBox(width: 8),
            ],
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
              onSelected: (value) {
                if (value == 'delete') {
                  _confirmDelete(patient);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: AppTheme.error, size: 20),
                      SizedBox(width: 8),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.textTertiary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.isNotEmpty;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSearch ? Icons.search_off : Icons.people_outline,
                size: 64,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              hasSearch ? 'No patients found' : 'No patients yet',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Try a different search term'
                  : 'Start by adding your first patient',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            if (!hasSearch) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _addNewPatient,
                icon: const Icon(Icons.add),
                label: const Text('Add Patient'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.isNotEmpty ? parts[0][0].toUpperCase() : '?';
  }

  void _navigateToPatient(Patient patient) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: patient)),
    ).then((_) async {
      await _loadPatients();
      widget.onDataChanged?.call();
    });
  }

  Future<void> _confirmDelete(Patient patient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Patient'),
        content: Text('Delete ${patient.name}? This removes all their records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final db = context.read<DatabaseService>();
    await db.deletePatient(patient.id);

    if (!mounted) return;
    await _loadPatients();
    widget.onDataChanged?.call();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Patient deleted')),
    );
  }

  void _addNewPatient() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    ).then((_) async {
      await _loadPatients();
      widget.onDataChanged?.call();
    });
  }
}
