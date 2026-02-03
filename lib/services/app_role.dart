enum AppRole { nurse, caregiver }

extension AppRoleX on AppRole {
  String get id => name;
  String get label => this == AppRole.nurse ? 'Nurse' : 'Caregiver';
  String get shortDesc => this == AppRole.nurse
      ? 'Clinical details and training tools'
      : 'Simple guidance and next steps';
}