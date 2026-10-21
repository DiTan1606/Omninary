import SwiftUI

// MARK: - Custom Calendar View with Connected Streak Ribbons
struct CustomMonthCalendar: View {
    let month: Date
    let activityLogs: [String: Bool]
    var frozenDates: Set<String> = []
    var rescuedDates: Set<String> = []
    var isExtra: Bool = false
    let onCompletedDayTapped: (Date) -> Void

    private let calendar = StreakClock.calendar
    private let daysOfWeek = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]

    var body: some View {
        VStack(spacing: 14) {
            // Days of Week Header
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isExtra ? Color.white.opacity(0.65) : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let weeks = generateWeeksInMonth(for: month)

            VStack(spacing: 7) {
                ForEach(0..<weeks.count, id: \.self) { weekIndex in
                    let week = weeks[weekIndex]
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { dayCol in
                            let date = week[dayCol]
                            if let date {
                                calendarCell(date: date)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                            }
                        }
                    }
                }
            }

        }
    }

    @ViewBuilder
    private func calendarCell(date: Date) -> some View {
        let completed = isDayCompleted(date)
        let isFrozen = isDayFrozen(date) && !completed
        let isRescued = rescuedDates.contains(StreakClock.dayKey(date)) && !completed && !isFrozen
        let isToday = calendar.isDateInToday(date)
        let isSelectedMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)

        ZStack {
            // Nền hình vuông cho các ngày học hoặc ngày đóng băng
            if completed {
                completedSquareBackground(isToday: isToday)
            } else if isFrozen {
                frozenSquareBackground(isToday: isToday)
            } else if isRescued {
                rescuedSquareBackground
            } else if isToday {
                todayPendingBackground
            }

            // Chữ số ngày
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 13, weight: completed || isFrozen || isRescued || isToday ? .bold : .medium, design: .rounded))
                .foregroundColor(dayTextColor(completed: completed, isFrozen: isFrozen, isRescued: isRescued, isToday: isToday, isSelectedMonth: isSelectedMonth))

            // Chỉ báo nhỏ cho ngày hôm nay khi đã học
            if isToday && completed {
                Circle()
                    .fill(isExtra ? ExtraAuroraPalette.ice : Color(red: 0.46, green: 0.38, blue: 0.95))
                    .frame(width: 3.5, height: 3.5)
                    .offset(y: 11)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ngày \(StreakClock.dayKey(date))")
        .accessibilityValue(completed ? "Đã học" : (isFrozen ? "Đã đóng băng" : (isRescued ? "Bỏ học, đã dùng Người giữ lửa để cứu" : "Chưa học")))
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture {
            if completed {
                onCompletedDayTapped(date)
            }
        }
    }

    @ViewBuilder
    private func completedSquareBackground(isToday: Bool) -> some View {
        let squareSize: CGFloat = 33
        let cornerRadius: CGFloat = 8.5

        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                isExtra
                    ? Color(red: 0.44, green: 0.36, blue: 0.96).opacity(0.38)
                    : Color(red: 0.08, green: 0.52, blue: 1.00).opacity(0.18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isExtra
                            ? Color(red: 0.62, green: 0.52, blue: 1.00).opacity(isToday ? 0.90 : 0.55)
                            : Color(red: 0.08, green: 0.50, blue: 1.00).opacity(isToday ? 0.85 : 0.38),
                        lineWidth: isToday ? 1.5 : 1
                    )
            )
            .frame(width: squareSize, height: squareSize)
            .shadow(
                color: isExtra
                    ? Color(red: 0.52, green: 0.42, blue: 1.0).opacity(0.30)
                    : Color.blue.opacity(0.12),
                radius: 4,
                y: 1.5
            )
    }

    @ViewBuilder
    private func frozenSquareBackground(isToday: Bool) -> some View {
        let squareSize: CGFloat = 33
        let cornerRadius: CGFloat = 8.5

        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: isExtra
                        ? [Color.cyan.opacity(0.35), Color.blue.opacity(0.20), Color.white.opacity(0.15)]
                        : [Color.cyan.opacity(0.25), Color.blue.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.85), Color.white.opacity(0.9), Color.cyan.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isToday ? 1.5 : 1.1
                    )
            )
            .frame(width: squareSize, height: squareSize)
            .shadow(
                color: Color.cyan.opacity(0.35),
                radius: 4,
                y: 1.5
            )
    }

    private var rescuedSquareBackground: some View {
        RoundedRectangle(cornerRadius: 8.5)
            .fill(Color.red.opacity(isExtra ? 0.28 : 0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 8.5)
                    .stroke(Color.red.opacity(isExtra ? 0.85 : 0.55), lineWidth: 1.1)
            }
            .frame(width: 33, height: 33)
            .shadow(color: Color.red.opacity(0.18), radius: 4, y: 1.5)
    }

    private var todayPendingBackground: some View {
        let squareSize: CGFloat = 33
        let cornerRadius: CGFloat = 8.5

        return RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
            .foregroundStyle(isExtra ? ExtraAuroraPalette.ice : Color(red: 0.08, green: 0.50, blue: 1.00))
            .frame(width: squareSize, height: squareSize)
    }

    private func dayTextColor(completed: Bool, isFrozen: Bool, isRescued: Bool, isToday: Bool, isSelectedMonth: Bool) -> Color {
        if completed {
            return isExtra ? Color.white : Color(red: 0.04, green: 0.42, blue: 0.95)
        }
        if isFrozen {
            return isExtra ? ExtraAuroraPalette.ice : Color.cyan
        }
        if isRescued {
            return isExtra ? Color(red: 1, green: 0.55, blue: 0.55) : Color(red: 0.72, green: 0.08, blue: 0.12)
        }
        if isToday {
            return isExtra ? ExtraAuroraPalette.ice : Color(red: 0.08, green: 0.50, blue: 1.00)
        }
        if isSelectedMonth {
            return isExtra ? Color.white.opacity(0.88) : Color.primary
        }
        return isExtra ? Color.white.opacity(0.25) : Color.secondary.opacity(0.32)
    }

    private func isDayCompleted(_ date: Date?) -> Bool {
        guard let date else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = StreakClock.calendar.timeZone
        let key = formatter.string(from: date)
        return activityLogs[key] == true
    }

    private func isDayFrozen(_ date: Date?) -> Bool {
        guard let date else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = StreakClock.calendar.timeZone
        let key = formatter.string(from: date)
        return frozenDates.contains(key)
    }

    private func generateWeeksInMonth(for month: Date) -> [[Date?]] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: month),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        // Swift weekday: 1=Sun, 2=Mon... -> Monday start offset
        let offset = (firstWeekday + 5) % 7

        var allDays: [Date?] = Array(repeating: nil, count: offset)
        for day in 1...monthRange.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                allDays.append(date)
            }
        }

        while allDays.count % 7 != 0 {
            allDays.append(nil)
        }

        var weeks: [[Date?]] = []
        for i in stride(from: 0, to: allDays.count, by: 7) {
            let chunk = Array(allDays[i..<i + 7])
            weeks.append(chunk)
        }
        return weeks
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = StreakClock.calendar.timeZone
        return formatter.string(from: date)
    }
}
