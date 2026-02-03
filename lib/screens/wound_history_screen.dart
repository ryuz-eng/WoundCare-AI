import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/patient.dart';
import '../models/wound_record.dart';
import '../services/app_state.dart';
import '../services/database_service.dart';
import '../widgets/progress_chart.dart';
import 'tissue_annotation_screen.dart';

class WoundHistoryScreen extends StatefulWidget {
  final Patient patient;
  final String location;

  const WoundHistoryScreen({
    super.key,
    required this.patient,
    required this.location,
  });

  @override
  State<WoundHistoryScreen> createState() => _WoundHistoryScreenState();
}

class _WoundHistoryScreenState extends State<WoundHistoryScreen> {
  List<WoundRecord> _records = [];
  bool _isLoading = true;
  bool _showClinicalDetails = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    
    final db = context.read<DatabaseService>();
    final records = await db.getWoundRecordsForLocation(
      widget.patient.id,
      widget.location,
    );
    
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  appBar: AppBar(
    title: Text(widget.location),

    // ✅ ADD THIS
    actions: [
      IconButton(
        tooltip: 'Home',
        icon: const Icon(Icons.home_rounded),
        onPressed: () {

          // Option B (if you have named routes):
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        },
      ),
    ],
  ),
  body: _isLoading
      ? const Center(child: CircularProgressIndicator())
      : _buildContent(),
);
  }

  Widget _buildContent() {
    if (_records.isEmpty) {
      return const Center(
        child: Text('No records found for this location'),
      );
    }

    final isCaregiver = context.watch<AppState>().isCaregiver;
    final showClinicalDetails = !isCaregiver || _showClinicalDetails;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Card
          _buildSummaryCard(showClinicalDetails),

          if (isCaregiver)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => setState(
                    () => _showClinicalDetails = !_showClinicalDetails,
                  ),
                  child: Text(
                    _showClinicalDetails
                        ? 'Hide clinical details'
                        : 'Show clinical details',
                  ),
                ),
              ),
            ),
          
          // Progress Chart
          if (showClinicalDetails && _records.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    child: ProgressChart(records: _records),
                  ),
                ],
              ),
            ),
          ],
          
          // Timeline
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Timeline',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTimeline(showClinicalDetails),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(bool showClinicalDetails) {
    final latestRecord = _records.last;
    final firstRecord = _records.first;
    
    String progressText = 'First record';
    Color progressColor = AppTheme.info;
    
    if (_records.length >= 2) {
      final areaDiff = latestRecord.woundAreaPercent - firstRecord.woundAreaPercent;
      if (areaDiff < -5) {
        progressText = 'Significant improvement';
        progressColor = AppTheme.success;
      } else if (areaDiff < -1) {
        progressText = 'Improving';
        progressColor = AppTheme.success;
      } else if (areaDiff < 1) {
        progressText = 'Stable';
        progressColor = AppTheme.warning;
      } else if (areaDiff < 5) {
        progressText = 'Worsening';
        progressColor = AppTheme.error;
      } else {
        progressText = 'Significant worsening';
        progressColor = AppTheme.error;
      }
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue,
            AppTheme.primaryBlueDark,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Stage',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latestRecord.stageName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: progressColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  progressText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildSummaryItem(
                'Total Records',
                _records.length.toString(),
              ),
              const SizedBox(width: 24),
              if (showClinicalDetails) ...[
                _buildSummaryItem(
                  'Current Area',
                  latestRecord.formattedWoundArea,
                ),
                const SizedBox(width: 24),
                _buildSummaryItem(
                  'Confidence',
                  latestRecord.formattedConfidence,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(bool showClinicalDetails) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final record = _records[_records.length - 1 - index];
        final isFirst = index == _records.length - 1;
        final isLast = index == 0;
        
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isLast
                            ? AppTheme.primaryBlue
                            : AppTheme.getStageColor(record.predictedStage),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                    if (!isFirst)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.grey[300],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () => _showRecordDetail(record),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
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
                                  : const Icon(Icons.image),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.getStageColor(record.predictedStage),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${record.stageName} • ${record.confidenceLabel}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (isLast)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryBlue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'LATEST',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryBlue,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  DateFormat('dd MMM yyyy, HH:mm').format(record.capturedAt),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (showClinicalDetails)
                                  Text(
                                    'Area: ${record.formattedWoundArea} | Conf: ${record.formattedConfidence}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                if (record.tissuePercentages != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _tissueSummaryText(record.tissuePercentages!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRecordDetail(WoundRecord record) {
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
                          _buildDetailRow(Icons.calendar_today, 'Date',
                              DateFormat('dd MMM yyyy, HH:mm').format(record.capturedAt)),
                          _buildDetailRow(Icons.square_foot, 'Wound Area', record.formattedWoundArea),
                          _buildDetailRow(Icons.badge, 'Captured By', record.capturedBy),
                          if (!context.read<AppState>().isCaregiver &&
                              record.triageData != null) ...[
                            const SizedBox(height: 12),
                            _buildTriageCard(record.triageData!),
                          ],
                          if (record.maskPath != null) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _editTissueLabels(record),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit tissue labels'),
                            ),
                          ],
                          if (record.notes != null && record.notes!.isNotEmpty)
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
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

  String _tissueSummaryText(Map<String, double> data) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .map((e) => '${e.key}: ${e.value.toStringAsFixed(0)}%')
        .join(' · ');
  }

  Future<void> _editTissueLabels(WoundRecord record) async {
    if (record.maskPath == null) return;
    final maskFile = File(record.maskPath!);
    if (!await maskFile.exists()) return;
    final maskBytes = await maskFile.readAsBytes();

    final result = await Navigator.push<TissueAnnotationResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TissueAnnotationScreen(
          imagePath: record.imagePath,
          woundMaskBytes: maskBytes,
          patientId: widget.patient.id,
          existingTissueMaskPath: record.tissueMaskPath,
        ),
      ),
    );

    if (result == null) return;
    final db = context.read<DatabaseService>();
    await db.updateWoundRecord(
      record.copyWith(
        tissueMaskPath: result.maskPath,
        tissuePercentages: result.percentages,
      ),
    );
    await _loadRecords();
  }

}
