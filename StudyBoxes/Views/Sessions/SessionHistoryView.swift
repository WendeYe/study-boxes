import SwiftUI

struct SessionHistoryView: View {
    let box: StudyBox

    @State private var filter: SessionHistoryFilter = .all

    private var sessions: [StudySession] {
        box.sessions.sorted { $0.startedAt > $1.startedAt }
    }

    private var filteredSessions: [StudySession] {
        sessions.filter { filter.includes($0.startedAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Session history")
                    .font(.title2.weight(.semibold))
                Spacer()
                DropdownMenu(
                    "History filter",
                    selection: $filter,
                    options: SessionHistoryFilter.allCases,
                    minWidth: 140
                )
            }

            if sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "clock",
                    description: Text("Start a session to track time, notes, completed tasks, and skipped tasks.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            } else if filteredSessions.isEmpty {
                ContentUnavailableView(
                    "No sessions in this period",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Switch filters or start another session.")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            } else {
                progressCards

                VStack(spacing: 0) {
                    ForEach(filteredSessions.prefix(8)) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                Text("\(session.completedTaskIDs.count) done, \(session.skippedTaskIDs.count) skipped")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(DurationFormatter.minutes(session.durationMinutes))
                                .font(.headline)
                        }
                        .padding(12)

                        if session.id != filteredSessions.prefix(8).last?.id {
                            Divider()
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }
            }
        }
    }

    private var progressCards: some View {
        let progress = StudyProgressService.summary(for: box)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                historyStat("Total", DurationFormatter.minutes(progress.totalMinutes))
                historyStat("This week", DurationFormatter.minutes(progress.weekMinutes))
                historyStat("This month", DurationFormatter.minutes(progress.monthMinutes))
                historyStat("Average", DurationFormatter.minutes(progress.averageSessionMinutes))
            }
            VStack(spacing: 12) {
                historyStat("Total", DurationFormatter.minutes(progress.totalMinutes))
                historyStat("This week", DurationFormatter.minutes(progress.weekMinutes))
                historyStat("This month", DurationFormatter.minutes(progress.monthMinutes))
                historyStat("Average", DurationFormatter.minutes(progress.averageSessionMinutes))
            }
        }
    }

    private func historyStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum SessionHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case thisWeek
    case thisMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .thisWeek: "Week"
        case .thisMonth: "Month"
        }
    }

    func includes(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .thisWeek:
            guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return true }
            return date >= start && date <= now
        case .thisMonth:
            guard let start = calendar.dateInterval(of: .month, for: now)?.start else { return true }
            return date >= start && date <= now
        }
    }
}
