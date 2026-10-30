import 'package:flutter/material.dart';
import 'package:qayd/application/pos/manage_pos_currency_rates_use_cases.dart';
import 'package:qayd/application/settings/list_currencies_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/components/inputs/qayd_text_field.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';

class PosCurrencyRatesPage extends StatefulWidget {
  const PosCurrencyRatesPage({
    super.key,
    this.preferredCurrency,
    required this.listCurrencies,
    required this.recordRate,
    required this.listHistory,
  });

  final CurrencyCode? preferredCurrency;
  final ListCurrenciesUseCase listCurrencies;
  final RecordPosCurrencyRateUseCase recordRate;
  final ListPosCurrencyRateHistoryUseCase listHistory;

  @override
  State<PosCurrencyRatesPage> createState() => _PosCurrencyRatesPageState();
}

class _PosCurrencyRatesPageState extends State<PosCurrencyRatesPage> {
  final _rateController = TextEditingController();
  final _noteController = TextEditingController();
  List<CurrencyCode> _currencies = const [];
  List<PosCurrencyRate> _history = const [];
  CurrencyCode? _from;
  CurrencyCode? _to;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    final result = await widget.listCurrencies(onlyActive: true);
    if (!mounted) return;
    if (result.isFailure) {
      setState(() {
        _loading = false;
        _error = result.failureOrNull?.messageAr;
      });
      return;
    }
    final currencies = result.valueOrNull ?? const <CurrencyCode>[];
    CurrencyCode? from = currencies.isEmpty ? null : currencies.first;
    final preferred = widget.preferredCurrency;
    if (preferred != null) {
      for (final currency in currencies) {
        if (currency == preferred) from = currency;
      }
    }
    CurrencyCode? to;
    for (final currency in currencies) {
      if (currency != from) {
        to = currency;
        break;
      }
    }
    setState(() {
      _currencies = List.unmodifiable(currencies);
      _from = from;
      _to = to;
      _loading = false;
    });
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    final from = _from;
    final to = _to;
    if (from == null || to == null || from == to) {
      if (mounted) setState(() => _history = const []);
      return;
    }
    final result = await widget.listHistory(
      fromCurrencyCode: from.code,
      toCurrencyCode: to.code,
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      if (result.isFailure) {
        _error = result.failureOrNull?.messageAr ??
            AppStrings.posCurrencyRateHistoryLoadFailed;
      } else {
        _error = null;
        _history = result.valueOrNull ?? const [];
      }
    });
  }

  Future<void> _submit() async {
    final from = _from;
    final to = _to;
    final scaled = _parseRate(_rateController.text);
    if (from == null || to == null || from == to || scaled == null) {
      setState(() => _error = AppStrings.posCurrencyRateInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final now = DateTime.now().toUtc();
    final result = await widget.recordRate(
      fromCurrencyCode: from.code,
      toCurrencyCode: to.code,
      rateScaled: scaled,
      effectiveAt: now,
      recordedAt: now,
      note: _noteController.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isFailure) {
      setState(() => _error = result.failureOrNull?.messageAr);
      return;
    }
    _rateController.clear();
    _noteController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.posCurrencyRateSaved)),
    );
    await _loadHistory();
  }

  void _selectFrom(CurrencyCode? value) {
    if (value == null) return;
    setState(() {
      _from = value;
      if (_to == value) {
        _to = _currencies.firstWhere(
          (currency) => currency != value,
          orElse: () => value,
        );
      }
    });
    _loadHistory();
  }

  void _selectTo(CurrencyCode? value) {
    if (value == null) return;
    setState(() => _to = value);
    _loadHistory();
  }

  @override
  void dispose() {
    _rateController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QaydScaffold(
      appBar: QaydAppBar(title: AppStrings.posCurrencyRatesTitle),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(SpacingTokens.lg),
              children: [
                Text(
                  AppStrings.posCurrencyRatesDescription,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: SpacingTokens.md),
                if (_currencies.length < 2)
                  Text(AppStrings.posProductCurrencyNotFound)
                else ...[
                  Row(
                    children: [
                      Expanded(
                          child: _currencyDropdown(
                        label: AppStrings.posCurrencyRateFrom,
                        value: _from,
                        onChanged: _selectFrom,
                      )),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(
                          child: _currencyDropdown(
                        label: AppStrings.posCurrencyRateTo,
                        value: _to,
                        onChanged: _selectTo,
                      )),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  QaydTextField(
                    controller: _rateController,
                    label: AppStrings.posCurrencyRateValue,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    maxLength: 32,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  QaydTextField(
                    controller: _noteController,
                    label: AppStrings.posCurrencyRateNote,
                    maxLength: 1000,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.currency_exchange_outlined),
                    label: Text(AppStrings.posCurrencyRateSave),
                  ),
                  const SizedBox(height: SpacingTokens.lg),
                  Text(
                    AppStrings.posCurrencyRateHistory,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  if (_history.isEmpty)
                    Text(AppStrings.posCurrencyRateNoHistory)
                  else
                    ..._history.map(_historyCard),
                ],
                if (_error != null) ...[
                  const SizedBox(height: SpacingTokens.md),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _currencyDropdown({
    required String label,
    required CurrencyCode? value,
    required ValueChanged<CurrencyCode?> onChanged,
  }) {
    return DropdownButtonFormField<CurrencyCode>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: _currencies
          .map((currency) => DropdownMenuItem(
                value: currency,
                child: Text('${currency.nameAr} (${currency.code})'),
              ))
          .toList(growable: false),
      onChanged: _saving ? null : onChanged,
    );
  }

  Widget _historyCard(PosCurrencyRate rate) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(Icons.swap_horiz_rounded, color: colorScheme.primary),
        title: Text(
          '1 ${rate.fromCurrency.code} = '
          '${_formatRate(rate.rateScaled)} ${rate.toCurrency.code}',
        ),
        subtitle: Text(
          '${rate.recordedAt.toLocal()}\n'
          '${rate.note?.isNotEmpty == true ? rate.note : ''}',
        ),
        isThreeLine: rate.note?.isNotEmpty == true,
      ),
    );
  }

  static int? _parseRate(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    if (value.isEmpty) return null;
    final parts = value.split('.');
    if (parts.length > 2) return null;
    final whole = parts.first.isEmpty ? '0' : parts.first;
    final fraction = parts.length == 2 ? parts[1] : '';
    if (!RegExp(r'^\d+$').hasMatch(whole) ||
        (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction)) ||
        fraction.length > 8) {
      return null;
    }
    final scaled = BigInt.parse(whole) * BigInt.from(posCurrencyRateScale) +
        BigInt.parse(fraction.padRight(8, '0').isEmpty
            ? '0'
            : fraction.padRight(8, '0'));
    if (scaled <= BigInt.zero || scaled > BigInt.parse('9223372036854775807')) {
      return null;
    }
    return scaled.toInt();
  }

  static String _formatRate(int scaled) {
    final value = BigInt.from(scaled);
    final whole = value ~/ BigInt.from(posCurrencyRateScale);
    final fraction =
        (value % BigInt.from(posCurrencyRateScale)).toString().padLeft(8, '0');
    return '$whole.$fraction';
  }
}
