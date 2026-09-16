import SwiftUI

// MARK: - Custom Calendar View
struct CustomMonthCalendar: View {
    let month: Date
    let activityLogs: [String: Bool]
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
    
    var body: some View {
        VStack(spacing: 15) {
            // Days of Week Header
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            let days = generateDaysInMonth(for: month)
            let columns = Array(repeating: GridItem(.flexible()), count: 7)
            
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(days, id: \.self) { date in
                    if let date = date {
                        calendarCell(for: date)
                    } else {
                        Color.clear.frame(height: 35)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    func calendarCell(for date: Date) -> some View {
        let dateStr = formatDate(date)
        let completed = activityLogs[dateStr] ?? false
        let isToday = calendar.isDateInToday(date)
        let isSelectedMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        
        ZStack {
            if completed {
                Circle()
                    .fill(Color.green)
                    .frame(width: 30, height: 30)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            } else if isToday {
                Circle()
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(width: 30, height: 30)
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
            } else {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12))
                    .foregroundColor(isSelectedMonth ? .primary : .secondary.opacity(0.3))
            }
        }
        .frame(height: 35)
    }
    
    private func generateDaysInMonth(for month: Date) -> [Date?] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: month),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        // Adjust for Monday start (Swift weekday: 1=Sun, 2=Mon...)
        let offset = (firstWeekday + 5) % 7
        
        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in 1...monthRange.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
