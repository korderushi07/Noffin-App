import 'package:flutter_test/flutter_test.dart';
import 'package:tiffin/calendar_screen.dart';
import 'package:tiffin/data/repository.dart';
import 'package:tiffin/logic/cycle.dart';

class FailingAbsencesRepository extends InMemoryTiffinRepository {
  bool failLoads = false;

  @override
  Future<Map<DateTime, int>> getAbsencesForCycle({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) {
    if (failLoads) {
      return Future.error(StateError('Absence load failed'));
    }
    return super.getAbsencesForCycle(userId: userId, start: start, end: end);
  }
}

void main() {
  group('BillingCycle logic tests', () {
    test('date before and after the start day', () {
      const startDay = 10;

      // Date before start day: 5 Nov 2026
      // Should start on 10 Oct 2026 and end on 9 Nov 2026
      final cycleBefore = BillingCycle.forDate(DateTime(2026, 11, 5), startDay);
      expect(cycleBefore.start, equals(DateTime(2026, 10, 10)));
      expect(cycleBefore.end, equals(DateTime(2026, 11, 9)));
      expect(
        cycleBefore.daysCount,
        equals(31),
      ); // Oct has 31 days: 22 in Oct + 9 in Nov = 31

      // Date on start day: 10 Nov 2026
      // Should start on 10 Nov 2026 and end on 9 Dec 2026
      final cycleOn = BillingCycle.forDate(DateTime(2026, 11, 10), startDay);
      expect(cycleOn.start, equals(DateTime(2026, 11, 10)));
      expect(cycleOn.end, equals(DateTime(2026, 12, 9)));
      expect(
        cycleOn.daysCount,
        equals(30),
      ); // Nov has 30 days: 21 in Nov + 9 in Dec = 30

      // Date after start day: 25 Nov 2026
      // Should start on 10 Nov 2026 and end on 9 Dec 2026
      final cycleAfter = BillingCycle.forDate(DateTime(2026, 11, 25), startDay);
      expect(cycleAfter.start, equals(DateTime(2026, 11, 10)));
      expect(cycleAfter.end, equals(DateTime(2026, 12, 9)));
      expect(cycleAfter.daysCount, equals(30));
    });

    test('year rollover (Dec–Jan)', () {
      const startDay = 10;

      // Date in January before start day: 5 Jan 2027
      // Cycle starts on 10 Dec 2026 and ends on 9 Jan 2027
      final cycleJanBefore = BillingCycle.forDate(
        DateTime(2027, 1, 5),
        startDay,
      );
      expect(cycleJanBefore.start, equals(DateTime(2026, 12, 10)));
      expect(cycleJanBefore.end, equals(DateTime(2027, 1, 9)));
      expect(
        cycleJanBefore.daysCount,
        equals(31),
      ); // Dec has 31: 22 in Dec + 9 in Jan = 31

      // Date in December after start day: 20 Dec 2026
      // Cycle starts on 10 Dec 2026 and ends on 9 Jan 2027
      final cycleDecAfter = BillingCycle.forDate(
        DateTime(2026, 12, 20),
        startDay,
      );
      expect(cycleDecAfter.start, equals(DateTime(2026, 12, 10)));
      expect(cycleDecAfter.end, equals(DateTime(2027, 1, 9)));

      // Paging forward from Dec-Jan
      final nextCycle = cycleDecAfter.next();
      expect(nextCycle.start, equals(DateTime(2027, 1, 10)));
      expect(nextCycle.end, equals(DateTime(2027, 2, 9)));

      // Paging backward from Jan-Feb
      final prevCycle = nextCycle.previous();
      expect(prevCycle.start, equals(DateTime(2026, 12, 10)));
      expect(prevCycle.end, equals(DateTime(2027, 1, 9)));
    });

    test('a 28-day February cycle', () {
      // 2025 is a non-leap year (February has 28 days)
      const startDay = 1;
      final cycleFeb = BillingCycle.forDate(DateTime(2025, 2, 14), startDay);
      expect(cycleFeb.start, equals(DateTime(2025, 2, 1)));
      expect(cycleFeb.end, equals(DateTime(2025, 2, 28)));
      expect(cycleFeb.daysCount, equals(28));
      expect(cycleFeb.days.length, equals(28));
      expect(cycleFeb.days.first, equals(DateTime(2025, 2, 1)));
      expect(cycleFeb.days.last, equals(DateTime(2025, 2, 28)));

      // Start day 28 in February non-leap year (2025):
      // Starts 28 Feb 2025 -> ends on 27 Mar 2025
      final cycleFeb28 = BillingCycle.forDate(DateTime(2025, 2, 28), 28);
      expect(cycleFeb28.start, equals(DateTime(2025, 2, 28)));
      expect(cycleFeb28.end, equals(DateTime(2025, 3, 27)));
      expect(cycleFeb28.daysCount, equals(28)); // 1 day in Feb + 27 in Mar = 28
    });

    test('start day 1', () {
      const startDay = 1;

      // November: 30 days
      final cycleNov = BillingCycle.forDate(DateTime(2026, 11, 15), startDay);
      expect(cycleNov.start, equals(DateTime(2026, 11, 1)));
      expect(cycleNov.end, equals(DateTime(2026, 11, 30)));
      expect(cycleNov.daysCount, equals(30));

      // December: 31 days
      final cycleDec = BillingCycle.forDate(DateTime(2026, 12, 1), startDay);
      expect(cycleDec.start, equals(DateTime(2026, 12, 1)));
      expect(cycleDec.end, equals(DateTime(2026, 12, 31)));
      expect(cycleDec.daysCount, equals(31));
    });

    test('bill formula using the specification example', () {
      // Specification:
      // "30 days, 3 full days and 2 single meals missed, rate 50: (60 - 8) * 50 = 2600."
      const daysInCycle = 30;
      final absences = [
        2, 2, 2, // 3 full days (2 meals each)
        1, 1, // 2 single meals (1 meal each)
      ];

      final totalTiffins = calculateTotalTiffins(daysInCycle);
      expect(totalTiffins, equals(60));

      final missed = calculateMissedMeals(absences);
      expect(missed, equals(8));

      final bill = calculateBill(
        daysInCycle: daysInCycle,
        missedMeals: missed,
        ratePerTiffin: 50.0,
      );
      expect(bill, equals(2600.0));
      expect(formatBill(bill), equals('₹2,600'));
    });

    test(
      'current-cycle bill counts meals only through the calculation date',
      () {
        final cycle = BillingCycle.fromYearMonth(
          year: 2026,
          month: 11,
          startDay: 1,
        );

        final amount = calculateCycleBill(
          cycle: cycle,
          absences: {DateTime(2026, 11, 2): 1},
          ratePerTiffin: 50,
          asOf: DateTime(2026, 11, 3),
        );

        expect(amount, equals(250));
      },
    );

    test('saved cycle bills stay separate by cycle start month', () async {
      final repository = InMemoryTiffinRepository();
      await repository.saveCycleBill(
        userId: 'user',
        cycleStart: DateTime(2026, 10, 10),
        amount: 1200,
        ratePerTiffin: 50,
      );
      await repository.saveCycleBill(
        userId: 'user',
        cycleStart: DateTime(2026, 11, 10),
        amount: 950,
        ratePerTiffin: 50,
      );
      await repository.saveCycleBill(
        userId: 'user',
        cycleStart: DateTime(2026, 11, 10),
        amount: 900,
        ratePerTiffin: 50,
      );

      final bills = await repository.getSavedCycleBills('user');

      expect(bills.map((bill) => bill.cycleStart).toList(), [
        DateTime(2026, 11, 10),
        DateTime(2026, 10, 10),
      ]);
      expect(bills.map((bill) => bill.amount).toList(), [900, 1200]);

      await repository.setCyclePaid(
        userId: 'user',
        cycleStart: DateTime(2026, 11, 10),
        isPaid: true,
      );
      final updatedBills = await repository.getSavedCycleBills('user');
      expect(updatedBills.first.isPaid, isTrue);
      expect(updatedBills.last.isPaid, isFalse);
    });

    test(
      'editing a paid completed cycle uses its saved rate and reopens payment',
      () async {
        final repository = InMemoryTiffinRepository();
        final state = TiffinState(repository: repository, userId: 'user');
        await state.init();
        final completedCycle = state.currentCycle.previous();
        await state.goToPreviousCycle();
        await state.setCyclePaid(
          cycleStart: completedCycle.start,
          isPaid: true,
        );
        await state.updateRate(75);

        await state.toggleAbsence(
          completedCycle.start,
          onError: (message) => fail(message),
        );

        final savedBill = state.savedCycleBills.firstWhere(
          (bill) => bill.cycleStart == completedCycle.start,
        );
        expect(
          savedBill.amount,
          equals((completedCycle.daysCount * 2 - 1) * 50),
        );
        expect(savedBill.ratePerTiffin, 50);
        expect(savedBill.isPaid, isFalse);
        state.dispose();
      },
    );

    test('refresh preserves finalized totals after a rate change', () async {
      final repository = InMemoryTiffinRepository();
      final state = TiffinState(repository: repository, userId: 'user');
      await state.init();
      final cycleStart = state.completedCycle.start;
      final before = state.savedCycleBills.firstWhere(
        (bill) => bill.cycleStart == cycleStart,
      );

      await state.updateRate(80);
      await state.refreshCompletedCycleBills();

      final after = state.savedCycleBills.firstWhere(
        (bill) => bill.cycleStart == cycleStart,
      );
      expect(after.amount, before.amount);
      expect(after.ratePerTiffin, 50);
      state.dispose();
    });

    test(
      'refresh reconciles remote absence edits and reopens changed bills',
      () async {
        final repository = InMemoryTiffinRepository();
        final state = TiffinState(repository: repository, userId: 'user');
        await state.init();
        final cycle = state.completedCycle;
        await state.setCyclePaid(cycleStart: cycle.start, isPaid: true);
        final before = state.savedCycleBills.firstWhere(
          (bill) => bill.cycleStart == cycle.start,
        );
        await repository.setAbsence(userId: 'user', day: cycle.start, meals: 2);

        await state.refreshCompletedCycleBills();

        final after = state.savedCycleBills.firstWhere(
          (bill) => bill.cycleStart == cycle.start,
        );
        expect(after.amount, before.amount! - 100);
        expect(after.isPaid, isFalse);
        state.dispose();
      },
    );

    test(
      'failed cycle navigation keeps the previous cycle and absences',
      () async {
        final repository = FailingAbsencesRepository();
        final state = TiffinState(repository: repository, userId: 'user');
        await state.init();
        final cycleBeforeNavigation = state.currentCycle;
        final absencesBeforeNavigation = Map<DateTime, int>.of(state.absences);
        String? errorMessage;
        repository.failLoads = true;

        await state.goToPreviousCycle(
          onError: (message) {
            errorMessage = message;
          },
        );

        expect(state.currentCycle, cycleBeforeNavigation);
        expect(state.absences, absencesBeforeNavigation);
        expect(errorMessage, isNotNull);
        state.dispose();
      },
    );

    test('formatRange produces correct strings', () {
      final cycle = BillingCycle(
        start: DateTime(2026, 11, 10),
        end: DateTime(2026, 12, 9),
        startDay: 10,
      );
      expect(cycle.formatRange(currentYear: 2026), equals('10 Nov – 9 Dec'));
    });

    test('payment due date falls on the start day', () {
      final cycle = BillingCycle(
        start: DateTime(2026, 11, 10),
        end: DateTime(2026, 12, 9),
        startDay: 10,
      );

      expect(cycle.paymentDueDate, equals(DateTime(2026, 12, 10)));
    });
  });
}
