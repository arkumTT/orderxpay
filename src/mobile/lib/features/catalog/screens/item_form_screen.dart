import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({super.key, this.item});

  final Item? item;

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.item?.name);
  late final _priceController = TextEditingController(
    text: widget.item != null
        ? (widget.item!.unitPricePesewas / 100).toStringAsFixed(2)
        : null,
  );
  late final _unitController = TextEditingController(text: widget.item?.qtyUnit);
  late bool _available =
      (widget.item?.availabilityStatus ?? 'in_stock') == 'in_stock';
  final _api = ApiClient();
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.item != null;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final merchantId = Session.instance.merchantId!;
      final pesewas = ((double.tryParse(_priceController.text) ?? 0) * 100)
          .round();
      final status = _available ? 'in_stock' : 'out_of_stock';
      if (_isEdit) {
        await _api.updateItem(
          merchantId,
          widget.item!.id,
          name: _nameController.text,
          unitPricePesewas: pesewas,
          qtyUnit: _unitController.text,
          availabilityStatus: status,
        );
      } else {
        await _api.createItem(
          merchantId,
          name: _nameController.text,
          unitPricePesewas: pesewas,
          qtyUnit: _unitController.text,
          availabilityStatus: status,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archive() async {
    setState(() => _saving = true);
    try {
      await _api.archiveItem(Session.instance.merchantId!, widget.item!.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Item' : 'New Item'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.xl),
          children: [
            Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.textDisabled,
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 28,
                    color: AppColors.textDisabled,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Add photo (coming soon)',
                    style: TextStyle(
                      color: AppColors.textDisabled,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OxpField(
              label: 'Item name',
              controller: _nameController,
              hintText: 'Kelewele Loaded Fries',
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OxpField(
                    label: 'Unit price (GH₵)',
                    controller: _priceController,
                    hintText: '45.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0) return 'Invalid';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OxpField(
                    label: 'Unit',
                    controller: _unitController,
                    hintText: 'Plate',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OxpCard(
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Shown as in-stock to customers',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _available,
                    activeTrackColor: AppColors.statusPaid,
                    onChanged: (v) => setState(() => _available = v),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.statusDeclined),
              ),
            ],
            const SizedBox(height: 20),
            OxpButton(
              label: _isEdit ? 'Save Changes' : 'Save to Catalog',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
            if (_isEdit) ...[
              const SizedBox(height: 12),
              OxpButton(
                label: 'Archive Item',
                variant: OxpButtonVariant.secondary,
                onPressed: _saving ? null : _archive,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
