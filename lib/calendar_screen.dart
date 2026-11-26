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
  List<SavedCycleBill> _savedCycleBills = [];
  final Set<DateTime> _savingAbsenceCycles = {};
  Future<void> _settingsUpdateQueue = Future<void>.value();
  bool _isNavigatingCycle = false;
  bool _isLoading = true;
  String? _billingLoadError;

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
  bool get isCalendarBusy =>
      _isLoading ||
      _isNavigatingCycle ||
      _savingAbsenceCycles.contains(_currentCycle.start);
  String? get billingLoadError => _billingLoadError;
  BillingCycle get completedCycle => _completedCycle;
  List<SavedCycleBill> get savedCycleBills =>
      List.unmodifiable(_savedCycleBills);
  bool get canNavigateToNextCycle {
    final currentCycle = BillingCycle.forDate(
      DateTime.now(),
      _settings.cycleStartDay,
    );
    return _currentCycle.start.isBefore(currentCycle.start);
  }

  Future<void> _enqueueSettingsUpdate(Future<void> Function() update) {
    final queuedUpdate = _settingsUpdateQueue.then((_) => update());
    _settingsUpdateQueue = queuedUpdate.catchError((Object _) {});
    return queuedUpdate;
  }

  int get fullDayMissedCount => _absences.values.where((m) => m == 2).length;
  int get singleTiffinMissedCount =>
      _absences.values.where((m) => m == 1).length;
  int get missedMealsCount => fullDayMissedCount * 2 + singleTiffinMissedCount;

  double get completedBill => calculateCycleBill(
    cycle: completedCycle,
    absences: _completedAbsences,
    ratePerTiffin: _settings.rate,
    asOf: completedCycle.end,
  );

  Future<void> init() async {
    _isLoading = true;
    _billingLoadError = null;
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
      await _loadSavedCycleBills();
      await _ensureFinalCycleBill(
        cycle: completedCycle,
        absences: _completedAbsences,
      );
      final today = BillingCycle.normalize(DateTime.now());
      if (!today.isBefore(_currentCycle.end)) {
        await _ensureFinalCycleBill(cycle: _currentCycle, absences: _absences);
      }
      await _loadSavedCycleBills();
    } catch (error) {
      _billingLoadError = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> goToPreviousCycle({void Function(String)? onError}) async {
    await _navigateToCycle(_currentCycle.previous(), onError: onError);
  }

  Future<void> goToNextCycle({void Function(String)? onError}) async {
    if (!canNavigateToNextCycle) return;
    await _navigateToCycle(_currentCycle.next(), onError: onError);
  }

  Future<void> _navigateToCycle(
    BillingCycle cycle, {
    void Function(String)? onError,
  }) async {
    if (_isNavigatingCycle) return;
    if (_savingAbsenceCycles.contains(_currentCycle.start)) {
      onError?.call('Wait for the attendance update to finish.');
      return;
    }

    _isNavigatingCycle = true;
    try {
      final absences = await repository.getAbsencesForCycle(
        userId: userId,
        start: cycle.start,
        end: cycle.end,
      );
      _currentCycle = cycle;
      _absences = absences;
      notifyListeners();
    } catch (_) {
      onError?.call('Unable to load absences. Please check connection.');
    } finally {
      _isNavigatingCycle = false;
    }
  }

  Future<void> _loadCompletedCycle() async {
    final cycle = completedCycle;
    _completedAbsences = await repository.getAbsencesForCycle(
      userId: userId,
      start: cycle.start,
      end: cycle.end,
    );
  }

  Future<void> _loadSavedCycleBills() async {
    _savedCycleBills = await repository.getSavedCycleBills(userId);
  }

  Future<void> _saveCycleBill({
    required BillingCycle cycle,
    required Map<DateTime, int> absences,
    required double ratePerTiffin,
  }) async {
    await repository.saveCycleBill(
      userId: userId,
      cycleStart: cycle.start,
      ratePerTiffin: ratePerTiffin,
      amount: calculateCycleBill(
        cycle: cycle,
        absences: absences,
        ratePerTiffin: ratePerTiffin,
        asOf: cycle.end,
      ),
    );
  }

  Future<void> _ensureFinalCycleBill({
    required BillingCycle cycle,
    required Map<DateTime, int> absences,
  }) async {
    SavedCycleBill? existingBill;
    for (final bill in _savedCycleBills) {
      if (bill.cycleStart == cycle.start) {
        existingBill = bill;
        break;
      }
    }

    final rate = existingBill?.ratePerTiffin ?? _settings.rate;
    final amount = calculateCycleBill(
      cycle: cycle,
      absences: absences,
      ratePerTiffin: rate,
      asOf: cycle.end,
    );
    if (existingBill != null &&
        existingBill.amount != null &&
        existingBill.isFinal &&
        (existingBill.amount! - amount).abs() < 0.005) {
      return;
    }

    if (existingBill != null &&
        existingBill.isPaid &&
        existingBill.amount != null &&
        (existingBill.amount! - amount).abs() >= 0.005) {
      await repository.setCyclePaid(
        userId: userId,
        cycleStart: cycle.start,
        isPaid: false,
      );
    }

    await repository.saveCycleBill(
      userId: userId,
      cycleStart: cycle.start,
      amount: amount,
      ratePerTiffin: rate,
    );
  }

  Future<void> refreshCompletedCycleBills({
    void Function(String)? onError,
  }) async {
    if (_isLoading) return;

    try {
      final today = BillingCycle.normalize(DateTime.now());
      final activeCycle = BillingCycle.forDate(today, _settings.cycleStartDay);
      final cyclesToSave = <DateTime, BillingCycle>{
        activeCycle.previous().start: activeCycle.previous(),
      };
      if (!today.isBefore(activeCycle.end)) {
        cyclesToSave[activeCycle.start] = activeCycle;
      }

      await _loadSavedCycleBills();
      for (final bill in _savedCycleBills) {
        final cycle = BillingCycle.fromYearMonth(
          year: bill.cycleStart.year,
          month: bill.cycleStart.month,
          startDay: bill.cycleStart.day,
        );
        if (!today.isBefore(cycle.end)) {
          cyclesToSave[cycle.start] = cycle;
        }
      }

      for (final cycle in cyclesToSave.values) {
        final absences = await repository.getAbsencesForCycle(
          userId: userId,
          start: cycle.start,
          end: cycle.end,
        );
        await _ensureFinalCycleBill(cycle: cycle, absences: absences);
      }
      await _loadSavedCycleBills();
      _billingLoadError = null;
      notifyListeners();
    } catch (error) {
      _billingLoadError = error.toString();
      notifyListeners();
      onError?.call('Unable to refresh completed billing cycles.');
    }
  }

  Future<void> setCyclePaid({
    required DateTime cycleStart,
    required bool isPaid,
    void Function(String)? onError,
  }) async {
    if (_savingAbsenceCycles.contains(cycleStart)) {
      onError?.call('Wait for the attendance update to finish.');
      return;
    }

    final index = _savedCycleBills.indexWhere(
      (bill) =>
          bill.cycleStart == cycleStart && bill.amount != null && bill.isFinal,
    );
    if (index < 0) return;

    final previousBill = _savedCycleBills[index];
    _savedCycleBills[index] = SavedCycleBill(
      cycleStart: previousBill.cycleStart,
      amount: previousBill.amount,
      ratePerTiffin: previousBill.ratePerTiffin,
      isPaid: isPaid,
      isFinal: previousBill.isFinal,
    );
    notifyListeners();
    try {
      await repository.setCyclePaid(
        userId: userId,
        cycleStart: cycleStart,
        isPaid: isPaid,
      );
    } catch (_) {
      _savedCycleBills[index] = previousBill;
      notifyListeners();
      onError?.call('Failed to update payment status.');
    }
  }

  Future<void> toggleAbsence(
    DateTime date, {
    required void Function(String message) onError,
  }) async {
    final normalized = BillingCycle.normalize(date);
    final cycle = _currentCycle;
    if (_isNavigatingCycle) {
      onError('Wait for the billing cycle to finish loading.');
      return;
    }
    if (normalized.isBefore(cycle.start) || normalized.isAfter(cycle.end)) {
      onError('Date is outside the selected billing cycle.');
      return;
    }
    if (!_savingAbsenceCycles.add(cycle.start)) return;

    try {
      await _toggleAbsenceInCycle(normalized, cycle: cycle, onError: onError);
    } finally {
      _savingAbsenceCycles.remove(cycle.start);
    }
  }

  Future<void> _toggleAbsenceInCycle(
    DateTime normalized, {
    required BillingCycle cycle,
    required void Function(String message) onError,
  }) async {
    final currentMeals = _absences[normalized] ?? 0;
    final nextMeals = (currentMeals + 1) % 3;
    SavedCycleBill? existingBill;
    for (final bill in _savedCycleBills) {
      if (bill.cycleStart == cycle.start) {
        existingBill = bill;
        break;
      }
    }

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
      if (currentMeals == 0) {
        _absences.remove(normalized);
      } else {
        _absences[normalized] = currentMeals;
      }
      notifyListeners();
      onError('Failed to save absence. Please check connection.');
      return;
    }

    final today = BillingCycle.normalize(DateTime.now());
    if (!today.isBefore(cycle.end)) {
      try {
        final rate = existingBill?.ratePerTiffin ?? _settings.rate;
        final updatedAmount = calculateCycleBill(
          cycle: cycle,
          absences: _absences,
          ratePerTiffin: rate,
          asOf: cycle.end,
        );
        final savedAmount = existingBill?.amount;
        final amountChanged =
            savedAmount == null || (savedAmount - updatedAmount).abs() >= 0.005;
        if (existingBill?.isPaid == true && amountChanged) {
          await repository.setCyclePaid(
            userId: userId,
            cycleStart: cycle.start,
            isPaid: false,
          );
        }
        await _saveCycleBill(
          cycle: cycle,
          absences: _absences,
          ratePerTiffin: rate,
        );
        await _loadSavedCycleBills();
        notifyListeners();
      } catch (billUpdateError) {
        try {
          await _loadSavedCycleBills();
          notifyListeners();
        } catch (reloadError) {
          onError(
            'Attendance was saved, but updating the bill failed '
            '($billUpdateError) and its latest status could not be loaded '
            '($reloadError).',
          );
          return;
        }
        onError(
          'Attendance was saved, but its bill could not be updated '
          '($billUpdateError). Reopen Billing to retry.',
        );
      }
    }
  }

  Future<void> updateRate(
    double newRate, {
    void Function(String message)? onError,
  }) => _enqueueSettingsUpdate(() async {
    if (!newRate.isFinite || newRate < 0) {
      onError?.call('Rate must be a non-negative number.');
      return;
    }

    final nextSettings = UserSettings(
      rate: newRate,
      cycleStartDay: _settings.cycleStartDay,
    );
    try {
      await repository.saveSettings(userId, nextSettings);
      _settings = nextSettings;
      notifyListeners();
    } catch (_) {
      onError?.call('Failed to save settings. Please check connection.');
    }
  });

  Future<void> updateCycleStartDay(
    int newStartDay, {
    void Function(String message)? onError,
  }) => _enqueueSettingsUpdate(() async {
    if (newStartDay < 1 || newStartDay > 28) return;
    if (newStartDay == _settings.cycleStartDay) return;

    final oldSettings = _settings;
    final nextSettings = UserSettings(
      rate: oldSettings.rate,
      cycleStartDay: newStartDay,
    );
    final nextCycle = BillingCycle.forDate(DateTime.now(), newStartDay);
    final nextCompletedCycle = nextCycle.previous();
    var settingsSaved = false;

    try {
      await repository.saveSettings(userId, nextSettings);
      settingsSaved = true;
      final nextAbsences = await repository.getAbsencesForCycle(
        userId: userId,
        start: nextCycle.start,
        end: nextCycle.end,
      );
      final nextCompletedAbsences = await repository.getAbsencesForCycle(
        userId: userId,
        start: nextCompletedCycle.start,
        end: nextCompletedCycle.end,
      );
      _settings = nextSettings;
      _currentCycle = nextCycle;
      _completedCycle = nextCompletedCycle;
      _absences = nextAbsences;
      _completedAbsences = nextCompletedAbsences;
      notifyListeners();
    } catch (_) {
      if (settingsSaved) {
        try {
          await repository.saveSettings(userId, oldSettings);
        } catch (_) {
          onError?.call(
            'Failed to load the new cycle and restore previous settings. '
            'Reopen the app to reload settings.',
          );
          return;
        }
      }
      onError?.call('Failed to update the billing cycle. Please try again.');
    }
  });
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
                    onPressed: widget.state.isCalendarBusy
                        ? null
                        : () => widget.state.goToPreviousCycle(
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
                    onPressed:
                        !widget.state.isCalendarBusy &&
                            widget.state.canNavigateToNextCycle
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
                        onTap: widget.state.isCalendarBusy
                            ? null
                            : () => widget.state.toggleAbsence(
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
