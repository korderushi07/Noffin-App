import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiffin/data/repository.dart';
import 'package:tiffin/logic/cycle.dart';
import 'package:tiffin/theme.dart';

class TiffinState extends ChangeNotifier {
  final TiffinRepository repository;
  final String userId;

  UserSettings _settings = UserSettings.defaults();
  late BillingCycle _currentCycle;
  Map<DateTime, int> _absences = {};
  Map<DateTime, int> _completedAbsences = {};
  late BillingCycle _completedCycle;
  bool _completedCyclePaid = false;
  bool _isLoading = true;

  TiffinState({required this.repository, required this.userId}) {
    _currentCycle = BillingCycle.forDate(
      DateTime.now(),
      _settings.cycleStartDay,
    );
    _completedCycle = _currentCycle.previous();
  }

  UserSettings get settings => _settings;
  BillingCycle get currentCycle => _currentCycle;
  Map<DateTime, int> get absences => _absences;
  bool get isLoading => _isLoading;
  BillingCycle get completedCycle => _completedCycle;
  bool get completedCyclePaid => _completedCyclePaid;
  bool get canNavigateToNextCycle {
    final currentCycle = BillingCycle.forDate(
      DateTime.now(),
      _settings.cycleStartDay,
    );
    return _currentCycle.start.isBefore(currentCycle.start);
  }

  bool get isPaymentReminderDue {
    final today = BillingCycle.normalize(DateTime.now());
    return !today.isBefore(completedCycle.paymentDueDate) &&
        !completedCyclePaid;
  }

  int get fullDayMissedCount => _absences.values.where((m) => m == 2).length;
  int get singleTiffinMissedCount =>
      _absences.values.where((m) => m == 1).length;
  int get missedMealsCount => fullDayMissedCount * 2 + singleTiffinMissedCount;

  double get currentBill => calculateBill(
    daysInCycle: _currentCycle.daysCount,
    missedMeals: missedMealsCount,
    ratePerTiffin: _settings.rate,
  );

