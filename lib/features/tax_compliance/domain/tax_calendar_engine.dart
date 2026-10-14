/// A statutory tax payment deadline event.
class TaxCalendarEvent {
  final String id;
  final String title;
  final String jurisdiction;
  final DateTime dueDate;
  final String description;
  final double estimatedPaymentAmount;
  final int daysRemaining;
  final bool isOverdue;

  const TaxCalendarEvent({
    required this.id,
    required this.title,
    required this.jurisdiction,
    required this.dueDate,
    required this.description,
    required this.estimatedPaymentAmount,
    required this.daysRemaining,
    required this.isOverdue,
  });

  /// Generates standard iCalendar (.ics) format string for export to Google/Apple Calendar.
  String toIcsFormat() {
    final startStr = _formatIcsDate(dueDate);
    final endStr = _formatIcsDate(dueDate.add(const Duration(hours: 1)));
    final nowStr = _formatIcsDate(DateTime.now().toUtc());

    return '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//tAIdy//Freelance Tax Calendar//EN
BEGIN:VEVENT
UID:$id@taidy.app
DTSTAMP:${nowStr}Z
DTSTART;VALUE=DATE:$startStr
DTEND;VALUE=DATE:$endStr
SUMMARY:$title (Estimated \$${estimatedPaymentAmount.toStringAsFixed(2)})
DESCRIPTION:$description - Estimated amount: \$${estimatedPaymentAmount.toStringAsFixed(2)}
STATUS:CONFIRMED
BEGIN:VALARM
TRIGGER:-P7D
ACTION:DISPLAY
DESCRIPTION:Tax payment due in 7 days
END:VALARM
END:VEVENT
END:VCALENDAR''';
  }

  static String _formatIcsDate(DateTime d) {
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }
}

/// Engine for generating quarterly estimated tax calendars and .ics exports across tax jurisdictions.
class TaxCalendarEngine {
  /// Generates the list of statutory estimated tax deadlines for a given [year] and [jurisdiction].
  static List<TaxCalendarEvent> generateFiscalCalendar({
    required int year,
    String jurisdiction = 'USA',
    double annualLockedTaxReserve = 0.0,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final quarterlyAmount = annualLockedTaxReserve > 0 ? (annualLockedTaxReserve / 4.0) : 0.0;

    final List<TaxCalendarEvent> events = [];

    if (jurisdiction == 'USA') {
      final deadlines = [
        (q: 1, date: DateTime(year, 4, 15), desc: 'Q1 Estimated Tax Payment (Jan 1 - Mar 31 income)'),
        (q: 2, date: DateTime(year, 6, 15), desc: 'Q2 Estimated Tax Payment (Apr 1 - May 31 income)'),
        (q: 3, date: DateTime(year, 9, 15), desc: 'Q3 Estimated Tax Payment (Jun 1 - Aug 31 income)'),
        (q: 4, date: DateTime(year + 1, 1, 15), desc: 'Q4 Estimated Tax Payment (Sep 1 - Dec 31 income)'),
      ];

      for (final d in deadlines) {
        final days = d.date.difference(now).inDays;
        events.add(TaxCalendarEvent(
          id: 'us-q${d.q}-$year',
          title: 'IRS Q${d.q} Estimated Tax Due',
          jurisdiction: 'USA',
          dueDate: d.date,
          description: d.desc,
          estimatedPaymentAmount: quarterlyAmount,
          daysRemaining: days,
          isOverdue: days < 0,
        ));
      }
    } else if (jurisdiction == 'GBR') {
      final deadlines = [
        (id: 'uk-jan', title: 'HMRC Self Assessment Balancing Payment', date: DateTime(year + 1, 1, 31), desc: 'Balancing payment & 1st Payment on Account'),
        (id: 'uk-jul', title: 'HMRC 2nd Payment on Account', date: DateTime(year, 7, 31), desc: 'Second payment on account for self-employed'),
      ];

      for (final d in deadlines) {
        final days = d.date.difference(now).inDays;
        events.add(TaxCalendarEvent(
          id: '${d.id}-$year',
          title: d.title,
          jurisdiction: 'GBR',
          dueDate: d.date,
          description: d.desc,
          estimatedPaymentAmount: annualLockedTaxReserve / 2.0,
          daysRemaining: days,
          isOverdue: days < 0,
        ));
      }
    } else {
      // General EU / Global default quarterly schedule
      for (int q = 1; q <= 4; q++) {
        final date = q == 4 ? DateTime(year + 1, 1, 15) : DateTime(year, q * 3 + 1, 15);
        final days = date.difference(now).inDays;
        events.add(TaxCalendarEvent(
          id: 'global-q$q-$year',
          title: 'Q$q Estimated Statutory Tax Due',
          jurisdiction: jurisdiction,
          dueDate: date,
          description: 'Quarterly estimated tax installment for $jurisdiction regime',
          estimatedPaymentAmount: quarterlyAmount,
          daysRemaining: days,
          isOverdue: days < 0,
        ));
      }
    }

    // Sort by due date
    events.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return events;
  }
}

