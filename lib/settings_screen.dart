import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiffin/calendar_screen.dart';
import 'package:tiffin/logic/cycle.dart';
import 'package:tiffin/theme.dart';

class SettingsScreen extends StatefulWidget {
  final TiffinState state;

  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _rateController;
  late final TextEditingController _startDayController;
  Timer? _rateDebounce;
  Timer? _startDayDebounce;
  String? _startDayError;

  BillingCycle _previewCycle(int startDay) {
    final now = DateTime.now();
    final containingCycle = BillingCycle.forDate(now, startDay);
    return containingCycle;
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You can sign in again with your email and password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final rate = widget.state.settings.rate;
    _rateController = TextEditingController(
      text: rate == 0
          ? ''
          : (rate % 1 == 0 ? rate.toInt().toString() : rate.toString()),
    );
    _startDayController = TextEditingController(
      text: widget.state.settings.cycleStartDay.toString(),
    );
  }

  @override
  void dispose() {
    _rateDebounce?.cancel();
    _startDayDebounce?.cancel();
    _rateController.dispose();
    _startDayController.dispose();
    super.dispose();
  }

  void _onRateChanged(String value) {
    _rateDebounce?.cancel();
    final trimmed = value.trim();
    final rate = trimmed.isEmpty ? 0.0 : double.tryParse(trimmed);
    if (rate != null && rate >= 0) {
      _rateDebounce = Timer(const Duration(milliseconds: 500), () {
        widget.state.updateRate(
          rate,
          onError: (msg) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        );
      });
    }
  }

  void _onStartDayChanged(String value) {
    _startDayDebounce?.cancel();
    final trimmed = value.trim();
    final day = int.tryParse(trimmed);
    if (day != null && day >= 1 && day <= 28) {
      setState(() => _startDayError = null);
      _startDayDebounce = Timer(const Duration(milliseconds: 500), () {
        widget.state.updateCycleStartDay(
          day,
          onError: (msg) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        );
      });
    } else {
      setState(() => _startDayError = 'Must be between 1 and 28');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'BILLING',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.separator),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Per tiffin',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _rateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                    decoration: const InputDecoration(
                      hintText: '₹0',
                      prefixText: '₹ ',
                      prefixStyle: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    onChanged: _onRateChanged,
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1, color: AppColors.separator),
                  const SizedBox(height: 18),
                  const Text(
                    'Cycle starts on day',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _startDayController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                    decoration: InputDecoration(
                      hintText: '1',
                      errorText: _startDayError,
                      suffixText: 'of each month',
                      suffixStyle: const TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    onChanged: _onStartDayChanged,
                  ),
                  if (_startDayError == null) ...[
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) {
                        final startDay = int.tryParse(
                          _startDayController.text.trim(),
                        );
                        if (startDay == null || startDay < 1 || startDay > 28) {
                          return const SizedBox.shrink();
                        }
                        final cycle = _previewCycle(startDay);
                        final endLabel = DateFormat('d MMMM').format(cycle.end);
                        final startLabel = DateFormat(
                          'd MMMM',
                        ).format(cycle.start);
                        return Text(
                          'Calculates from $startLabel to $endLabel',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondaryText,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Changes are saved automatically',
                style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
              ),
            ),
            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'ACCOUNT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.separator),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
