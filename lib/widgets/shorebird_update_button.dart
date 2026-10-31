import 'package:flutter/material.dart';

import '../services/shorebird_update_service.dart';
import '../theme/app_colors.dart';

class ShorebirdUpdateButton extends StatelessWidget {
  const ShorebirdUpdateButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShorebirdUpdatePromptState>(
      valueListenable: ShorebirdUpdateService.promptState,
      builder: (context, state, _) {
        if (state == ShorebirdUpdatePromptState.hidden) {
          return const SizedBox.shrink();
        }
        final ready = state == ShorebirdUpdatePromptState.restartRequired;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: ShorebirdUpdateService.requestUpdatePrompt,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.blush, width: 1.4),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.system_update_alt_rounded,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ready ? 'Update ready' : 'Ready to update',
                            style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ready
                                ? 'Restart the app to finish updating.'
                                : 'A new Angel’z Bites Cupcakes app update is ready.',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
