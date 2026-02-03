import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/analysis_result.dart';
import '../utils/constants.dart';

class TriageService {
  static const Set<String> _riskLevels = {'low', 'medium', 'high', 'urgent'};
  static const Set<String> _painLevels = {'none', 'mild', 'moderate', 'severe'};
  static const Set<String> _odorLevels = {'none', 'mild', 'strong'};
  static const Set<String> _exudateAmounts = {
    'none',
    'low',
    'moderate',
    'heavy',
  };
  static const Set<String> _exudateTypes = {
    'serous',
    'purulent',
    'bloody',
    'mixed',
  };
  static const Set<String> _rednessLevels = {'none', 'mild', 'spreading'};
  static const Set<String> _yesNo = {'yes', 'no'};
  static const Set<String> _woundChange = {'better', 'same', 'worse'};

  void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  Future<Map<String, dynamic>> generateTriage({
    required AnalysisResult result,
    required Map<String, dynamic> checklist,
    required String patientId,
  }) async {
    final normalizedChecklist = _normalizeChecklist(checklist);
    final local = _localRules(result: result, checklist: normalizedChecklist);
    if (!AppConstants.enableTriageBackend || AppConstants.triageUrl.isEmpty) {
      return local;
    }

    try {
      final payload = {
        'patient_id': patientId, // de-identified app UUID
        'sequential_data': [
          {
            'type': 'cnn_output',
            'data': {
              'predicted_stage': result.predictedStage,
              'confidence': result.confidence,
              'wound_area_percent': result.woundAreaPercent,
              'stage_probabilities': result.stageProbabilities,
            },
          },
          {
            'type': 'checklist',
            'data': normalizedChecklist,
          },
        ],
        'rules_first_result': local,
      };

      final headers = <String, String>{'Content-Type': 'application/json'};
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken(true);
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } else {
        _log('TriageService: no signed-in user, using local rules fallback');
        return local;
      }

      final resp = await http
          .post(
            Uri.parse(AppConstants.triageUrl),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final parsed = jsonDecode(resp.body);
        if (parsed is Map<String, dynamic>) {
          final validated = _validateRemoteResponse(
            parsed,
            fallback: local,
          );
          return validated;
        }
        _log('TriageService: invalid JSON shape from backend, using local rules');
      } else {
        _log(
          'TriageService: backend status ${resp.statusCode}, using local rules',
        );
      }
    } catch (e) {
      _log('TriageService: remote triage failed ($e), using local rules');
    }

    return local;
  }

  Map<String, dynamic> _normalizeChecklist(Map<String, dynamic> raw) {
    String pick(
      String key,
      Set<String> allowed,
      String fallback,
    ) {
      final value = (raw[key] ?? fallback).toString().trim().toLowerCase();
      return allowed.contains(value) ? value : fallback;
    }

    return {
      'pain_level': pick('pain_level', _painLevels, 'none'),
      'odor': pick('odor', _odorLevels, 'none'),
      'exudate_amount': pick('exudate_amount', _exudateAmounts, 'none'),
      'exudate_type': pick('exudate_type', _exudateTypes, 'serous'),
      'periwound_redness': pick('periwound_redness', _rednessLevels, 'none'),
      'warmth_or_swelling': pick('warmth_or_swelling', _yesNo, 'no'),
      'fever_or_chills': pick('fever_or_chills', _yesNo, 'no'),
      'wound_change_48h': pick('wound_change_48h', _woundChange, 'same'),
    };
  }

  Map<String, dynamic> _validateRemoteResponse(
    Map<String, dynamic> remote, {
    required Map<String, dynamic> fallback,
  }) {
    final risk = (remote['risk_level'] ?? '').toString().trim().toLowerCase();
    final escalateRaw = remote['escalate_now'];
    final actionsRaw = remote['top_actions'];
    final rationale = (remote['rationale'] ?? '').toString().trim();

    if (!_riskLevels.contains(risk)) return fallback;
    if (escalateRaw is! bool) return fallback;
    if (actionsRaw is! List) return fallback;
    if (rationale.isEmpty) return fallback;

    final actions = actionsRaw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .take(3)
        .toList();
    if (actions.isEmpty) return fallback;

    final flagsRaw = remote['flags'];
    final flags = (flagsRaw is List ? flagsRaw : const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final source = (remote['source'] ?? 'rules').toString().trim();
    final reviewNote = (remote['review_note'] ??
            'AI assist only. Clinical judgment required.')
        .toString()
        .trim();

    return {
      'risk_level': risk,
      'escalate_now': escalateRaw,
      'top_actions': actions,
      'rationale': rationale,
      'flags': flags,
      'source': source.isEmpty ? 'rules' : source,
      'review_note': reviewNote.isEmpty
          ? 'AI assist only. Clinical judgment required.'
          : reviewNote,
    };
  }

  Map<String, dynamic> _localRules({
    required AnalysisResult result,
    required Map<String, dynamic> checklist,
  }) {
    final pain = (checklist['pain_level'] ?? 'none').toString();
    final odor = (checklist['odor'] ?? 'none').toString();
    final exudateType = (checklist['exudate_type'] ?? 'serous').toString();
    final exudateAmount = (checklist['exudate_amount'] ?? 'none').toString();
    final redness = (checklist['periwound_redness'] ?? 'none').toString();
    final worsening = (checklist['wound_change_48h'] ?? 'same').toString();
    final fever = (checklist['fever_or_chills'] ?? 'no').toString() == 'yes';

    String risk = 'low';
    bool escalate = false;
    final actions = <String>[];
    final flags = <String>[];

    if (fever && (odor == 'strong' || exudateType == 'purulent')) {
      risk = 'urgent';
      escalate = true;
      flags.add('Infection red flag');
    }
    if (worsening == 'worse' && (pain == 'severe' || redness == 'spreading')) {
      risk = 'urgent';
      escalate = true;
      flags.add('Rapid deterioration red flag');
    }
    if (result.predictedStage >= 4 && risk != 'urgent') {
      risk = 'high';
      flags.add('Advanced stage');
    }
    if (result.predictedStage >= 3 &&
        (odor == 'strong' || exudateAmount == 'heavy') &&
        risk != 'urgent') {
      risk = 'high';
      flags.add('Heavy burden at higher stage');
    }
    if (risk == 'low' && result.predictedStage == 2) {
      risk = 'medium';
    }
    if (risk == 'low' && result.confidence < 0.6) {
      risk = 'medium';
      flags.add('Low model confidence');
    }

    if (risk == 'urgent') {
      actions.add('Escalate to clinician immediately.');
      actions.add('Repeat photo/check within short interval.');
      actions.add('Document red-flag symptoms.');
    } else if (risk == 'high') {
      actions.add('Notify nurse/senior reviewer today.');
      actions.add('Plan close re-check and dressing review.');
      actions.add('Monitor for infection signs.');
    } else if (risk == 'medium') {
      actions.add('Review in next routine round.');
      actions.add('Repeat image with consistent angle.');
      actions.add('Monitor symptoms and wound trend.');
    } else {
      actions.add('Continue routine monitoring.');
      actions.add('Maintain pressure offloading and care plan.');
      actions.add('Re-check at scheduled interval.');
    }

    return {
      'risk_level': risk,
      'escalate_now': escalate,
      'top_actions': actions.take(3).toList(),
      'rationale':
          'Rule-based triage using stage/confidence + checklist context.',
      'flags': flags,
      'source': 'rules',
      'review_note': 'AI assist only. Clinical judgment required.',
    };
  }
}
