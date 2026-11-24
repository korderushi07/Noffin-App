import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiffin/calendar_screen.dart';
import 'package:tiffin/logic/cycle.dart';
import 'package:tiffin/theme.dart';

class BillingScreen extends StatefulWidget {
  final TiffinState state;

  const BillingScreen({super.key, required this.state});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChange);
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
    final cycle = widget.state.completedCycle;
    final dueDate = cycle.paymentDueDate;
    final dueLabel = DateFormat('d MMMM yyyy').format(dueDate);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Billing',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                '${DateFormat('MMMM').format(cycle.start)} payment',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Billing cycle',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryText,
                ),
              ),
        
              const Spacer(),
              Text(
                widget.state.isLoading
                    ? '...'
                    : formatBill(widget.state.completedBill),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 64,
                  height: 1,
                  letterSpacing: -3,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.state.completedCyclePaid
                    ? 'Paid'
                    : 'Amount due',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              
              const Spacer(),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: widget.state.isLoading
                      ? null
                      : () => widget.state.setCompletedCyclePaid(
                          isPaid: !widget.state.completedCyclePaid,
                          onError: (message) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text(message)));
                            }
                          },
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.text,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    widget.state.completedCyclePaid
                        ? 'Mark as unpaid'
                        : 'Mark as paid',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