  double get completedBill {
    final fullDays = _completedAbsences.values.where((m) => m == 2).length;
    final singleMeals = _completedAbsences.values.where((m) => m == 1).length;
    final missedMeals = fullDays * 2 + singleMeals;
    return calculateBill(
      daysInCycle: completedCycle.daysCount,
      missedMeals: missedMeals,
      ratePerTiffin: _settings.rate,
    );
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    try {
      _settings = await repository.getOrInitSettings(userId);
      _currentCycle = BillingCycle.forDate(
        DateTime.now(),
        _settings.cycleStartDay,
      );
      _absences = await repository.getAbsencesForCycle(
        userId: userId,
        start: _currentCycle.start,
        end: _currentCycle.end,
      );
      _completedCycle = _currentCycle.previous();
      await _loadCompletedCycle();
    } catch (_) {
      // Offline fallback: keep default settings
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> goToPreviousCycle({void Function(String)? onError}) async {
    _currentCycle = _currentCycle.previous();
    notifyListeners();
    await _loadAbsencesForCurrentCycle(onError: onError);
  }

  Future<void> goToNextCycle({void Function(String)? onError}) async {
    if (!canNavigateToNextCycle) return;
    _currentCycle = _currentCycle.next();
    notifyListeners();
    await _loadAbsencesForCurrentCycle(onError: onError);
  }

  Future<void> _loadCompletedCycle() async {
    final cycle = completedCycle;
    _completedAbsences = await repository.getAbsencesForCycle(
      userId: userId,
      start: cycle.start,
      end: cycle.end,
    );
    _completedCyclePaid = await repository.isCyclePaid(
      userId: userId,
      cycleStart: cycle.start,
    );
  }

  Future<void> setCompletedCyclePaid({
    required bool isPaid,
    void Function(String)? onError,
  }) async {
    final previousPaid = _completedCyclePaid;
    _completedCyclePaid = isPaid;
    notifyListeners();
    try {
      await repository.setCyclePaid(
        userId: userId,
        cycleStart: completedCycle.start,
        isPaid: isPaid,
      );
    } catch (_) {
      _completedCyclePaid = previousPaid;
      notifyListeners();
      onError?.call('Failed to update payment status.');
    }
  }

  Future<void> _loadAbsencesForCurrentCycle({
    void Function(String)? onError,
  }) async {
    try {
      _absences = await repository.getAbsencesForCycle(
        userId: userId,
        start: _currentCycle.start,
        end: _currentCycle.end,
      );
      notifyListeners();
    } catch (_) {
      onError?.call('Unable to load absences. Please check connection.');
    }
  }

  Future<void> toggleAbsence(
    DateTime date, {
    required void Function(String message) onError,
  }) async {
    final normalized = BillingCycle.normalize(date);
    final currentMeals = _absences[normalized] ?? 0;
    final nextMeals = (currentMeals + 1) % 3;

    // Optimistic update
    if (nextMeals == 0) {
      _absences.remove(normalized);
    } else {
      _absences[normalized] = nextMeals;
    }
    notifyListeners();

    try {
      if (nextMeals == 0) {
        await repository.deleteAbsence(userId: userId, day: normalized);
      } else {
        await repository.setAbsence(
          userId: userId,
          day: normalized,
          meals: nextMeals,
        );
      }
    } catch (_) {
      // Rollback
      if (currentMeals == 0) {
        _absences.remove(normalized);
      } else {
        _absences[normalized] = currentMeals;
      }
      notifyListeners();
      onError('Failed to save absence. Please check connection.');
    }
  }

  Future<void> updateRate(
    double newRate, {
    void Function(String message)? onError,
  }) async {
    _settings = UserSettings(
      rate: newRate,
      cycleStartDay: _settings.cycleStartDay,
    );
    notifyListeners();

    try {
      await repository.saveSettings(userId, _settings);
    } catch (_) {
      onError?.call('Failed to save settings. Please check connection.');
    }
  }

  Future<void> updateCycleStartDay(
    int newStartDay, {
    void Function(String message)? onError,
  }) async {
    if (newStartDay < 1 || newStartDay > 28) return;
    final oldStartDay = _settings.cycleStartDay;
    _settings = UserSettings(rate: _settings.rate, cycleStartDay: newStartDay);
    // Instantly recalculate cycle containing today
    _currentCycle = BillingCycle.forDate(DateTime.now(), newStartDay);
    _completedCycle = _currentCycle.previous();
    _loadCompletedCycle();
    notifyListeners();

    try {
      await repository.saveSettings(userId, _settings);
      await _loadAbsencesForCurrentCycle(onError: onError);
    } catch (_) {
      _settings = UserSettings(
        rate: _settings.rate,
        cycleStartDay: oldStartDay,
      );
      _currentCycle = BillingCycle.forDate(DateTime.now(), oldStartDay);
      notifyListeners();
      onError?.call('Failed to save settings. Please check connection.');
    }
  }
}

class CalendarScreen extends StatefulWidget {
  final TiffinState state;

  const CalendarScreen({super.key, required this.state});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChange);
    widget.state.init();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = widget.state.currentCycle.days;
    final firstDay = days.isNotEmpty ? days.first : today;
    final leadingOffset =
        firstDay.weekday - 1; // 1 (Mon) -> 0, ..., 7 (Sun) -> 6
    final totalCellCount = leadingOffset + days.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top row: ‹  10 Nov – 9 Dec  › pages by billing cycle + settings icon
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous billing cycle',
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.text,
                      size: 30,
                    ),
                    onPressed: () => widget.state.goToPreviousCycle(
                      onError: (msg) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(msg)));
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.state.currentCycle.formatRange(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next billing cycle',
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.secondaryText,
                      size: 30,
                    ),
                    onPressed: widget.state.canNavigateToNextCycle
                        ? () => widget.state.goToNextCycle(
                            onError: (msg) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text(msg)));
                              }
                            },
                          )
                        : null,
                  ),
                ],
              ),
            ),

            // Weekday header (M T W T F S S)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: const [
                  Expanded(
                    child: Center(
                      child: Text(
                        'M',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'T',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'W',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'T',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'F',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'S',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'S',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 7-column calendar grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  childAspectRatio: 0.86,
                ),
                itemCount: totalCellCount,
                itemBuilder: (context, index) {
                  if (index < leadingOffset) {
                    return const SizedBox.shrink();
                  }

                  final date = days[index - leadingOffset];
                  final isToday =
                      date.year == today.year &&
                      date.month == today.month &&
                      date.day == today.day;
                  final meals = widget.state.absences[date] ?? 0;

                  final Color cellColor;
                  final Color textColor;
                  switch (meals) {
                    case 2:
                      cellColor = AppColors.darkFill;
                      textColor = Colors.white;
                      break;
                    case 1:
                      cellColor = AppColors.lightFill;
                      textColor = AppColors.text;
                      break;
                    default:
                      cellColor = AppColors.emptyCell;
                      textColor = AppColors.text;
                  }

                  return Semantics(
                    button: true,
                    label:
                        '${DateFormat('d MMMM').format(date)}, '
                        '${meals == 0
                            ? 'no missed meals'
                            : meals == 1
                            ? 'one missed meal'
                            : 'full day missed'}',
                    child: Material(
                      color: cellColor,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => widget.state.toggleAbsence(
                          date,
                          onError: (msg) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(msg),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: isToday
                                ? Border.all(
                                    color: AppColors.todayBorder,
                                    width: 1.5,
                                  )
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: date.day == 1
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: textColor,
                                      ),
                                    ),
                                    Text(
                                      DateFormat('MMM').format(date),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: meals == 2
                                            ? const Color(0xE6FFFFFF)
                                            : AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
