import 'package:flutter/material.dart';
import '../config/theme.dart';

class StageBadge extends StatelessWidget {
  final int stage;
  final String? confidenceLabel;

  const StageBadge({
    super.key,
    required this.stage,
    this.confidenceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isAlert = stage >= 3;
    final color = _stageColor(stage);
    final background = isAlert ? color : AppTheme.surfaceVariant;
    final textColor = isAlert ? Colors.white : AppTheme.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isAlert ? background : AppTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stage == 4) ...[
            BlinkingDot(color: Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            _buildLabel(),
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _buildLabel() {
    if (confidenceLabel == null || confidenceLabel!.isEmpty) {
      return 'Stage $stage';
    }
    return 'Stage $stage • ${confidenceLabel!}';
  }

  Color _stageColor(int stage) {
    if (stage >= 4) return AppTheme.error;
    if (stage == 3) return AppTheme.stage3;
    return AppTheme.textSecondary;
  }
}

class BlinkingDot extends StatefulWidget {
  final Color color;
  final double size;

  const BlinkingDot({
    super.key,
    required this.color,
    this.size = 8,
  });

  @override
  State<BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
