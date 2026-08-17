import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/invoice_calc.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import 'invoice_sent_screen.dart';

class _CustomLine {
  _CustomLine({required this.description, required this.unitPricePesewas});
  final String description;
  final int unitPricePesewas;
  final int quantity = 1;
}

/// Create & Send Invoice (Section 4.3) — also handles confirming an order
/// request (Section 4.6) when [sourceRequest] is set, pre-filling the
/// customer and letting the merchant adjust quantities before sending.
class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key, this.sourceRequest});

  final OrderRequest? sourceRequest;

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  final _api = ApiClient();
  final _customerController = TextEditingController();
  final _customDescController = TextEditingController();
  final _customPriceController = TextEditingController();

  bool _fromCatalog = true;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  List<Item> _items = [];
  final Map<String, int> _catalogQty = {};
  final List<_CustomLine> _customLines = [];

  Merchant? _merchant;
  int _commissionBps = 0;
  List<DeliveryOption> _deliveryOptions = [];

  String? _deliveryOptionId;
  String? _deliveryLabel;
  String? _deliveryFeeHandling; // bundled | external | null (none chosen)
  int _deliveryFeePesewas = 0;
  final _deliveryAddressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _customerController.text = widget.sourceRequest?.customerContact ?? '';
    _load();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _customDescController.dispose();
    _customPriceController.dispose();
    _deliveryAddressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final merchantId = Session.instance.merchantId!;
    try {
      final results = await Future.wait([
        _api.listItems(merchantId),
        _api.getMerchant(merchantId),
        _api.getCommissionBps(merchantId),
        _api.listDeliveryOptions(merchantId),
      ]);
      setState(() {
        _items = results[0] as List<Item>;
        _merchant = results[1] as Merchant;
        _commissionBps = results[2] as int;
        _deliveryOptions = results[3] as List<DeliveryOption>;
        _loading = false;
      });
      _prefillFromRequest();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _prefillFromRequest() {
    final req = widget.sourceRequest;
    if (req == null) return;
    for (final raw in req.requestedItems) {
      final map = raw as Map<String, dynamic>;
      final itemId = map['item_id'] as String?;
      final qty = (map['quantity'] as num?)?.toInt() ?? 1;
      if (itemId != null && _items.any((i) => i.id == itemId)) {
        setState(() => _catalogQty[itemId] = qty);
      }
    }
  }

  int get _subtotalPesewas {
    var total = 0;
    for (final item in _items) {
      final qty = _catalogQty[item.id] ?? 0;
      total += item.unitPricePesewas * qty;
    }
    for (final line in _customLines) {
      total += line.unitPricePesewas * line.quantity;
    }
    return total;
  }

  InvoiceAmounts get _amounts => computeInvoiceAmounts(
    subtotalPesewas: _subtotalPesewas,
    commissionBps: _commissionBps,
    allocation: _merchant?.serviceChargeAllocation ?? 'customer_only',
    splitBps: _merchant?.serviceChargeSplitBps,
    deliveryFeePesewas: _deliveryFeePesewas,
    deliveryBundled: _deliveryFeeHandling == 'bundled',
  );

  List<Map<String, dynamic>> get _lineItemsPayload {
    final lines = <Map<String, dynamic>>[];
    for (final item in _items) {
      final qty = _catalogQty[item.id] ?? 0;
      if (qty > 0) lines.add({'item_id': item.id, 'quantity': qty});
    }
    for (final line in _customLines) {
      lines.add({
        'description': line.description,
        'unit_price_pesewas': line.unitPricePesewas,
        'quantity': line.quantity,
      });
    }
    return lines;
  }

  Future<void> _openDeliverySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeliverySheet(
        options: _deliveryOptions,
        selectedId: _deliveryOptionId,
        onSelectOption: (opt) {
          setState(() {
            _deliveryOptionId = opt.id;
            _deliveryLabel = opt.contactName ?? opt.type;
            _deliveryFeeHandling = opt.feeHandlingDefault;
            _deliveryFeePesewas = opt.feeHandlingDefault == 'bundled' ? 1500 : 0;
          });
        },
        onSelectNone: () {
          setState(() {
            _deliveryOptionId = null;
            _deliveryLabel = null;
            _deliveryFeeHandling = null;
            _deliveryFeePesewas = 0;
          });
        },
        addressController: _deliveryAddressController,
      ),
    );
    setState(() {});
  }

  Future<void> _submit() async {
    if (_customerController.text.trim().isEmpty) {
      setState(() => _error = 'Customer contact is required');
      return;
    }
    if (_lineItemsPayload.isEmpty) {
      setState(() => _error = 'Add at least one item');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final merchantId = Session.instance.merchantId!;
      final Invoice invoice;
      if (widget.sourceRequest != null) {
        invoice = await _api.confirmOrderRequest(
          merchantId,
          widget.sourceRequest!.id,
          lineItems: _lineItemsPayload,
          deliveryOptionId: _deliveryOptionId,
          deliveryAddress: _deliveryAddressController.text.isEmpty
              ? null
              : _deliveryAddressController.text,
          deliveryFeeHandling: _deliveryFeeHandling,
          deliveryFeePesewas: _deliveryFeeHandling != null ? _deliveryFeePesewas : null,
        );
      } else {
        invoice = await _api.createInvoice(
          merchantId,
          customerContact: _customerController.text.trim(),
          lineItems: _lineItemsPayload,
          deliveryOptionId: _deliveryOptionId,
          deliveryAddress: _deliveryAddressController.text.isEmpty
              ? null
              : _deliveryAddressController.text,
          deliveryFeeHandling: _deliveryFeeHandling,
          deliveryFeePesewas: _deliveryFeeHandling != null ? _deliveryFeePesewas : null,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => InvoiceSentScreen(invoice: invoice)),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _addCustomLine() {
    final desc = _customDescController.text.trim();
    final price = double.tryParse(_customPriceController.text);
    if (desc.isEmpty || price == null) return;
    setState(() {
      _customLines.add(
        _CustomLine(description: desc, unitPricePesewas: (price * 100).round()),
      );
      _customDescController.clear();
      _customPriceController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('New Order')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          Row(
            children: [
              Expanded(
                child: _SegmentChip(
                  label: 'From Catalog',
                  active: _fromCatalog,
                  onTap: () => setState(() => _fromCatalog = true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SegmentChip(
                  label: 'Custom Item',
                  active: !_fromCatalog,
                  onTap: () => setState(() => _fromCatalog = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_fromCatalog) _buildCatalogList() else _buildCustomForm(),
          const SizedBox(height: 16),
          OxpField(label: 'Customer', controller: _customerController, hintText: 'Name · phone'),
          const SizedBox(height: 16),
          OxpCard(
            child: Column(
              children: [
                _SummaryRow('Subtotal', formatPesewas(_subtotalPesewas)),
                _SummaryRow(
                  'Service charge',
                  formatPesewas(_amounts.serviceChargePesewas),
                ),
                if (_deliveryFeeHandling == 'bundled')
                  _SummaryRow('Delivery ($_deliveryLabel)', formatPesewas(_deliveryFeePesewas)),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total to collect',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      formatPesewas(_amounts.totalPesewas),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_merchant?.deliveryEnabled ?? true) ...[
            const SizedBox(height: 16),
            OxpButton(
              label: _deliveryOptionId != null || _deliveryFeeHandling != null
                  ? 'Delivery: ${_deliveryLabel ?? 'arranged separately'}'
                  : '+ Add Delivery',
              variant: OxpButtonVariant.secondary,
              onPressed: _openDeliverySheet,
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.statusDeclined)),
          ],
          const SizedBox(height: 16),
          OxpButton(
            label: 'Send Invoice · ${formatPesewas(_amounts.totalPesewas)}',
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogList() {
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No catalog items yet — add some from the Items tab, or switch to Custom Item.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return OxpCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < _items.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _items[i].name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        Text(
                          '${formatPesewas(_items[i].unitPricePesewas)} each',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  _QtyStepper(
                    value: _catalogQty[_items[i].id] ?? 0,
                    onChanged: (v) => setState(() => _catalogQty[_items[i].id] = v),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_customLines.isNotEmpty)
          OxpCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _customLines.length; i++)
                  ListTile(
                    dense: true,
                    title: Text(_customLines[i].description),
                    subtitle: Text(formatPesewas(_customLines[i].unitPricePesewas)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _customLines.removeAt(i)),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        OxpField(label: 'Description', controller: _customDescController, hintText: 'Gift wrap'),
        const SizedBox(height: 12),
        OxpField(
          label: 'Price (GH₵)',
          controller: _customPriceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        OxpButton(
          label: 'Add line',
          variant: OxpButtonVariant.secondary,
          onPressed: _addCustomLine,
        ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primaryBlack : Colors.transparent,
          border: active ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.primaryBlack,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _stepButton(Icons.remove, () => onChanged((value - 1).clamp(0, 999)), false),
        SizedBox(
          width: 22,
          child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        _stepButton(Icons.add, () => onChanged(value + 1), true),
      ],
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap, bool filled) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryBlack : Colors.transparent,
          border: filled ? null : Border.all(color: AppColors.border),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 15, color: filled ? Colors.white : AppColors.primaryBlack),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class _DeliverySheet extends StatelessWidget {
  const _DeliverySheet({
    required this.options,
    required this.selectedId,
    required this.onSelectOption,
    required this.onSelectNone,
    required this.addressController,
  });

  final List<DeliveryOption> options;
  final String? selectedId;
  final ValueChanged<DeliveryOption> onSelectOption;
  final VoidCallback onSelectNone;
  final TextEditingController addressController;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Delivery to This Order',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFF2F2F2),
                      child: Icon(Icons.close, size: 14, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (options.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No delivery options configured yet — set them up under More → Delivery Settings.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    for (final opt in options)
                      _DeliveryOptionCard(
                        title: opt.contactName ?? (opt.type == 'own_contact' ? 'Own delivery contact' : 'Verified provider'),
                        subtitle: opt.feeHandlingDefault == 'bundled'
                            ? 'Bundled into this invoice'
                            : 'Customer arranges & pays separately',
                        selected: selectedId == opt.id,
                        onTap: () => onSelectOption(opt),
                      ),
                    _DeliveryOptionCard(
                      title: 'Let customer arrange after payment',
                      subtitle: 'No delivery method attached',
                      selected: selectedId == null,
                      onTap: onSelectNone,
                    ),
                    const SizedBox(height: 14),
                    OxpField(
                      label: 'Delivery address (optional)',
                      controller: addressController,
                      hintText: '12 Volta Street, Osu',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OxpButton(label: 'Add to Order', onPressed: () => Navigator.pop(context)),
            ],
          ),
        );
      },
    );
  }
}

class _DeliveryOptionCard extends StatelessWidget {
  const _DeliveryOptionCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OxpCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.border,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
