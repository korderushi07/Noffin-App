import 'package:intl/intl.dart';

/// Pure logic for billing cycles and bill calculation.
class BillingCycle {
  final DateTime start; // Normalized to year, month, day 00:00:00
  final DateTime end; // Inclusive end date
  final int startDay;

  const BillingCycle({
    required this.start,
    required this.end,
    required this.startDay,
  });

  /// Normalize date to 00:00:00 local time
  static DateTime normalize(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// Number of days in this billing cycle (inclusive)
  int get daysCount {
    final startUtc = DateTime.utc(start.year, start.month, start.day);
    final endUtc = DateTime.utc(end.year, end.month, end.day);
    return endUtc.difference(startUtc).inDays + 1;
  }

  /// First day the completed cycle can be paid.
  DateTime get paymentDueDate {
    final endUtc = DateTime.utc(end.year, end.month, end.day);
    final dueUtc = endUtc.add(const Duration(days: 1));
    return DateTime(dueUtc.year, dueUtc.month, dueUtc.day);
  }

  /// List of all dates in this billing cycle (inclusive)
  List<DateTime> get days {
    final list = <DateTime>[];
    final count = daysCount;
    for (int i = 0; i < count; i++) {
      final utc = DateTime.utc(start.year, start.month, start.day + i);
      list.add(DateTime(utc.year, utc.month, utc.day));
    }
    return list;
  }

  /// Previous billing cycle
  BillingCycle previous() {
    final prevYear = start.month == 1 ? start.year - 1 : start.year;
    final prevMonth = start.month == 1 ? 12 : start.month - 1;
    return BillingCycle.fromYearMonth(
      year: prevYear,
      month: prevMonth,
      startDay: startDay,
    );
  }

  /// Next billing cycle
  BillingCycle next() {
    final nextYear = start.month == 12 ? start.year + 1 : start.year;
    final nextMonth = start.month == 12 ? 1 : start.month + 1;
    return BillingCycle.fromYearMonth(
      year: nextYear,
      month: nextMonth,
      startDay: startDay,
    );
  }

  /// Compute cycle containing [date] given [startDay] (1..28).
  ///
  /// Rule: if date.day >= start_day, it starts on start_day of date's month,
  /// otherwise on start_day of the previous month.
  static BillingCycle forDate(DateTime date, int startDay) {
    assert(
      startDay >= 1 && startDay <= 28,
      'cycle_start_day must be between 1 and 28',
    );
    final normalized = normalize(date);
    final int startYear;
    final int startMonth;
    if (normalized.day >= startDay) {
      startYear = normalized.year;
      startMonth = normalized.month;
    } else {
      if (normalized.month == 1) {
        startYear = normalized.year - 1;
        startMonth = 12;
      } else {
        startYear = normalized.year;
        startMonth = normalized.month - 1;
      }
    }
    return BillingCycle.fromYearMonth(
      year: startYear,
      month: startMonth,
      startDay: startDay,
    );
  }

  /// Create a BillingCycle from start year, month, and startDay (1..28).
  /// End date is the day before the same startDay next month.
  static BillingCycle fromYearMonth({
    required int year,
    required int month,
    required int startDay,
  }) {
    assert(
      startDay >= 1 && startDay <= 28,
      'cycle_start_day must be between 1 and 28',
    );
    final start = DateTime(year, month, startDay);
    final nextYear = month == 12 ? year + 1 : year;
    final nextMonth = month == 12 ? 1 : month + 1;
    final nextCycleStartUtc = DateTime.utc(nextYear, nextMonth, startDay);
    final endUtc = nextCycleStartUtc.subtract(const Duration(days: 1));
    final end = DateTime(endUtc.year, endUtc.month, endUtc.day);
    return BillingCycle(start: start, end: end, startDay: startDay);
  }

  /// Formatted cycle title (e.g. "10 Nov – 9 Dec")
  String formatRange({int? currentYear}) {
    final nowYear = currentYear ?? DateTime.now().year;
    if (start.year == end.year) {
      if (start.year == nowYear) {
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';
      } else {
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
      }
    } else {
      return '${DateFormat('d MMM yyyy').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillingCycle &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          startDay == other.startDay;

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ startDay.hashCode;

  @override
  String toString() => 'BillingCycle($start to $end, startDay: $startDay)';
}

/// Calculate total tiffins in a cycle (2 per day: lunch and dinner)
int calculateTotalTiffins(int daysInCycle) => daysInCycle * 2;

/// Calculate total missed meals (sum of meals)
int calculateMissedMeals(Iterable<int> mealsList) {
  return mealsList.fold<int>(0, (sum, meals) => sum + meals);
}

/// Calculate bill to pay:
/// total_tiffins = days_in_cycle * 2
/// missed = sum(meals) over absences in the cycle
/// to_pay = (total_tiffins - missed) * rate_per_tiffin
double calculateBill({
  required int daysInCycle,
  required int missedMeals,
  required double ratePerTiffin,
}) {
  final totalTiffins = calculateTotalTiffins(daysInCycle);
  final toPay = (totalTiffins - missedMeals) * ratePerTiffin;
  return toPay < 0 ? 0.0 : toPay;
}

/// Calculate the bill for meals taken in [cycle] through [asOf].
double calculateCycleBill({
  required BillingCycle cycle,
  required Map<DateTime, int> absences,
  required double ratePerTiffin,
  required DateTime asOf,
}) {
  final cutoff = BillingCycle.normalize(asOf);
  final elapsedDays = cycle.days.where((day) => !day.isAfter(cutoff)).length;
  final missedMeals = absences.entries
      .where(
        (entry) =>
            !entry.key.isBefore(cycle.start) &&
            !entry.key.isAfter(cutoff) &&
            !entry.key.isAfter(cycle.end),
      )
      .fold<int>(0, (total, entry) => total + entry.value);

  return calculateBill(
    daysInCycle: elapsedDays,
    missedMeals: missedMeals,
    ratePerTiffin: ratePerTiffin,
  );
}

/// Formats bill amount for UI (e.g., ₹2,600 or ₹2,600.50)
String formatBill(double amount) {
  final formatter = NumberFormat.currency(
    symbol: '₹',
    decimalDigits: amount % 1 == 0 ? 0 : 2,
  );
  return formatter.format(amount);
}
