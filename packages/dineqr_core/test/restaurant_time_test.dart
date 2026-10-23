import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final original = RestaurantTime.offset.inMinutes;
  tearDown(() => RestaurantTime.configure(original));

  group('DayGreeting.at', () {
    DayGreeting at(int hour, [int minute = 0]) =>
        DayGreeting.at(DateTime.utc(2026, 3, 14, hour, minute));

    test('morning runs from 05:00 to 11:59', () {
      expect(at(5), DayGreeting.morning);
      expect(at(8, 30), DayGreeting.morning);
      expect(at(11, 59), DayGreeting.morning);
    });

    test('afternoon runs from 12:00 to 16:59', () {
      expect(at(12), DayGreeting.afternoon);
      expect(at(16, 59), DayGreeting.afternoon);
    });

    test('evening runs from 17:00 through to 04:59', () {
      expect(at(17), DayGreeting.evening);
      expect(at(23, 59), DayGreeting.evening);
      // The hours either side of midnight stay in the same band.
      expect(at(0), DayGreeting.evening);
      expect(at(4, 59), DayGreeting.evening);
    });
  });

  group('RestaurantTime.greeting', () {
    test('uses restaurant time, not UTC', () {
      RestaurantTime.configure(330); // UTC+5:30
      // 02:00 UTC is 07:30 in the restaurant: morning, not evening.
      final instant = DateTime.utc(2026, 3, 14, 2);
      expect(RestaurantTime.greeting(instant), DayGreeting.morning);

      RestaurantTime.configure(-480); // UTC-8:00
      // The same instant is 18:00 the previous day there.
      expect(RestaurantTime.greeting(instant), DayGreeting.evening);
    });
  });

  group('RestaurantTime.nextGreetingChange', () {
    setUp(() => RestaurantTime.configure(330)); // UTC+5:30

    /// The instant whose restaurant-local wall clock is the given time.
    DateTime wallAt(int hour, int minute) =>
        DateTime.utc(2026, 3, 14, hour, minute).subtract(RestaurantTime.offset);

    test('lands on the next boundary and changes the band', () {
      for (final (from, boundary) in [(6, 12), (13, 17), (3, 5)]) {
        final now = wallAt(from, 0);
        final next = RestaurantTime.nextGreetingChange(now);
        expect(next.isAfter(now), isTrue, reason: 'from $from:00');
        expect(RestaurantTime.wall(next).hour, boundary);
        expect(
          RestaurantTime.greeting(next),
          isNot(RestaurantTime.greeting(now)),
          reason: 'the band must differ either side of $boundary:00',
        );
      }
    });

    test('rolls over midnight after the evening boundary', () {
      final now = wallAt(22, 15);
      final next = RestaurantTime.nextGreetingChange(now);
      final wall = RestaurantTime.wall(next);
      expect(wall.hour, 5);
      expect(wall.day, 15, reason: 'the morning boundary is the next day');
      expect(RestaurantTime.greeting(next), DayGreeting.morning);
    });

    test('is always in the future, including exactly on a boundary', () {
      for (final hour in [0, 5, 12, 17, 23]) {
        final now = wallAt(hour, 0);
        expect(
          RestaurantTime.nextGreetingChange(now).isAfter(now),
          isTrue,
          reason: 'at $hour:00',
        );
      }
    });
  });
}
