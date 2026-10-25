import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StaffOnboardingCard extends StatefulWidget {
  const StaffOnboardingCard({
    super.key,
    required this.title,
    required this.description,
    required this.step,
    required this.totalSteps,
    required this.arrowPointsUp,
    required this.isLastStep,
    required this.isSaving,
    required this.isConfirmingSkip,
    this.errorMessage,
    this.onBack,
    required this.onCancelSkip,
    required this.onNext,
    required this.onSkip,
    required this.onFinish,
  });

  final String title;
  final String description;
  final int step;
  final int totalSteps;
  final bool arrowPointsUp;
  final bool isLastStep;
  final bool isSaving;
  final bool isConfirmingSkip;
  final String? errorMessage;
  final VoidCallback? onBack;
  final VoidCallback onCancelSkip;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onFinish;

  @override
  State<StaffOnboardingCard> createState() => _StaffOnboardingCardState();
}

class _StaffOnboardingCardState extends State<StaffOnboardingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arrowAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _arrowAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardWidth = (size.width - 36).clamp(200.0, 420.0).toDouble();
    final maxCardHeight = (size.height - 116).clamp(240.0, 620.0).toDouble();
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cardWidth),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.blush),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxCardHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: _arrowAnimation,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(
                              0,
                              (widget.arrowPointsUp ? -1 : 1) *
                                  4 *
                                  _arrowAnimation.value,
                            ),
                            child: child,
                          ),
                          child: Icon(
                            widget.arrowPointsUp
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: AppColors.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Step ${widget.step} of ${widget.totalSteps}',
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 18,
                          color: AppColors.rose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: widget.step / widget.totalSteps,
                        minHeight: 4,
                        backgroundColor: AppColors.blush,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.isConfirmingSkip
                          ? 'Skip the staff tutorial?'
                          : widget.title,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isConfirmingSkip
                          ? 'Your progress will be saved, and you can replay the guide from the dashboard or profile any time.'
                          : widget.description,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                    if (widget.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: widget.isSaving ? null : widget.onFinish,
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('Retry save'),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (widget.isConfirmingSkip)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: widget.isSaving
                                  ? null
                                  : widget.onCancelSkip,
                              child: const Text(
                                'Keep learning',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primaryDark,
                              ),
                              onPressed: widget.isSaving
                                  ? null
                                  : widget.onFinish,
                              child: widget.isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Skip tutorial',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          TextButton(
                            onPressed: widget.isSaving ? null : widget.onSkip,
                            child: const Text('Skip'),
                          ),
                          const Spacer(),
                          if (widget.onBack != null)
                            TextButton(
                              onPressed: widget.isSaving ? null : widget.onBack,
                              child: const Text('Back'),
                            ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primaryDark,
                            ),
                            onPressed: widget.isSaving
                                ? null
                                : widget.isLastStep
                                ? widget.onFinish
                                : widget.onNext,
                            child: widget.isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(widget.isLastStep ? 'Finish' : 'Next'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
