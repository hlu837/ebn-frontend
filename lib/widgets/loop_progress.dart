import 'package:flutter/material.dart';
import '../providers/loop_controller.dart';

/// Stepper layout removed.
class LoopProgress extends StatelessWidget {
  const LoopProgress({super.key, required this.stage, this.idleContent});

  final LoopStage stage;
  final Widget? idleContent;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

