import 'package:flutter/material.dart';

import '../core/theme/colors.dart';

/// The reference .sw switch (50 x 30). [activeColor] defaults to emerald.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged, this.activeColor});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final on = activeColor ?? AppColors.em;
    final knob = value ? 20.0 : 18.0;
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 50,
          height: 30,
          decoration: BoxDecoration(
            color: value ? on : AppColors.switchOffTrack,
            border: Border.all(color: value ? on : AppColors.switchOffKnob, width: 2),
            borderRadius: BorderRadius.circular(15),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: value ? 2 : 4),
              child: Container(
                width: knob,
                height: knob,
                decoration: BoxDecoration(
                  color: value ? AppColors.onEm : AppColors.switchOffKnob,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
