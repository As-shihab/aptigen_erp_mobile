import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../models/workplace_model.dart';

class SelectWorkplaceStep extends StatelessWidget {
  final List<WorkplaceOption> options;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onCreateWorkplace;

  const SelectWorkplaceStep({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.onCreateWorkplace,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1,
      children: [
        for (final option in options)
          _WorkplaceTile(
            label: option.name,
            isOwn: option.isOwn,
            selected: value == option.id,
            onTap: () => onChanged(option.id),
          ),
        _CreateWorkplaceTile(onTap: onCreateWorkplace),
      ],
    );
  }
}

class _WorkplaceTile extends StatelessWidget {
  final String label;
  final bool isOwn;
  final bool selected;
  final VoidCallback onTap;

  const _WorkplaceTile({required this.label, required this.isOwn, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? AppColors.brand.withValues(alpha: 0.1) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.brand : AppColors.slate400.withValues(alpha: 0.3)),
        ),
        child: Stack(
          children: [
            if (isOwn)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Own', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.brand)),
                ),
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? AppColors.brand : null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateWorkplaceTile extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateWorkplaceTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.brand.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.brand.withValues(alpha: 0.4), style: BorderStyle.solid),
        ),
        child: const Center(
          child: Icon(Icons.add, color: AppColors.brand, size: 28),
        ),
      ),
    );
  }
}
