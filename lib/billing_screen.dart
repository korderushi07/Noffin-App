import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiffin/calendar_screen.dart';
import 'package:tiffin/data/repository.dart';
import 'package:tiffin/logic/cycle.dart';
import 'package:tiffin/theme.dart';

class BillingScreen extends StatefulWidget {
  final TiffinState state;

  const BillingScreen({super.key, required this.state});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  static final _billingCurrency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChange);
    widget.state.refreshCompletedCycleBills(
      onError: (message) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final today = BillingCycle.normalize(DateTime.now());
    final completedBills = widget.state.savedCycleBills.where((bill) {
      final cycle = BillingCycle.fromYearMonth(
        year: bill.cycleStart.year,
        month: bill.cycleStart.month,
        startDay: bill.cycleStart.day,
      );
      return !today.isBefore(cycle.end);
    }).toList();
    final pendingBills = completedBills.where((bill) => !bill.isPaid).toList();
    final pastBills = completedBills.where((bill) => bill.isPaid).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Billing',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: widget.state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : widget.state.billingLoadError != null
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Could not load completed billing cycles.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.state.billingLoadError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'If the error mentions the amount column, run the '
                          'updated supabase/schema.sql in the Supabase SQL Editor.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.secondaryText),
                        ),
                        TextButton(
                          onPressed: widget.state.init,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : completedBills.isEmpty
              ? const Center(
                  child: Text(
                    'No completed billing cycles yet.',
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(top: 12, bottom: 16),
                  children: [
                    if (pendingBills.isNotEmpty) ...[
                      const _BillingSectionLabel('PENDING'),
                      const SizedBox(height: 12),
                      ...pendingBills.map(
                        (bill) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PendingCycleCard(
                            bill: bill,
                            amount: _billingCurrency.format(bill.amount),
                            onMarkPaid: () => widget.state.setCyclePaid(
                              cycleStart: bill.cycleStart,
                              isPaid: true,
                              onError: (message) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(message)),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      if (pastBills.isNotEmpty) const SizedBox(height: 20),
                    ],
                    if (pastBills.isNotEmpty) ...[
                      const _BillingSectionLabel('PAST CYCLES'),
                      const SizedBox(height: 8),
                      ...pastBills.indexed.map((entry) {
                        final index = entry.$1;
                        final bill = entry.$2;
                        return Column(
                          children: [
                            _PastCycleRow(
                              bill: bill,
                              amount: _billingCurrency.format(bill.amount),
                            ),
                            if (index < pastBills.length - 1)
                              const Divider(
                                height: 1,
                                color: AppColors.separator,
                              ),
                          ],
                        );
                      }),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _BillingSectionLabel extends StatelessWidget {
  final String text;

  const _BillingSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: AppColors.tertiaryText,
        ),
      ),
    );
  }
}

class _PendingCycleCard extends StatelessWidget {
  final SavedCycleBill bill;
  final String amount;
  final VoidCallback onMarkPaid;

  const _PendingCycleCard({
    required this.bill,
    required this.amount,
    required this.onMarkPaid,
  });

  @override
  Widget build(BuildContext context) {
    final cycle = BillingCycle.fromYearMonth(
      year: bill.cycleStart.year,
      month: bill.cycleStart.month,
      startDay: bill.cycleStart.day,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateFormat('MMMM yyyy').format(bill.cycleStart)} cycle',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cycle.formatRange(),
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.text, width: 1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Unpaid',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: const TextStyle(
                fontSize: 46,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: onMarkPaid,
            icon: const Icon(Icons.check_circle_rounded, size: 22),
            label: const Text('Mark Paid'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
              minimumSize: const Size.fromHeight(52),
              side: const BorderSide(color: AppColors.text, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PastCycleRow extends StatelessWidget {
  final SavedCycleBill bill;
  final String amount;

  const _PastCycleRow({required this.bill, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                DateFormat('MMMM yyyy').format(bill.cycleStart),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.separator,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: AppColors.secondaryText,
                    ),
                    SizedBox(width: 3),
                    Text(
                      'Paid',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
