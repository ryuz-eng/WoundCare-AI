import 'package:flutter/material.dart';
import '../config/theme.dart';

class ConfidenceChart extends StatelessWidget {
  final Map<String, double> probabilities;
  final int predictedStage;

  const ConfidenceChart({
    super.key,
    required this.probabilities,
    required this.predictedStage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: probabilities.entries.map((entry) {
        final stage = int.tryParse(entry.key.replaceAll('Stage ', '')) ?? 1;
        final isSelected = stage == predictedStage;
        final percentage = entry.value * 100;
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Stack(
                  children: [
                    // Background
                    Container(
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    // Fill
                    FractionallySizedBox(
                      widthFactor: entry.value.clamp(0.0, 1.0),
                      child: Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.getStageColor(stage)
                              : AppTheme.getStageColor(stage).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.getStageColor(stage).withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    // Percentage text
                    if (percentage > 10)
                      Positioned(
                        left: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: percentage > 30 ? Colors.white : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                child: Text(
                  '${percentage.toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
