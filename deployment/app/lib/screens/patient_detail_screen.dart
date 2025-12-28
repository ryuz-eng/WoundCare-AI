import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/patient.dart';
import '../models/wound_record.dart';
import '../services/database_service.dart';
import '../widgets/wound_card.dart';
import '../widgets/progress_chart.dart';
import 'capture_screen.dart';
import 'wound_history_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final Patient patient;

  const PatientDetailScreen({
    super.key,
    required this.patient,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<WoundRecord> _woundRecords = [];
  List<String> _woundLocations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final db = context.read<DatabaseService>();
    final records = await db.getWoundRecordsForPatient(widget.patient.id);
    final locations = await db.getWoundLocationsForPatient(widget.patient.id);
    
    setState(() {
      _woundRecords = records;
      _woundLocations = locations;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(widget.patient.name),
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
                          const SizedBox(height: 60),
                          Row(
                            children: [
                              _buildInfoChip(
                                Icons.bed,
                                widget.patient.bedNumber ?? 'N/A',
                              ),
                              const SizedBox(width: 8),
                              _buildInfoChip(
                                Icons.local_hospital,
                                widget.patient.ward ?? 'N/A',
                              ),
                              if (widget.patient.age != null) ...[
                                const SizedBox(width: 8),
                                _buildInfoChip(
                                  Icons.cake,
                                  '${widget.patient.age} years',
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
                  icon: const Icon(Icons.edit),
                  onPressed: _editPatient,
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'History'),
                ],
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

  Widget _buildOverviewTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            if (_woundRecords.length >= 2) ...[
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
                  record.stageName,
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
        builder: (context) => CaptureScreen(existingPatient: widget.patient),
      ),
    ).then((_) => _loadData());
  }

  void _viewWoundHistory(String location) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WoundHistoryScreen(
          patient: widget.patient,
          location: location,
        ),
      ),
    );
  }

  void _viewRecordDetail(WoundRecord record) {
    // TODO: Navigate to record detail screen
  }

  void _editPatient() {
    // TODO: Show edit patient dialog
  }
}
