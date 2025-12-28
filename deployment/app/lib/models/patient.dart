import 'package:uuid/uuid.dart';

class Patient {
  final String id;
  final String name;
  final int? age;
  final String? gender;
  final String? bedNumber;
  final String? ward;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Patient({
    String? id,
    required this.name,
    this.age,
    this.gender,
    this.bedNumber,
    this.ward,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Create from database map
  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'] as String,
      name: map['name'] as String,
      age: map['age'] as int?,
      gender: map['gender'] as String?,
      bedNumber: map['bed_number'] as String?,
      ward: map['ward'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'gender': gender,
      'bed_number': bedNumber,
      'ward': ward,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Create a copy with updated fields
  Patient copyWith({
    String? name,
    int? age,
    String? gender,
    String? bedNumber,
    String? ward,
    String? notes,
  }) {
    return Patient(
      id: id,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      bedNumber: bedNumber ?? this.bedNumber,
      ward: ward ?? this.ward,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'Patient(id: $id, name: $name, age: $age, ward: $ward)';
  }
}
