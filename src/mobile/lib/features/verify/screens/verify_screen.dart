import 'dart:io';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import 'liveness_check_screen.dart';

/// Section 4.1/4.9's Tier 1 upgrade: Ghana Card number, business
/// registration number, notes, and — per Section 4.1/7.1 — a liveness-check
/// selfie captured via an active on-device challenge (see
/// liveness_check_screen.dart), all reviewed by a Back Office staff member.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyData {
  _VerifyData({required this.merchant, required this.submission});
  final Merchant merchant;
  final KYCSubmission? submission; // most recent, if any
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _api = ApiClient();
  late Future<_VerifyData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_VerifyData> _load() async {
    final merchantId = Session.instance.merchantId!;
    final results = await Future.wait([
      _api.getMerchant(merchantId),
      _api.listKYCSubmissions(merchantId),
    ]);
    final merchant = results[0] as Merchant;
    final submissions = results[1] as List<KYCSubmission>;
    return _VerifyData(
      merchant: merchant,
      submission: submissions.isEmpty ? null : submissions.first,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify & Withdraw')),
      body: FutureBuilder<_VerifyData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final tier1 = data.merchant.kycTier >= 1;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpace.xl, AppSpace.xl, AppSpace.xl,
              AppSpace.xl + bottomSafeInset(context),
            ),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlack,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available to withdraw',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'GH₵0.00',
                      style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Held securely by our licensed payment partner',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OxpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ChecklistRow(label: 'Phone verified', done: true),
                    const _ChecklistRow(label: 'Business info', done: true),
                    _ChecklistRow(label: 'Ghana Card details', done: tier1),
                    const _ChecklistRow(
                      label: 'Payout account (Mobile Money/Bank)',
                      done: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (tier1)
                const _InfoBanner(
                  color: AppColors.statusPaid,
                  text: "You're Tier 1 verified. Payout requests aren't "
                      'wired up yet, but your KYC is complete.',
                )
              else
                _KYCSection(
                  merchantId: data.merchant.id,
                  submission: data.submission,
                  api: _api,
                  onSubmitted: _refresh,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _KYCSection extends StatefulWidget {
  const _KYCSection({
    required this.merchantId,
    required this.submission,
    required this.api,
    required this.onSubmitted,
  });

  final String merchantId;
  final KYCSubmission? submission;
  final ApiClient api;
  final VoidCallback onSubmitted;

  @override
  State<_KYCSection> createState() => _KYCSectionState();
}

class _KYCSectionState extends State<_KYCSection> {
  final _formKey = GlobalKey<FormState>();
  late final _ghanaCardController = TextEditingController(
    text: widget.submission?.ghanaCardNumber ?? '',
  );
  late final _businessRegController = TextEditingController(
    text: widget.submission?.businessRegNumber ?? '',
  );
  late final _notesController = TextEditingController(
    text: widget.submission?.notes ?? '',
  );
  bool _submitting = false;
  bool _uploadingSelfie = false;
  String? _error;
  String? _selfiePhotoPath; // opaque filename returned by uploadKYCSelfie
  File? _selfiePreview;

  @override
  void dispose() {
    _ghanaCardController.dispose();
    _businessRegController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _runLivenessCheck() async {
    setState(() => _error = null);
    final captured = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => const LivenessCheckScreen()),
    );
    if (captured == null || !mounted) return;

    setState(() => _uploadingSelfie = true);
    try {
      final path = await widget.api.uploadKYCSelfie(
        widget.merchantId,
        captured.path,
      );
      setState(() {
        _selfiePhotoPath = path;
        _selfiePreview = File(captured.path);
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploadingSelfie = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selfiePhotoPath == null) {
      setState(() => _error = 'Complete the liveness check first');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.api.submitKYC(
        widget.merchantId,
        ghanaCardNumber: _ghanaCardController.text.trim(),
        selfiePhotoPath: _selfiePhotoPath!,
        businessRegNumber: _businessRegController.text.trim(),
        notes: _notesController.text.trim(),
      );
      widget.onSubmitted();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;

    // Pending: awaiting review, nothing more to do — no form.
    if (submission != null && submission.status == 'pending') {
      return const _InfoBanner(
        color: AppColors.statusPending,
        text: 'Submitted — a reviewer will confirm your Tier 1 status soon.',
      );
    }

    final showReviewerNote =
        submission != null &&
        (submission.status == 'rejected' ||
            submission.status == 'more_info_requested') &&
        (submission.reviewerNotes?.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (submission != null && submission.status == 'more_info_requested')
          const _InfoBanner(
            color: AppColors.statusPartial,
            text: 'More information needed — update the details below and resubmit.',
          )
        else if (submission != null && submission.status == 'rejected')
          const _InfoBanner(
            color: AppColors.statusDeclined,
            text: 'Your previous submission was rejected. You can submit again below.',
          ),
        if (showReviewerNote) ...[
          const SizedBox(height: 8),
          Text(
            'Reviewer note: ${submission.reviewerNotes}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Form(
          key: _formKey,
          child: OxpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Request Tier 1 verification',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlack,
                  ),
                ),
                const SizedBox(height: 14),
                OxpField(
                  label: 'Ghana Card number',
                  controller: _ghanaCardController,
                  hintText: 'GHA-000000000-0',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                OxpField(
                  label: 'Business registration number (optional)',
                  controller: _businessRegController,
                  hintText: 'BN-000000000',
                ),
                const SizedBox(height: 14),
                OxpField(
                  label: 'Notes (optional)',
                  controller: _notesController,
                  hintText: 'Anything else a reviewer should know',
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Liveness check',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlack,
                  ),
                ),
                const SizedBox(height: 8),
                if (_selfiePreview != null)
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: Image.file(
                          _selfiePreview!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, size: 16, color: AppColors.statusPaid),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Selfie captured',
                                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              ),
                            ),
                            TextButton(
                              onPressed: _uploadingSelfie ? null : _runLivenessCheck,
                              child: const Text('Retake'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  OxpButton(
                    label: _uploadingSelfie ? 'Uploading…' : 'Start liveness check',
                    loading: _uploadingSelfie,
                    variant: OxpButtonVariant.secondary,
                    onPressed: _uploadingSelfie ? null : _runLivenessCheck,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.statusDeclined,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                OxpButton(
                  label: _submitting ? 'Submitting…' : 'Submit for review',
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The liveness check confirms a real person is present at signup — '
          'it stops a static printed/screen photo, not a sophisticated '
          'pre-recorded video.',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 11),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.label, required this.done});
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: done ? AppColors.statusPaid : AppColors.textDisabled,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: done ? AppColors.primaryBlack : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
