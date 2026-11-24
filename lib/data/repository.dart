import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiffin/logic/cycle.dart';

class UserSettings {
  final double rate;
  final int cycleStartDay;

  const UserSettings({required this.rate, required this.cycleStartDay});

  factory UserSettings.defaults() =>
      const UserSettings(rate: 0.0, cycleStartDay: 1);

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    final rateVal = json['rate'];
    final double parsedRate;
    if (rateVal is num) {
      parsedRate = rateVal.toDouble();
    } else if (rateVal is String) {
      parsedRate = double.tryParse(rateVal) ?? 0.0;
    } else {
      parsedRate = 0.0;
    }

    final startDayVal = json['cycle_start_day'];
    final int parsedStartDay;
    if (startDayVal is int) {
      parsedStartDay = startDayVal;
    } else if (startDayVal is num) {
      parsedStartDay = startDayVal.toInt();
    } else if (startDayVal is String) {
      parsedStartDay = int.tryParse(startDayVal) ?? 1;
    } else {
      parsedStartDay = 1;
    }

    return UserSettings(
      rate: parsedRate,
      cycleStartDay: parsedStartDay.clamp(1, 28),
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'rate': rate,
    'cycle_start_day': cycleStartDay,
  };
}

abstract class TiffinRepository {
  factory TiffinRepository(SupabaseClient client) = SupabaseTiffinRepository;

  Future<UserSettings> getOrInitSettings(String userId);
  Future<void> saveSettings(String userId, UserSettings settings);
  Future<Map<DateTime, int>> getAbsencesForCycle({
    required String userId,
    required DateTime start,
    required DateTime end,
  });
  Future<void> setAbsence({
    required String userId,
    required DateTime day,
    required int meals,
  });
  Future<void> deleteAbsence({required String userId, required DateTime day});
  Future<bool> isCyclePaid({
    required String userId,
    required DateTime cycleStart,
  });
  Future<void> setCyclePaid({
    required String userId,
    required DateTime cycleStart,
    required bool isPaid,
  });
}

class SupabaseTiffinRepository implements TiffinRepository {
  final SupabaseClient _client;

  SupabaseTiffinRepository(this._client);

  static String formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<UserSettings> getOrInitSettings(String userId) async {
    final res = await _client
        .from('settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (res == null) {
      final defaults = UserSettings.defaults();
      await _client.from('settings').upsert(defaults.toJson(userId));
      return defaults;
    }
    return UserSettings.fromJson(res);
  }

  @override
  Future<void> saveSettings(String userId, UserSettings settings) async {
    await _client.from('settings').upsert(settings.toJson(userId));
  }

  @override
  Future<Map<DateTime, int>> getAbsencesForCycle({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startStr = formatDate(start);
    final endStr = formatDate(end);

    final List<dynamic> response = await _client
        .from('absences')
        .select('day, meals')
        .eq('user_id', userId)
        .gte('day', startStr)
        .lte('day', endStr);

    final map = <DateTime, int>{};
    for (final row in response) {
      final dateStr = row['day'] as String;
      final meals = (row['meals'] as num).toInt();
      final parsed = DateTime.parse(dateStr);
      map[DateTime(parsed.year, parsed.month, parsed.day)] = meals;
    }
    return map;
  }

  @override
  Future<void> setAbsence({
    required String userId,
    required DateTime day,
    required int meals,
  }) async {
    final dayStr = formatDate(day);
    await _client.from('absences').upsert({
      'user_id': userId,
      'day': dayStr,
      'meals': meals,
    });
  }

  @override
  Future<void> deleteAbsence({
    required String userId,
    required DateTime day,
  }) async {
    final dayStr = formatDate(day);
    await _client
        .from('absences')
        .delete()
        .eq('user_id', userId)
        .eq('day', dayStr);
  }

  @override
  Future<bool> isCyclePaid({
    required String userId,
    required DateTime cycleStart,
  }) async {
    final response = await _client
        .from('paid_cycles')
        .select('is_paid')
        .eq('user_id', userId)
        .eq('cycle_start', formatDate(cycleStart))
        .maybeSingle();
    return response?['is_paid'] as bool? ?? false;
  }

  @override
  Future<void> setCyclePaid({
    required String userId,
    required DateTime cycleStart,
    required bool isPaid,
  }) async {
    await _client.from('paid_cycles').upsert({
      'user_id': userId,
      'cycle_start': formatDate(cycleStart),
      'is_paid': isPaid,
      'paid_at': isPaid ? DateTime.now().toUtc().toIso8601String() : null,
    });
  }
}

class InMemoryTiffinRepository implements TiffinRepository {
  UserSettings _settings = const UserSettings(rate: 50.0, cycleStartDay: 10);
  final Map<DateTime, int> _absences = {};
  final Set<DateTime> _paidCycles = {};

  InMemoryTiffinRepository() {
    // Pre-seed sample data matching the specification example:
    // 3 full days (meals = 2) and 2 single meals (meals = 1), rate 50
    final now = DateTime.now();
    final cycle = BillingCycle.forDate(now, _settings.cycleStartDay);
    final days = cycle.days;
    if (days.length >= 10) {
      _absences[days[1]] = 2; // full day missed
      _absences[days[3]] = 2; // full day missed
      _absences[days[5]] = 2; // full day missed
      _absences[days[7]] = 1; // single meal missed
      _absences[days[8]] = 1; // single meal missed
    }
  }

  @override
  Future<UserSettings> getOrInitSettings(String userId) async {
    return _settings;
  }

  @override
  Future<void> saveSettings(String userId, UserSettings settings) async {
    _settings = settings;
  }

  @override
  Future<Map<DateTime, int>> getAbsencesForCycle({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startNorm = BillingCycle.normalize(start);
    final endNorm = BillingCycle.normalize(end);
    final result = <DateTime, int>{};
    for (final entry in _absences.entries) {
      if (!entry.key.isBefore(startNorm) && !entry.key.isAfter(endNorm)) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  @override
  Future<void> setAbsence({
    required String userId,
    required DateTime day,
    required int meals,
  }) async {
    _absences[BillingCycle.normalize(day)] = meals;
  }

  @override
  Future<void> deleteAbsence({
    required String userId,
    required DateTime day,
  }) async {
    _absences.remove(BillingCycle.normalize(day));
  }

  @override
  Future<bool> isCyclePaid({
    required String userId,
    required DateTime cycleStart,
  }) async {
    return _paidCycles.contains(BillingCycle.normalize(cycleStart));
  }

  @override
  Future<void> setCyclePaid({
    required String userId,
    required DateTime cycleStart,
    required bool isPaid,
  }) async {
    final normalized = BillingCycle.normalize(cycleStart);
    if (isPaid) {
      _paidCycles.add(normalized);
    } else {
      _paidCycles.remove(normalized);
    }
  }
}
