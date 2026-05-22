import Foundation

enum DateRules {
    static func dayBounds(for date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    static func occurrenceDates(
        for template: PlanTemplate,
        from startDate: Date,
        days: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        let start = calendar.startOfDay(for: startDate)
        guard days > 0 else { return [] }

        switch template.cadence {
        case .daily:
            return (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .weekly:
            let selectedWeekdays = Set(template.weekdays.isEmpty ? [calendar.component(.weekday, from: start)] : template.weekdays)
            return (0..<days)
                .compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                .filter { selectedWeekdays.contains(calendar.component(.weekday, from: $0)) }
        case .monthly:
            return monthlyOccurrences(for: template, from: start, days: days, calendar: calendar)
        }
    }

    static func reminderDate(for day: Date, template: PlanTemplate, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = template.defaultReminderHour
        components.minute = template.defaultReminderMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private static func monthlyOccurrences(
        for template: PlanTemplate,
        from start: Date,
        days: Int,
        calendar: Calendar
    ) -> [Date] {
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }
        var cursor = start
        var seenMonths = Set<String>()
        var result: [Date] = []

        while cursor < end {
            let components = calendar.dateComponents([.year, .month], from: cursor)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            if !seenMonths.contains(key), let occurrence = monthlyDate(year: components.year, month: components.month, requestedDay: template.monthDay, calendar: calendar) {
                seenMonths.insert(key)
                if occurrence >= start && occurrence < end {
                    result.append(occurrence)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return result
    }

    private static func monthlyDate(year: Int?, month: Int?, requestedDay: Int, calendar: Calendar) -> Date? {
        guard let year, let month else { return nil }
        let safeDay = max(1, requestedDay)
        let firstOfMonth = DateComponents(calendar: calendar, year: year, month: month, day: 1).date
        guard let firstOfMonth, let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return nil }
        let day = min(safeDay, range.count)
        return DateComponents(calendar: calendar, year: year, month: month, day: day).date
    }
}

