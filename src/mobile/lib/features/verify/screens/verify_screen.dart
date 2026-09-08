import 'dart:io';

import 'package:image_picker/image_picker.dart';

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
  _VerifyData({
    required this.merchant,
    required this.submission,
    required this.limits,
  });
  final Merchant merchant;
  final KYCSubmission? submission; // most recent, if any
  final MerchantLimits limits;
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
      _api.getMerchantLimits(merchantId),
    ]);
    final merchant = results[0] as Merchant;
    final submissions = results[1] as List<KYCSubmission>;
    return _VerifyData(
      merchant: merchant,
      submission: submissions.isEmpty ? null : submissions.first,
      limits: results[2] as MerchantLimits,
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
          final tier = data.merchant.kycTier;
          final verified = tier >= 1;
          // A verified informal trader can still go on to Tier 2 by
          // registering their business, so the form stays available to
          // them — only Tier 2 is the end of the ladder.
          final canUpgrade = tier < 2;

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
                    _ChecklistRow(label: 'Ghana Card details', done: verified),
                    _ChecklistRow(
                      label: 'Business registration (Tier 2)',
                      done: tier >= 2,
                    ),
                    const _ChecklistRow(
                      label: 'Payout account (Mobile Money/Bank)',
                      done: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (verified) ...[
                _InfoBanner(
                  color: AppColors.statusPaid,
                  text: tier >= 2
                      ? "You're Tier 2 verified as a registered business. "
                            "Payout requests aren't wired up yet, but your "
                            'verification is complete.'
                      : "You're Tier 1 verified. Payout requests aren't "
                            'wired up yet, but your verification is complete.',
                ),
                const SizedBox(height: 16),
              ],
              _LimitsCard(limits: data.limits),
              if (canUpgrade) ...[
                const SizedBox(height: 20),
                _KYCSection(
                  merchantId: data.merchant.id,
                  submission: data.submission,
                  api: _api,
                  onSubmitted: _refresh,
                ),
              ],
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
  late final _tinController = TextEditingController(
    text: widget.submission?.tin ?? '',
  );
  late final _notesController = TextEditingController(
    text: widget.submission?.notes ?? '',
  );

  /// The fork. Defaults to whatever a returning submission chose, so a
  /// merchant sent back for more info lands on the form they were already
  /// filling in rather than the other one.
  late String _businessType =
      widget.submission?.businessType ?? BusinessTypes.informal;
  late String? _entityType = widget.submission?.entityType;

  bool _submitting = false;
  bool _uploadingSelfie = false;
  bool _uploadingCert = false;
  String? _error;
  String? _selfiePhotoPath; // opaque filename returned by uploadKYCSelfie
  File? _selfiePreview;
  String? _certPath; // opaque filename returned by uploadKYCRegistrationCert
  String? _certLabel;

  bool get _isRegistered => _businessType == BusinessTypes.registered;

  @override
  void dispose() {
    _ghanaCardController.dispose();
    _businessRegController.dispose();
    _tinController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Certificate capture. image_picker is what this app ships, so the
  /// merchant photographs the certificate or picks an existing image — the
  /// API also accepts a PDF, which a file picker would unlock if one is
  /// ever added.
  ///
  /// Note this exists only for the registration certificate. There is no
  /// equivalent for the Ghana Card, deliberately: that is captured as a
  /// number plus a liveness check because copying or scanning Ghana Card
  /// IDs is restricted. Do not add a card capture here.
  Future<void> _pickCertificate() async {
    setState(() => _error = null);
    final picked = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo of the certificate'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from photos'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final file = await ImagePicker().pickImage(source: picked, imageQuality: 85);
    if (file == null || !mounted) return;

    setState(() => _uploadingCert = true);
    try {
      final path = await widget.api.uploadKYCRegistrationCert(
        widget.merchantId,
        file.path,
      );
      setState(() {
        _certPath = path;
        _certLabel = file.name;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploadingCert = false);
    }
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
    if (_isRegistered && _entityType == null) {
      setState(() => _error = 'Choose the type of business you registered');
      return;
    }
    if (_isRegistered && _certPath == null) {
      setState(() => _error = 'Add a photo of your registration certificate');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.api.submitKYC(
        widget.merchantId,
        businessType: _businessType,
        ghanaCardNumber: _ghanaCardController.text.trim(),
        selfiePhotoPath: _selfiePhotoPath!,
        businessRegNumber: _businessRegController.text.trim(),
        tin: _isRegistered ? _tinController.text.trim() : null,
        entityType: _isRegistered ? _entityType : null,
        registrationCertPath: _isRegistered ? _certPath : null,
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
                Text(
                  _isRegistered
                      ? 'Verify your registered business'
                      : 'Verify your business',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlack,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Which describes your business?',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                _ForkOption(
                  label: 'I trade on my own',
                  detail:
                      'No registered company. Your Ghana Card and a quick '
                      'face check are all we need.',
                  selected: !_isRegistered,
                  onTap: () =>
                      setState(() => _businessType = BusinessTypes.informal),
                ),
                const SizedBox(height: 8),
                _ForkOption(
                  label: 'My business is registered',
                  detail:
                      'Registered with the Registrar-General. Needs your TIN '
                      'and certificate too, and unlocks higher limits.',
                  selected: _isRegistered,
                  onTap: () =>
                      setState(() => _businessType = BusinessTypes.registered),
                ),
                const SizedBox(height: 18),
                OxpField(
                  label: 'Ghana Card number',
                  controller: _ghanaCardController,
                  hintText: 'GHA-000000000-0',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 6),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 13, color: AppColors.textDisabled),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'We store the number only — never a photo or scan of '
                        'your card. This is how we keep someone else from '
                        'collecting money in your name.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_isRegistered) ...[
                  OxpField(
                    label: 'Business registration number',
                    controller: _businessRegController,
                    hintText: 'CS000000000',
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Required for a registered business'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  OxpField(
                    label: 'TIN',
                    controller: _tinController,
                    hintText: 'C0000000000',
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Required for a registered business'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _entityType,
                    decoration: const InputDecoration(
                      labelText: 'Type of business',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in kEntityTypes.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (v) => setState(() => _entityType = v),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Registration certificate',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlack,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_certPath != null)
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            size: 16, color: AppColors.statusPaid),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _certLabel ?? 'Certificate added',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: _uploadingCert ? null : _pickCertificate,
                          child: const Text('Replace'),
                        ),
                      ],
                    )
                  else
                    OxpButton(
                      label: _uploadingCert ? 'Uploading…' : 'Add certificate',
                      loading: _uploadingCert,
                      variant: OxpButtonVariant.secondary,
                      onPressed: _uploadingCert ? null : _pickCertificate,
                    ),
                  const SizedBox(height: 14),
                ] else ...[
                  OxpField(
                    label: 'Business registration number (optional)',
                    controller: _businessRegController,
                    hintText: 'BN-000000000',
                  ),
                  const SizedBox(height: 14),
                ],
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
                  label: _submitting
                      ? 'Submitting…'
                      : 'Submit for Tier ${_isRegistered ? 2 : 1} review',
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


/// One of the two verification paths, presented as a choice the merchant
/// makes about their own business rather than as a tier they're applying
/// for — "my business is registered" is a fact they know; "Tier 2" is not.
class _ForkOption extends StatelessWidget {
  const _ForkOption({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected ? AppColors.primaryBlack : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? AppColors.primaryBlack : AppColors.textDisabled,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlack,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


String _ghs(int pesewas) =>
    'GH\u20B5${(pesewas ~/ 100)}.${(pesewas % 100).toString().padLeft(2, '0')}';

/// What this merchant's tier lets them collect, and how much is left.
///
/// The limits ship unset — they're Bank of Ghana-governed thresholds that
/// nobody has entered yet — so the common case is "no limits". The card
/// says that plainly instead of drawing three full bars, which would imply
/// a cap exists and the merchant is nowhere near it.
class _LimitsCard extends StatelessWidget {
  const _LimitsCard({required this.limits});

  final MerchantLimits limits;

  @override
  Widget build(BuildContext context) {
    return OxpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Your limits',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlack,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.fieldFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Tier ${limits.kycTier}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (limits.isUncapped)
            const Text(
              'No collection limits apply to your account right now.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            )
          else ...[
            if (limits.perTransactionLimitPesewas > 0)
              _LimitRow(
                label: 'Most in one payment',
                value: _ghs(limits.perTransactionLimitPesewas),
              ),
            if (limits.dailyLimitPesewas > 0)
              _LimitRow(
                label: 'Left today',
                value: '${_ghs(limits.dailyRemainingPesewas)} '
                    'of ${_ghs(limits.dailyLimitPesewas)}',
                used: limits.todayPesewas,
                total: limits.dailyLimitPesewas,
              ),
            if (limits.cumulativeLimitPesewas > 0)
              _LimitRow(
                label: 'Left in total',
                value: '${_ghs(limits.cumulativeRemainingPesewas)} '
                    'of ${_ghs(limits.cumulativeLimitPesewas)}',
                used: limits.cumulativePesewas,
                total: limits.cumulativeLimitPesewas,
              ),
          ],
          const SizedBox(height: 8),
          Text(
            limits.kycTier >= 2
                ? 'Need more room? Contact support.'
                : 'Verifying below raises these.',
            style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
          ),
        ],
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.label,
    required this.value,
    this.used,
    this.total,
  });

  final String label;
  final String value;
  final int? used;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final u = used, t = total;
    // Integer arithmetic to a percentage, then one division at the very
    // edge purely to satisfy LinearProgressIndicator — money itself never
    // becomes a double anywhere in this app.
    final percent = (u != null && t != null && t > 0)
        ? (u * 100 ~/ t).clamp(0, 100)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlack,
                ),
              ),
            ],
          ),
          if (percent != null) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 5,
                backgroundColor: AppColors.fieldFill,
                valueColor: AlwaysStoppedAnimation(
                  percent >= 90 ? AppColors.statusDeclined : AppColors.primaryBlack,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
