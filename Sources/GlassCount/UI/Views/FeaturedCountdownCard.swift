import SwiftUI

struct FeaturedCountdownCard: View {
    let event: CountdownEvent
    let detail: CountdownDetail
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        LiveCountdown(target: event.targetDate, showsSeconds: detail.effectiveSeconds) { b, now in
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: event.iconName)
                        .font(.title2)
                        .foregroundStyle(event.colorToken.color)
                        .frame(width: 48, height: 48)
                        .background(event.colorToken.color.opacity(0.18), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.system(.title, design: .rounded, weight: .semibold)).lineLimit(2)
                        Text(event.targetDate.formatted(date: .complete, time: .omitted))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Label("Featured", systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.secondary)
                    Menu {
                        Button("Edit…", systemImage: "pencil", action: onEdit)
                        Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("More actions")
                }

                if b.isExpired {
                    VStack(spacing: 6) {
                        Text("It’s here!").font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("Happened \(CountdownFormatter.compact(b, detail: detail))").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        DigitBlock(value: CountdownFormatter.days(b), label: "DAYS")
                        DigitBlock(value: CountdownFormatter.twoDigits(b.hours), label: "HOURS")
                        if detail.showMinutes { DigitBlock(value: CountdownFormatter.twoDigits(b.minutes), label: "MINUTES") }
                        if detail.effectiveSeconds { DigitBlock(value: CountdownFormatter.twoDigits(b.seconds), label: "SECONDS") }
                    }
                    if let summary = CountdownFormatter.yearsSummary(b) {
                        Text(summary).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }

                if let p = CountdownEngine.progress(start: event.startDate, target: event.targetDate, now: now) {
                    HStack(spacing: 10) {
                        ProgressView(value: p).tint(event.colorToken.color)
                        Text(p.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Progress")
                    .accessibilityValue(p.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(event.title), \(CountdownFormatter.spoken(b)) \(b.isExpired ? "" : "remaining")")
        }
        .padding(28)
        .glassSurface(cornerRadius: 36, tint: event.colorToken.color.opacity(0.10))
        .accessibilityIdentifier("featuredCard")
    }
}
