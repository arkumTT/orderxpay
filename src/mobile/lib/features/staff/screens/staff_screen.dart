import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

class _Staff {
  _Staff({required this.id, required this.name, required this.phone, required this.role});
  final String id;
  final String name;
  final String phone;
  final String role;

  factory _Staff.fromJson(Map<String, dynamic> j) => _Staff(
    id: j['id'] as String,
    name: j['name'] as String,
    phone: j['phone'] as String,
    role: j['role'] as String,
  );
}

/// Section 4.9 — Staff can create/send invoices but never see payout
/// settings or full KYC/bank details (enforced server-side by actor type,
/// not by anything client-side).
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final _api = ApiClient();
  late Future<List<_Staff>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Staff>> _load() async {
    final res = await _api.listStaff(Session.instance.merchantId!);
    return res.map(_Staff.fromJson).toList();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _addStaff() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    var obscure = true;
    var saving = false;
    String? error;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add Staff', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                "Set their login email and a starting password, and tell them "
                "both yourself — they'll log in with these on the app's Login screen.",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              OxpField(label: 'Name', controller: nameController),
              const SizedBox(height: 12),
              OxpField(label: 'Phone', controller: phoneController, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              OxpField(
                label: 'Email',
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              OxpField(
                label: 'Password',
                controller: passwordController,
                hintText: 'At least 8 characters',
                obscureText: obscure,
                suffix: IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => setSheetState(() => obscure = !obscure),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(color: AppColors.statusDeclined, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              OxpButton(
                label: 'Save',
                loading: saving,
                onPressed: saving
                    ? null
                    : () async {
                        setSheetState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await _api.post(
                            '/api/v1/app/merchants/${Session.instance.merchantId}/staff',
                            {
                              'name': nameController.text,
                              'phone': phoneController.text,
                              'role': 'staff',
                              'email': emailController.text,
                              'password': passwordController.text,
                            },
                          );
                          if (context.mounted) Navigator.pop(context, true);
                        } on ApiException catch (e) {
                          setSheetState(() {
                            saving = false;
                            error = e.message;
                          });
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        actions: [
          IconButton(icon: const Icon(Icons.add, color: AppColors.accent), onPressed: _addStaff),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<_Staff>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final staff = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                const Text(
                  'Staff can create/send invoices, but cannot change payout '
                  'settings or view full KYC/bank details.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (staff.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No staff added yet.', style: TextStyle(color: AppColors.textSecondary)),
                  )
                else
                  for (final s in staff)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OxpCard(
                        child: Row(
                          children: [
                            AvatarInitials(name: s.name),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  Text(s.phone, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            StatusPill(
                              label: s.role,
                              color: s.role == 'owner' ? AppColors.statusPartial : AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
