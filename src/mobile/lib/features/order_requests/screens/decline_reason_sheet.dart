import 'package:flutter/material.dart';
import '../../../core/decline_reasons.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

class DeclineChoice {
  const DeclineChoice({required this.category, this.note = ''});

  final String category;
  final String note;
}

/// Section 4.6 decline flow, step 1: why. A one-tap reason instead of a
/// bare text box — each category maps to its own canned customer message
/// (see decline_reasons.dart), which step 2 (the "let them know" prompt)
/// sends. "Other" is the one category that still needs the merchant's own
/// words, since nothing canned fits; every other category accepts an
/// optional note on top instead of requiring one.
Future<DeclineChoice?> showDeclineReasonSheet(BuildContext context) {
  return showModalBottomSheet<DeclineChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.control)),
    ),
    builder: (context) => const _DeclineReasonSheet(),
  );
}

class _DeclineReasonSheet extends StatefulWidget {
  const _DeclineReasonSheet();

  @override
  State<_DeclineReasonSheet> createState() => _DeclineReasonSheetState();
}

class _DeclineReasonSheetState extends State<_DeclineReasonSheet> {
  String? _category;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Only "other" needs the note to gate the submit button — but it's
    // simplest to just rebuild on every keystroke rather than branch the
    // listener registration on the (mutable) category.
    _noteController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _category != null &&
      (_category != 'other' || _noteController.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Why decline this request?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                "We'll suggest a message to send the customer based on what you pick.",
                style:
                    TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: _category,
                onChanged: (v) => setState(() => _category = v),
                child: Column(
                  children: [
                    for (final key in declineReasonKeys)
                      RadioListTile<String>(
                        value: key,
                        title: Text(declineReasonLabels[key]!,
                            style: const TextStyle(fontSize: 14)),
                        activeColor: AppColors.accent,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
              if (_category != null) ...[
                const SizedBox(height: 6),
                OxpField(
                  label: _category == 'other'
                      ? 'What happened'
                      : 'Add a note (optional)',
                  controller: _noteController,
                  hintText: _category == 'other'
                      ? 'Let the customer know why'
                      : 'e.g. restocking Thursday',
                ),
              ],
              const SizedBox(height: 18),
              OxpButton(
                label: 'Decline Request',
                variant: OxpButtonVariant.secondary,
                onPressed: _canSubmit
                    ? () => Navigator.pop(
                          context,
                          DeclineChoice(
                              category: _category!,
                              note: _noteController.text.trim()),
                        )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
