import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_role.dart';

class AppState extends ChangeNotifier {
  static const _roleKey = 'app_role';
  AppRole? _role;
  bool _shouldShowOnboarding = false;

  AppRole? get role => _role;
  bool get hasRole => _role != null;
  bool get isNurse => _role == AppRole.nurse;
  bool get isCaregiver => _role == AppRole.caregiver;
  bool get shouldShowOnboarding => _shouldShowOnboarding;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_roleKey);
    _role = _fromId(id);
    _shouldShowOnboarding = false;
    notifyListeners();
  }

  Future<void> setRole(AppRole role) async {
    _shouldShowOnboarding = _role != role;
    _role = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role.id);
    notifyListeners();
  }

  Future<void> clearRole() async {
    _role = null;
    _shouldShowOnboarding = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    notifyListeners();
  }

  void markOnboardingShown() {
    _shouldShowOnboarding = false;
  }

  AppRole? _fromId(String? id) {
    if (id == null) return null;
    for (final role in AppRole.values) {
      if (role.id == id) return role;
    }
    return null;
  }
}
