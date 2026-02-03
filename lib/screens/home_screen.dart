import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../models/patient.dart';
import '../models/wound_record.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/inline_tip.dart';
import '../widgets/stage_badge.dart';
import 'capture_screen.dart';
import 'patient_list_screen.dart';
import 'patient_detail_screen.dart';
import 'role_select_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<Patient> _recentPatients = [];
  List<WoundRecord> _recentRecords = [];
  int _totalPatients = 0;
  int _totalAnalyses = 0;
  bool _isLoading = true;
  String? _lastRoleId;
  Map<String, int?> _latestStageByPatientId = {};
  Map<String, String?> _latestLocationByPatientId = {};
  Map<String, String?> _latestConfidenceLabelByPatientId = {};
  Map<String, int> _recheckDueByPatientId = {};
  final Map<String, int> _overdueBannerLastShownAt = {};
  static const Duration _overduePopupDelay = Duration(seconds: 30);
  static const Duration _overdueBannerRepeat = Duration(seconds: 20);
  bool _overdueBannerVisible = false;
  int _recordsLast7Days = 0;
  Timer? _recheckTimer;
  final TextEditingController _searchController = TextEditingController();
  List<Patient> _allPatients = [];
  List<Patient> _searchResults = [];
  String _searchQuery = '';
  String _langCode = 'en';

  static const Map<String, Map<String, String>> _strings = {
    'language': {'en': 'Language', 'zh': '语言'},
    'language_english': {'en': 'English', 'zh': '英语'},
    'language_chinese': {'en': 'Simplified Chinese', 'zh': '简体中文'},
    'app_name': {'en': 'WoundCare AI', 'zh': '伤口护理AI'},
    'dashboard': {'en': 'Dashboard', 'zh': '仪表板'},
    'search_patients': {'en': 'Search patients...', 'zh': '搜索患者...'},
    'caregiver_mode': {
      'en': 'Caregiver mode: simple guidance and clear next steps.',
      'zh': '照护者模式：简明指导与清晰的下一步。',
    },
    'nurse_mode': {
      'en': 'Nurse mode: full clinical details and training tips.',
      'zh': '护士模式：完整临床细节与培训提示。',
    },
    'change': {'en': 'Change', 'zh': '切换'},
    'quick_tutorial': {'en': 'Quick tutorial', 'zh': '快速教程'},
    'tutorial_caregiver_sub': {
      'en': '3 steps to get reliable results.',
      'zh': '三步获得可靠结果。',
    },
    'tutorial_nurse_sub': {
      'en': '3 steps to keep records consistent.',
      'zh': '三步保持记录一致。',
    },
    'view': {'en': 'View', 'zh': '查看'},
    'tip_caregiver': {
      'en': 'Tip: Tap a patient to see the simple summary and next steps.',
      'zh': '提示：点选患者查看简明摘要和下一步。',
    },
    'tip_nurse': {
      'en': 'Tip: Keep ward/bed info updated for traceable follow-ups.',
      'zh': '提示：保持病房/床位信息更新，便于追踪复查。',
    },
    'total_patients': {'en': 'Total Patients', 'zh': '患者总数'},
    'analyses': {'en': 'Analyses', 'zh': '分析次数'},
    'quick_actions': {'en': 'Quick Actions', 'zh': '快捷操作'},
    'new_analysis': {'en': 'New Analysis', 'zh': '新分析'},
    'camera_or_gallery': {'en': 'Camera or gallery', 'zh': '相机或相册'},
    'recheck': {'en': 'Re-check', 'zh': '复查'},
    'overdue_followups': {'en': 'Overdue follow-ups', 'zh': '逾期随访'},
    'history': {'en': 'History', 'zh': '历史记录'},
    'view_records': {'en': 'View records', 'zh': '查看记录'},
    'recent_patients': {'en': 'Recent Patients', 'zh': '最近患者'},
    'view_all': {'en': 'View All', 'zh': '查看全部'},
    'no_recent_patients': {
      'en': 'No recent patients. Check Follow-up due for re-checks.',
      'zh': '暂无最近患者。请查看“随访到期”以安排复查。',
    },
    'delete': {'en': 'Delete', 'zh': '删除'},
    'no_patients_yet': {'en': 'No patients yet', 'zh': '暂无患者'},
    'start_by_adding': {
      'en': 'Start by adding a new patient\nor taking a wound photo',
      'zh': '先添加新患者\n或拍摄伤口照片',
    },
    'home': {'en': 'Home', 'zh': '首页'},
    'insights': {'en': 'Insights', 'zh': '洞察'},
    'patients': {'en': 'Patients', 'zh': '患者'},
    'recheck_not_scheduled': {'en': 'Re-check not scheduled', 'zh': '未安排复查'},
    'recheck_due_now': {'en': 'Re-check due now', 'zh': '现在需要复查'},
    'recheck_in': {'en': 'Re-check in {time}', 'zh': '复查倒计时 {time}'},
    'no_patients_found': {'en': 'No patients found', 'zh': '未找到患者'},
    'records_7d': {'en': 'Records 7d', 'zh': '近7天记录'},
    'overdue': {'en': 'Overdue', 'zh': '逾期'},
    'follow_up_due': {'en': 'Follow-up due', 'zh': '随访到期'},
    'no_followups_due': {
      'en': 'No follow-ups due right now.',
      'zh': '目前没有到期随访。',
    },
    'due_now': {'en': 'Due now', 'zh': '现在到期'},
    'overdue_minutes': {
      'en': 'Overdue {minutes}m',
      'zh': '逾期{minutes}分钟',
    },
    'overdue_seconds': {
      'en': 'Overdue {seconds}s',
      'zh': '逾期{seconds}秒',
    },
    'stage_trends_7_days': {
      'en': 'Stage trends from the last 7 days',
      'zh': '最近7天分期趋势',
    },
    'stage_trend': {'en': 'Stage trend', 'zh': '分期趋势'},
    'total_analyses': {
      'en': 'Total analyses: {total}',
      'zh': '分析总数：{total}',
    },
    'stage_1': {'en': 'Stage 1', 'zh': '第1期'},
    'stage_2': {'en': 'Stage 2', 'zh': '第2期'},
    'stage_3': {'en': 'Stage 3', 'zh': '第3期'},
    'stage_4': {'en': 'Stage 4', 'zh': '第4期'},
    'no_recent_analyses': {'en': 'No recent analyses', 'zh': '暂无最近分析'},
    'no_overdue_rechecks': {
      'en': 'No overdue re-checks right now',
      'zh': '目前没有逾期复查',
    },
    'sign_out_title': {'en': 'Sign out', 'zh': '退出登录'},
    'sign_out_message': {
      'en': 'Sign out of this device?',
      'zh': '要在此设备上退出登录吗？',
    },
    'cancel': {'en': 'Cancel', 'zh': '取消'},
    'sign_out': {'en': 'Sign out', 'zh': '退出登录'},
    'overdue_banner': {
      'en': 'Re-check overdue {label}: {name}{location}',
      'zh': '复查已逾期{label}：{name}{location}',
    },
    'dismiss': {'en': 'Dismiss', 'zh': '忽略'},
    'ward': {'en': 'Ward {ward}', 'zh': '病房 {ward}'},
    'bed': {'en': 'Bed {bed}', 'zh': '床位 {bed}'},
    'no_ward_bed': {'en': 'No ward/bed info', 'zh': '无病房/床位信息'},
    'welcome_caregiver': {'en': 'Welcome, caregiver', 'zh': '欢迎，照护者'},
    'welcome_nurse': {'en': 'Welcome, nurse', 'zh': '欢迎，护士'},
    'onboarding_caregiver_subtitle': {
      'en': 'Quick tips to help you get the most accurate result.',
      'zh': '快速提示，帮助你获得最准确的结果。',
    },
    'onboarding_nurse_subtitle': {
      'en': 'Quick tips to keep records consistent and useful.',
      'zh': '快速提示，帮助你保持记录一致且有用。',
    },
    'onboarding_caregiver_tip1': {
      'en': 'Use good lighting and include the full wound.',
      'zh': '使用充足光线并包含完整伤口。',
    },
    'onboarding_caregiver_tip2': {
      'en': 'Check History to see changes over time.',
      'zh': '查看历史以了解随时间的变化。',
    },
    'onboarding_caregiver_tip3': {
      'en': 'Seek help if symptoms worsen or look infected.',
      'zh': '若症状加重或疑似感染，请及时求助。',
    },
    'onboarding_nurse_tip1': {
      'en': 'Keep camera distance consistent for follow-ups.',
      'zh': '复查时保持拍摄距离一致。',
    },
    'onboarding_nurse_tip2': {
      'en': 'Capture ward/bed details for traceability.',
      'zh': '记录病房/床位信息以便追踪。',
    },
    'onboarding_nurse_tip3': {
      'en': 'Use confidence + trends to decide re-check.',
      'zh': '结合置信度与趋势决定复查。',
    },
    'got_it': {'en': 'Got it', 'zh': '知道了'},
    'how_to_use': {
      'en': 'How to use WoundCare AI',
      'zh': '如何使用伤口护理AI',
    },
    'tutorial_step_1_title': {'en': '1. Capture', 'zh': '1. 拍摄'},
    'tutorial_step_1_body': {
      'en': 'Use good lighting and keep the full wound in frame.',
      'zh': '使用充足光线并将完整伤口置于画面中。',
    },
    'tutorial_step_2_title': {'en': '2. Analyze', 'zh': '2. 分析'},
    'tutorial_step_2_body': {
      'en': 'Review the stage and confidence before saving.',
      'zh': '保存前查看分期和置信度。',
    },
    'tutorial_step_3_title': {'en': '3. Track', 'zh': '3. 跟踪'},
    'tutorial_step_3_body_caregiver': {
      'en': 'Use History to see progress and re-check when reminded.',
      'zh': '使用历史查看进展，并在提醒时复查。',
    },
    'tutorial_step_3_body_nurse': {
      'en': 'Use History to compare stages and follow-ups.',
      'zh': '使用历史比较分期与复查情况。',
    },
    'delete_patient_title': {'en': 'Delete Patient', 'zh': '删除患者'},
    'delete_patient_message': {
      'en': 'Delete {name}? This removes all their records.',
      'zh': '删除 {name}？这将删除其所有记录。',
    },
    'patient_deleted': {'en': 'Patient deleted', 'zh': '已删除患者'},
  };

  bool get _isZh => _langCode == 'zh';
  String _t(String key) {
    return _strings[key]?[_langCode] ?? _strings[key]?['en'] ?? key;
  }

  String _tWith(String key, Map<String, String> params) {
    var text = _t(key);
    params.forEach((param, value) {
      text = text.replaceAll('{$param}', value);
    });
    return text;
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('home_lang') ?? 'en';
    if (!mounted) return;
    setState(() => _langCode = code);
  }

  Future<void> _setLanguage(String code) async {
    if (_langCode == code) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_lang', code);
    if (!mounted) return;
    setState(() => _langCode = code);
  }

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _loadData();
  }

  @override
  void dispose() {
    _recheckTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<AppState>();
    final roleId = appState.role?.name ?? 'default';
    if (_lastRoleId != roleId) {
      _lastRoleId = roleId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
          _maybeShowRoleOnboarding();
        }
      });
    }
  }

  Future<void> _loadData() async {
    final db = context.read<DatabaseService>();
    final patients = await db.getAllPatients();
    final stats = await db.getWoundStatistics();
    final recentRecords = await db.getRecentWoundRecords(limit: 200);
    final stageMap = <String, int?>{};
    final locationMap = <String, String?>{};
    final confidenceLabelMap = <String, String?>{};
    final recheckMap = <String, int>{};
    final results = await Future.wait(
      patients.map((p) => db.getLatestWoundRecord(p.id)),
    );
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < patients.length; i++) {
      final record = results[i];
      stageMap[patients[i].id] = record?.predictedStage;
      locationMap[patients[i].id] = record?.location;
      confidenceLabelMap[patients[i].id] = record?.confidenceLabel;
      final dueAt = prefs.getInt('recheck_due_${patients[i].id}');
      if (dueAt != null) {
        recheckMap[patients[i].id] = dueAt;
      }
    }
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final recentCount = recentRecords
        .where((record) => record.capturedAt.isAfter(sevenDaysAgo))
        .length;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final overduePatientIds = recheckMap.entries
        .where((entry) => entry.value <= nowMs)
        .map((entry) => entry.key)
        .toSet();
    final indexedPatients = patients.asMap().entries.map((entry) {
      return (entry.key, entry.value);
    }).toList();
    indexedPatients.sort((a, b) {
      final stageA = stageMap[a.$2.id] ?? 0;
      final stageB = stageMap[b.$2.id] ?? 0;
      if (stageA != stageB) {
        return stageB.compareTo(stageA); // Stage 4 first
      }
      return a.$1.compareTo(b.$1);
    });
    final recentPatients = indexedPatients
        .map((entry) => entry.$2)
        .where((patient) => !overduePatientIds.contains(patient.id))
        .take(5)
        .toList();

    setState(() {
      _allPatients = patients;
      _recentPatients = recentPatients;
      _recentRecords = recentRecords;
      _latestStageByPatientId = stageMap;
      _latestLocationByPatientId = locationMap;
      _latestConfidenceLabelByPatientId = confidenceLabelMap;
      _recheckDueByPatientId = recheckMap;
      _totalPatients = patients.length;
      _totalAnalyses = stats['totalRecords'] ?? 0;
      _recordsLast7Days = recentCount;
      _isLoading = false;
    });
    _scheduleRecheckRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkOverduePopups();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Make status bar transparent
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _currentIndex == 0
          ? _buildDashboard()
          : _currentIndex == 1
              ? _buildAnalyticsTab()
              : PatientListScreen(onDataChanged: _loadData),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _buildFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildDashboard() {
    return CustomScrollView(
      slivers: [
        // Hero Header
        SliverToBoxAdapter(
          child: _buildHeader(),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: _buildRoleBanner(),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: _buildTutorialCard(),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: _buildInlineTip(),
          ),
        ),
          
        // Stats Cards
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _buildStatsRow(),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _buildAnalyticsPanel(),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _buildFollowUpDueSection(),
          ),
        ),
        
        // Quick Actions
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: _buildQuickActions(),
          ),
        ),
        
        // Recent Patients
        SliverToBoxAdapter(
          child: _buildRecentPatients(),
        ),
        
        // Bottom spacing for FAB
        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }

  Widget _buildRoleBanner() {
    final isCaregiver = context.watch<AppState>().isCaregiver;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(
            isCaregiver ? Icons.handshake : Icons.medical_services,
            color: AppTheme.primaryBlue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isCaregiver ? _t('caregiver_mode') : _t('nurse_mode'),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _openRoleSelect,
            child: Text(_t('change')),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialCard() {
    final isCaregiver = context.watch<AppState>().isCaregiver;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.school_outlined, color: AppTheme.primaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('quick_tutorial'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  isCaregiver
                      ? _t('tutorial_caregiver_sub')
                      : _t('tutorial_nurse_sub'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _showTutorialSheet,
            child: Text(_t('view')),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineTip() {
    final isCaregiver = context.watch<AppState>().isCaregiver;
    return InlineTip(
      text: isCaregiver ? _t('tip_caregiver') : _t('tip_nurse'),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 32),
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
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
                    _t('app_name'),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t('dashboard'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _buildLanguageButton(),
                  const SizedBox(width: 10),
                  _buildNotificationsButton(),
                  const SizedBox(width: 10),
                  _buildLogoutButton(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          
                  // Search Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          color: Colors.white.withOpacity(0.8),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: _t('search_patients'),
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                              ),
                              border: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: _clearSearch,
                          ),
                      ],
                    ),
                  ),
                  if (_searchQuery.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildSearchResults(),
                  ],
                ],
              ),
            );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            _t('total_patients'),
            _totalPatients.toString(),
            Icons.people_outline,
            const Color(0xFF3B82F6),
            const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            _t('analyses'),
            _totalAnalyses.toString(),
            Icons.analytics_outlined,
            const Color(0xFF10B981),
            const Color(0xFF0D9488),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color1,
    Color color2,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color1, color2],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color1.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('quick_actions'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  _t('new_analysis'),
                _t('camera_or_gallery'),
                Icons.camera_alt_rounded,
                AppTheme.primaryBlue,
                () => _navigateToCapture(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                _t('recheck'),
                _t('overdue_followups'),
                Icons.alarm_rounded,
                AppTheme.warning,
                _openOverduePatientsOrNotify,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                _t('history'),
                _t('view_records'),
                Icons.history_rounded,
                AppTheme.accentTeal,
                () => setState(() => _currentIndex = 2),
                ),
              ),
            ],
          ),
        ],
      );
    }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPatients() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final visiblePatients = _recentPatients.where((patient) {
      final dueAt = _recheckDueByPatientId[patient.id];
      return dueAt == null || dueAt > nowMs;
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
        Text(
          _t('recent_patients'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
              TextButton(
                onPressed: () => setState(() => _currentIndex = 2),
                child: Text(_t('view_all')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (visiblePatients.isEmpty)
            _recentPatients.isEmpty
                ? _buildEmptyState()
                : _buildEmptyRecentState()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visiblePatients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildPatientTile(visiblePatients[index]);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyRecentState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.assignment_turned_in_outlined,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _t('no_recent_patients'),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientTile(Patient patient) {
    final hasRecord = _latestStageByPatientId[patient.id] != null;
    final dueAt = _recheckDueByPatientId[patient.id];
    final recheckStatus = _recheckStatus(dueAt);
    final isDue = dueAt != null &&
        DateTime.now().millisecondsSinceEpoch >= dueAt;

    return GestureDetector(
      onTap: () => _navigateToPatient(patient),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  _getInitials(patient.name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
              Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                patient.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (patient.ward != null) ...[
                        Icon(
                          Icons.local_hospital_outlined,
                          size: 14,
                          color: AppTheme.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          patient.ward!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (patient.bedNumber != null) ...[
                        Icon(
                          Icons.bed_outlined,
                          size: 14,
                          color: AppTheme.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _tWith('bed', {
                            'bed': patient.bedNumber.toString(),
                          }),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  ],
                ),
              ),
              if (hasRecord) ...[
                StageBadge(
                  stage: _latestStageByPatientId[patient.id]!,
                  confidenceLabel:
                      _latestConfidenceLabelByPatientId[patient.id],
                ),
                const SizedBox(width: 8),
                _buildRecheckStatusPill(
                  recheckStatus.text,
                  isDue: recheckStatus.isDue,
                ),
                const SizedBox(width: 8),
                if (isDue) ...[
                  TextButton.icon(
                    onPressed: () => _recheckPatient(patient),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(_t('recheck')),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
                onSelected: (value) {
                  if (value == 'delete') {
                    _confirmDelete(patient);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, color: AppTheme.error, size: 20),
                      const SizedBox(width: 8),
                      Text(_t('delete')),
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

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline,
              size: 48,
              color: AppTheme.primaryBlue,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _t('no_patients_yet'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t('start_by_adding'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _navigateToCapture,
            icon: const Icon(Icons.add),
            label: Text(_t('new_analysis')),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded, _t('home')),
              _buildNavItem(1, Icons.insights_rounded, _t('insights')),
              const SizedBox(width: 80), // Space for FAB
              _buildNavItem(2, Icons.people_rounded, _t('patients')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryBlue : AppTheme.textTertiary,
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.large(
        onPressed: _navigateToCapture,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const Icon(Icons.add_a_photo_rounded, size: 32),
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

  ({String text, bool isDue}) _recheckStatus(int? dueAtMs) {
    if (dueAtMs == null) {
      return (text: _t('recheck_not_scheduled'), isDue: false);
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final diffMs = dueAtMs - nowMs;
    if (diffMs <= 0) {
      return (text: _t('recheck_due_now'), isDue: true);
    }
    final duration = Duration(milliseconds: diffMs);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final time = '$minutes:$seconds';
    return (text: _tWith('recheck_in', {'time': time}), isDue: false);
  }

  Widget _buildRecheckStatusPill(String text, {required bool isDue}) {
    final color = isDue ? AppTheme.error : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToCapture() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    ).then((_) => _loadData());
  }

  void _recheckPatient(Patient patient) {
    final location = _latestLocationByPatientId[patient.id];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          existingPatient: patient,
          preselectedLocation: location,
        ),
      ),
    ).then((_) => _loadData());
  }

  void _scheduleRecheckRefresh() {
    _recheckTimer?.cancel();
    if (_recheckDueByPatientId.isEmpty) return;

    _recheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_recheckDueByPatientId.isEmpty) {
        _recheckTimer?.cancel();
        return;
      }
      setState(() {});
      _checkOverduePopups();
    });
  }

  void _navigateToPatient(Patient patient) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: patient)),
    ).then((_) => _loadData());
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    final lower = trimmed.toLowerCase();
    setState(() {
      _searchQuery = trimmed;
      if (trimmed.isEmpty) {
        _searchResults = [];
      } else {
        _searchResults = _allPatients.where((p) {
          return p.name.toLowerCase().contains(lower);
        }).toList();
      }
    });
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _searchResults = [];
    });
    FocusScope.of(context).unfocus();
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.search_off, color: Colors.white.withOpacity(0.8)),
            const SizedBox(width: 8),
            Text(
              _t('no_patients_found'),
              style: TextStyle(color: Colors.white.withOpacity(0.85)),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _searchResults.length.clamp(0, 6),
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Colors.white.withOpacity(0.15),
        ),
        itemBuilder: (context, index) {
          final patient = _searchResults[index];
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: Colors.white.withOpacity(0.2),
              child: Text(
                _getInitials(patient.name),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              patient.name,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _patientSubtitle(patient),
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
            ),
            onTap: () => _openPatientHistory(patient),
          );
        },
      ),
    );
  }


  Widget _buildAnalyticsPanel() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final overdue = _recheckDueByPatientId.values
        .where((dueAt) => dueAt <= nowMs)
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildAnalyticsStatItem(
              label: _t('records_7d'),
              value: _recordsLast7Days.toString(),
              icon: Icons.timeline_rounded,
              color: AppTheme.accentTeal,
            ),
          ),
          _buildAnalyticsDivider(),
          Expanded(
            child: InkWell(
              onTap: overdue > 0 ? _openOverduePatients : null,
              borderRadius: BorderRadius.circular(12),
              child: _buildAnalyticsStatItem(
                label: _t('overdue'),
                value: overdue.toString(),
                icon: Icons.alarm_rounded,
                color: overdue > 0 ? AppTheme.error : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageButton() {
    return PopupMenuButton<String>(
      tooltip: _t('language'),
      onSelected: _setLanguage,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'en',
          child: Text(_t('language_english')),
        ),
        PopupMenuItem(
          value: 'zh',
          child: Text(_t('language_chinese')),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.language_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildNotificationsButton() {
    final count = _overdueCount();
    return InkWell(
      onTap: _handleNotificationsTap,
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Text(
                  count > 9 ? '9+' : count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return InkWell(
      onTap: _confirmSignOut,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.logout_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildFollowUpDueSection() {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final uniqueDue = <String, Patient>{};
    for (final patient in _allPatients) {
      final dueAt = _recheckDueByPatientId[patient.id];
      if (dueAt != null && dueAt <= nowMs) {
        uniqueDue[patient.id] = patient;
      }
    }
    final duePatients = uniqueDue.values.toList()
      ..sort((a, b) {
        final dueA = _recheckDueByPatientId[a.id] ?? 0;
        final dueB = _recheckDueByPatientId[b.id] ?? 0;
        return dueA.compareTo(dueB);
      });

    final preview = duePatients.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _t('follow_up_due'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            if (duePatients.isNotEmpty)
              TextButton(
                onPressed: _openOverduePatients,
                child: Text(_t('view_all')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (duePatients.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppTheme.success),
                const SizedBox(width: 10),
                Text(
                  _t('no_followups_due'),
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _buildOverduePatientTile(preview[index]);
            },
          ),
      ],
    );
  }

  Widget _buildOverduePatientTile(Patient patient) {
    final dueAt = _recheckDueByPatientId[patient.id];
    return InkWell(
      onTap: () => _navigateToPatient(patient),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  _getInitials(patient.name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _overdueLabelText(dueAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_latestStageByPatientId[patient.id] != null) ...[
              StageBadge(
                stage: _latestStageByPatientId[patient.id]!,
                confidenceLabel:
                    _latestConfidenceLabelByPatientId[patient.id],
              ),
              const SizedBox(width: 8),
            ],
            TextButton(
              onPressed: () => _recheckPatient(patient),
              child: Text(_t('recheck')),
            ),
          ],
        ),
      ),
    );
  }

  String _overdueLabelText(int? dueAtMs) {
    if (dueAtMs == null) return _t('due_now');
    final overdueMs =
        DateTime.now().millisecondsSinceEpoch - dueAtMs;
    final duration = Duration(milliseconds: overdueMs);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes > 0) {
      return _tWith('overdue_minutes', {
        'minutes': minutes.toString(),
      });
    }
    return _tWith('overdue_seconds', {
      'seconds': seconds.toString(),
    });
  }

  Widget _buildAnalyticsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final trendData = _buildStageTrendData();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildAnalyticsHeader()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _buildStageTrendCard(trendData),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildAnalyticsHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 20,
        20,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('insights'),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t('stage_trends_7_days'),
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageTrendCard(List<_StageDayCount> data) {
    final total = data.fold<int>(0, (sum, d) => sum + d.total);
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
          Text(
            _t('stage_trend'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _tWith('total_analyses', {'total': total.toString()}),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: data.isEmpty
                ? _buildEmptyAnalytics()
                : _buildStageTrendChart(data),
          ),
          const SizedBox(height: 12),
          _buildStageLegend(),
        ],
      ),
    );
  }

  Widget _buildStageTrendChart(List<_StageDayCount> data) {
    final maxTotal = data.fold<int>(0, (max, d) {
      return d.total > max ? d.total : max;
    });
    final maxY = math.max(4, maxTotal).toDouble();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (value) {
            return FlLine(color: AppTheme.border, strokeWidth: 1);
          },
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 2,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _weekdayLabel(data[index].day),
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
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: AppTheme.primaryBlueDark,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final day = data[group.x.toInt()];
              final label = _tooltipDateLabel(day.day);
              return BarTooltipItem(
                '$label\n'
                '${_stageTooltipLine(1, day.counts[0])}\n'
                '${_stageTooltipLine(2, day.counts[1])}\n'
                '${_stageTooltipLine(3, day.counts[2])}\n'
                '${_stageTooltipLine(4, day.counts[3])}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(data.length, (index) {
          final day = data[index];
          double running = 0;
          final items = <BarChartRodStackItem>[];
          for (var i = 0; i < day.counts.length; i++) {
            final value = day.counts[i].toDouble();
            if (value <= 0) continue;
            final toY = running + value;
            items.add(BarChartRodStackItem(
              running,
              toY,
              _stageColor(i + 1),
            ));
            running = toY;
          }

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: day.total.toDouble(),
                width: 18,
                rodStackItems: items,
                borderRadius: BorderRadius.circular(4),
                color: AppTheme.surfaceVariant,
              ),
            ],
          );
        }),
      ),
    );
  }

  Color _stageColor(int stage) => AppTheme.getStageColor(stage);

  String _stageTooltipLine(int stage, int count) {
    final label = _t('stage_$stage');
    return _isZh ? '$label：$count' : '$label: $count';
  }

  String _weekdayLabel(DateTime date) {
    if (!_isZh) {
      return DateFormat('E').format(date);
    }
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '周${weekdays[date.weekday - 1]}';
  }

  String _tooltipDateLabel(DateTime date) {
    if (!_isZh) {
      return DateFormat('EEE, MMM d').format(date);
    }
    return '${date.month}月${date.day}日 ${_weekdayLabel(date)}';
  }

  Widget _buildStageLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _buildLegendItem(_t('stage_1'), AppTheme.stage1),
        _buildLegendItem(_t('stage_2'), AppTheme.stage2),
        _buildLegendItem(_t('stage_3'), AppTheme.stage3),
        _buildLegendItem(_t('stage_4'), AppTheme.stage4),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
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

  Widget _buildEmptyAnalytics() {
    return Center(
      child: Text(
        _t('no_recent_analyses'),
        style: TextStyle(color: AppTheme.textSecondary),
      ),
    );
  }

  List<_StageDayCount> _buildStageTrendData() {
    final now = DateTime.now();
    final startDay = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final days = List<DateTime>.generate(
      7,
      (index) => DateTime(
        startDay.year,
        startDay.month,
        startDay.day + index,
      ),
    );
    final dayMap = <String, List<int>>{
      for (final day in days) DateFormat('yyyy-MM-dd').format(day): [0, 0, 0, 0],
    };

    for (final record in _recentRecords) {
      if (record.capturedAt.isBefore(startDay)) continue;
      final key = DateFormat('yyyy-MM-dd').format(record.capturedAt);
      final stage = record.predictedStage;
      final counts = dayMap[key];
      if (counts == null) continue;
      if (stage >= 1 && stage <= 4) {
        counts[stage - 1] = counts[stage - 1] + 1;
      }
    }

    return days.map((day) {
      final key = DateFormat('yyyy-MM-dd').format(day);
      final counts = dayMap[key] ?? [0, 0, 0, 0];
      return _StageDayCount(day: day, counts: counts);
    }).toList();
  }

  Widget _buildAnalyticsStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsDivider() {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: AppTheme.border,
    );
  }

  int _overdueCount() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return _recheckDueByPatientId.values
        .where((dueAt) => dueAt <= nowMs)
        .length;
  }

  void _handleNotificationsTap() {
    if (_overdueCount() > 0) {
      _openOverduePatients();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('no_overdue_rechecks'))),
    );
  }

  void _openOverduePatientsOrNotify() {
    if (_overdueCount() > 0) {
      _openOverduePatients();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('no_overdue_rechecks'))),
    );
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('sign_out_title')),
        content: Text(_t('sign_out_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('sign_out')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _openOverduePatients() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PatientListScreen(showOverdueOnly: true),
      ),
    );
  }

  void _checkOverduePopups() {
    if (!mounted || _recheckDueByPatientId.isEmpty) return;
    if (_overdueBannerVisible) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final thresholdMs = _overduePopupDelay.inMilliseconds;
    _pruneOverdueBannerState();
    final candidates = _recheckDueByPatientId.entries.where((entry) {
      final overdueMs = nowMs - entry.value;
      if (overdueMs < thresholdMs) return false;
      final key = _overdueKey(entry.key, entry.value);
      final lastShownAt = _overdueBannerLastShownAt[key] ?? 0;
      return nowMs - lastShownAt >= _overdueBannerRepeat.inMilliseconds;
    }).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    if (candidates.isEmpty) return;

    final selected = candidates.first;
    final patient = _findPatientById(selected.key);
    if (patient == null) return;

    final overdueMs = nowMs - selected.value;
    final label = _formatOverdueLabel(overdueMs);
    final location = _latestLocationByPatientId[selected.key];
    final locationText =
        location == null || location.trim().isEmpty ? '' : ' • $location';

    final key = _overdueKey(selected.key, selected.value);
    _overdueBannerLastShownAt[key] = nowMs;

    final messenger = ScaffoldMessenger.of(context);
    _overdueBannerVisible = true;
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(
          _tWith('overdue_banner', {
            'label': label,
            'name': patient.name,
            'location': locationText,
          }),
        ),
        leading: const Icon(Icons.alarm, color: AppTheme.error),
        backgroundColor: AppTheme.surface,
        actions: [
          TextButton(
            onPressed: () {
              _dismissOverdueBanner(messenger);
              _openOverduePatients();
            },
            child: Text(_t('view')),
          ),
          TextButton(
            onPressed: () => _dismissOverdueBanner(messenger),
            child: Text(_t('dismiss')),
          ),
        ],
      ),
    );
  }

  Patient? _findPatientById(String id) {
    for (final patient in _allPatients) {
      if (patient.id == id) return patient;
    }
    return null;
  }

  String _formatOverdueLabel(int overdueMs) {
    final duration = Duration(milliseconds: overdueMs);
    final totalMinutes = duration.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) {
      return _isZh ? '${hours}小时${minutes}分钟' : '${hours}h ${minutes}m';
    }
    return _isZh ? '${minutes}分钟' : '${minutes}m';
  }

  void _dismissOverdueBanner(ScaffoldMessengerState messenger) {
    messenger.hideCurrentMaterialBanner();
    _overdueBannerVisible = false;
  }

  void _pruneOverdueBannerState() {
    final expected = <String>{};
    for (final entry in _recheckDueByPatientId.entries) {
      expected.add(_overdueKey(entry.key, entry.value));
    }
    _overdueBannerLastShownAt
        .removeWhere((key, _) => !expected.contains(key));
  }

  String _overdueKey(String patientId, int dueAtMs) {
    return '$patientId|$dueAtMs';
  }

  String _patientSubtitle(Patient patient) {
    final parts = <String>[];
    if ((patient.ward ?? '').trim().isNotEmpty) {
      parts.add(_tWith('ward', {'ward': patient.ward!.trim()}));
    }
    if ((patient.bedNumber ?? '').trim().isNotEmpty) {
      parts.add(_tWith('bed', {'bed': patient.bedNumber!.trim()}));
    }
    return parts.isEmpty ? _t('no_ward_bed') : parts.join(' • ');
  }

  void _openPatientHistory(Patient patient) {
    _clearSearch();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientDetailScreen(
          patient: patient,
          initialTabIndex: 1,
        ),
      ),
    ).then((_) => _loadData());
  }

  Future<void> _maybeShowRoleOnboarding() async {
    if (!mounted) return;

    final appState = context.read<AppState>();
    if (!appState.shouldShowOnboarding) return;
    final isCaregiver = appState.isCaregiver;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCaregiver
                    ? _t('welcome_caregiver')
                    : _t('welcome_nurse'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isCaregiver
                    ? _t('onboarding_caregiver_subtitle')
                    : _t('onboarding_nurse_subtitle'),
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (isCaregiver) ...[
                _buildOnboardingTip(
                  Icons.photo_camera_outlined,
                  _t('onboarding_caregiver_tip1'),
                ),
                _buildOnboardingTip(
                  Icons.history_edu_outlined,
                  _t('onboarding_caregiver_tip2'),
                ),
                _buildOnboardingTip(
                  Icons.warning_amber_outlined,
                  _t('onboarding_caregiver_tip3'),
                ),
              ] else ...[
                _buildOnboardingTip(
                  Icons.straighten,
                  _t('onboarding_nurse_tip1'),
                ),
                _buildOnboardingTip(
                  Icons.badge_outlined,
                  _t('onboarding_nurse_tip2'),
                ),
                _buildOnboardingTip(
                  Icons.analytics_outlined,
                  _t('onboarding_nurse_tip3'),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(_t('got_it')),
                ),
              ),
            ],
          ),
        );
      },
    );
    appState.markOnboardingShown();
  }

  Widget _buildOnboardingTip(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  void _openRoleSelect() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
    ).then((_) => _loadData());
  }

  void _showTutorialSheet() {
    final isCaregiver = context.read<AppState>().isCaregiver;
    showModalBottomSheet<void>(
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
          children: [
            Text(
              _t('how_to_use'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _buildTutorialStep(
              _t('tutorial_step_1_title'),
              _t('tutorial_step_1_body'),
            ),
            _buildTutorialStep(
              _t('tutorial_step_2_title'),
              _t('tutorial_step_2_body'),
            ),
            _buildTutorialStep(
              _t('tutorial_step_3_title'),
              isCaregiver
                  ? _t('tutorial_step_3_body_caregiver')
                  : _t('tutorial_step_3_body_nurse'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_t('got_it')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorialStep(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Patient patient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('delete_patient_title')),
        content: Text(
          _tWith('delete_patient_message', {'name': patient.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final db = context.read<DatabaseService>();
    await db.deletePatient(patient.id);

    if (!mounted) return;
    await _loadData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('patient_deleted'))),
    );
  }
}

class _StageDayCount {
  final DateTime day;
  final List<int> counts;

  const _StageDayCount({
    required this.day,
    required this.counts,
  });

  int get total => counts.fold(0, (sum, value) => sum + value);
}
