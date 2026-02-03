import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/patient.dart';
import '../models/wound_record.dart';
import '../utils/constants.dart';

class DatabaseService {
  static final Map<String, DatabaseService> _instances = {};
  final String _dbName;

  factory DatabaseService({String? dbName}) {
    final resolvedName = dbName ?? AppConstants.databaseName;
    return _instances.putIfAbsent(
      resolvedName,
      () => DatabaseService._internal(resolvedName),
    );
  }

  DatabaseService._internal(this._dbName);

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), _dbName);
    
    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create patients table
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        age INTEGER,
        gender TEXT,
        bed_number TEXT,
        ward TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Create wound_records table
    await db.execute('''
      CREATE TABLE wound_records (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        location TEXT NOT NULL,
        notes TEXT,
        captured_by TEXT NOT NULL,
        image_path TEXT NOT NULL,
        mask_path TEXT,
        predicted_stage INTEGER NOT NULL,
        confidence REAL NOT NULL,
        stage_probabilities TEXT NOT NULL,
        wound_area_percent REAL NOT NULL,
        wound_area_cm2 REAL,
        tissue_mask_path TEXT,
        tissue_percentages TEXT,
        checklist_json TEXT,
        triage_json TEXT,
        captured_at TEXT NOT NULL,
        analyzed_at TEXT NOT NULL,
        FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for faster queries
    await db.execute(
      'CREATE INDEX idx_wound_records_patient_id ON wound_records (patient_id)'
    );
    await db.execute(
      'CREATE INDEX idx_wound_records_captured_at ON wound_records (captured_at)'
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE wound_records ADD COLUMN tissue_mask_path TEXT',
      );
      await db.execute(
        'ALTER TABLE wound_records ADD COLUMN tissue_percentages TEXT',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE wound_records ADD COLUMN checklist_json TEXT',
      );
      await db.execute(
        'ALTER TABLE wound_records ADD COLUMN triage_json TEXT',
      );
    }
  }

  // ==================== PATIENT OPERATIONS ====================

  // Insert a new patient
  Future<String> insertPatient(Patient patient) async {
    final db = await database;
    await db.insert('patients', patient.toMap());
    return patient.id;
  }

  // Get all patients
  Future<List<Patient>> getAllPatients() async {
    final db = await database;
    final maps = await db.query(
      'patients',
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => Patient.fromMap(map)).toList();
  }

  // Get patient by ID
  Future<Patient?> getPatientById(String id) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Patient.fromMap(maps.first);
  }

  // Update patient
  Future<void> updatePatient(Patient patient) async {
    final db = await database;
    await db.update(
      'patients',
      patient.toMap(),
      where: 'id = ?',
      whereArgs: [patient.id],
    );
  }

  // Delete patient
  Future<void> deletePatient(String id) async {
    final db = await database;
    await db.delete(
      'patients',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Search patients by name
  Future<List<Patient>> searchPatients(String query) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Patient.fromMap(map)).toList();
  }

  // Get patient count
  Future<int> getPatientCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM patients');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== WOUND RECORD OPERATIONS ====================

  // Insert a new wound record
  Future<String> insertWoundRecord(WoundRecord record) async {
    _validateWoundRecord(record);
    final db = await database;
    await db.insert('wound_records', record.toMap());
    return record.id;
  }

  // Update an existing wound record
  Future<void> updateWoundRecord(WoundRecord record) async {
    _validateWoundRecord(record);
    final db = await database;
    await db.update(
      'wound_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  // Get all wound records for a patient
  Future<List<WoundRecord>> getWoundRecordsForPatient(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'wound_records',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'captured_at DESC',
    );
    return maps.map((map) => WoundRecord.fromMap(map)).toList();
  }

  // Get wound records for a specific location
  Future<List<WoundRecord>> getWoundRecordsForLocation(
    String patientId,
    String location,
  ) async {
    final db = await database;
    final maps = await db.query(
      'wound_records',
      where: 'patient_id = ? AND location = ?',
      whereArgs: [patientId, location],
      orderBy: 'captured_at ASC',
    );
    return maps.map((map) => WoundRecord.fromMap(map)).toList();
  }

  // Get wound record by ID
  Future<WoundRecord?> getWoundRecordById(String id) async {
    final db = await database;
    final maps = await db.query(
      'wound_records',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return WoundRecord.fromMap(maps.first);
  }

  // Get latest wound record for a patient
  Future<WoundRecord?> getLatestWoundRecord(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'wound_records',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'captured_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return WoundRecord.fromMap(maps.first);
  }

  // Delete wound record
  Future<void> deleteWoundRecord(String id) async {
    final db = await database;
    await db.delete(
      'wound_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get wound record count for a patient
  Future<int> getWoundRecordCount(String patientId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM wound_records WHERE patient_id = ?',
      [patientId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Get all unique wound locations for a patient
  Future<List<String>> getWoundLocationsForPatient(String patientId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT location FROM wound_records WHERE patient_id = ? ORDER BY location',
      [patientId],
    );
    return result.map((row) => row['location'] as String).toList();
  }

  // Get recent wound records across all patients
  Future<List<WoundRecord>> getRecentWoundRecords({int limit = 10}) async {
    final db = await database;
    final maps = await db.query(
      'wound_records',
      orderBy: 'captured_at DESC',
      limit: limit,
    );
    return maps.map((map) => WoundRecord.fromMap(map)).toList();
  }

  // Get wound statistics
  Future<Map<String, dynamic>> getWoundStatistics() async {
    final db = await database;
    
    final totalRecords = await db.rawQuery(
      'SELECT COUNT(*) as count FROM wound_records'
    );
    
    final stageDistribution = await db.rawQuery('''
      SELECT predicted_stage, COUNT(*) as count 
      FROM wound_records 
      GROUP BY predicted_stage
    ''');

    final avgConfidence = await db.rawQuery(
      'SELECT AVG(confidence) as avg FROM wound_records'
    );

    return {
      'totalRecords': Sqflite.firstIntValue(totalRecords) ?? 0,
      'stageDistribution': {
        for (var row in stageDistribution)
          'Stage ${row['predicted_stage']}': row['count']
      },
      'averageConfidence': avgConfidence.first['avg'] ?? 0.0,
    };
  }

  void _validateWoundRecord(WoundRecord record) {
    if (record.patientId.trim().isEmpty) {
      throw ArgumentError('WoundRecord.patientId is required');
    }
    if (record.location.trim().isEmpty) {
      throw ArgumentError('WoundRecord.location is required');
    }
    if (record.capturedBy.trim().isEmpty) {
      throw ArgumentError('WoundRecord.capturedBy is required');
    }
    if (record.imagePath.trim().isEmpty) {
      throw ArgumentError('WoundRecord.imagePath is required');
    }
    if (record.predictedStage < 1 || record.predictedStage > 4) {
      throw ArgumentError('WoundRecord.predictedStage must be 1..4');
    }
    if (record.confidence.isNaN ||
        record.confidence.isInfinite ||
        record.confidence < 0 ||
        record.confidence > 1) {
      throw ArgumentError('WoundRecord.confidence must be in 0..1');
    }
    if (record.woundAreaPercent.isNaN ||
        record.woundAreaPercent.isInfinite ||
        record.woundAreaPercent < 0 ||
        record.woundAreaPercent > 100) {
      throw ArgumentError('WoundRecord.woundAreaPercent must be in 0..100');
    }
    if (record.stageProbabilities.isEmpty) {
      throw ArgumentError('WoundRecord.stageProbabilities cannot be empty');
    }
  }

  // Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
