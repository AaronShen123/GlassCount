import SwiftUI

struct EventEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: EditorTarget

    @State private var draft = EventDraft()
    @State private var imageSessionID = UUID()
    @State private var loaded = false
    @State private var showImporter = false

    private var issues: [EventValidationIssue] { draft.validate() }
    private var editingID: UUID? { if case .edit(let id) = target { return id } else { return nil } }

    var body: some View {
        VStack(spacing: 0) {
            Text(editingID == nil ? "New Countdown" : "Edit Countdown")
                .font(.title2.weight(.semibold)).padding(.top, 22).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Name") {
                        TextField("e.g. Summer Trip", text: $draft.title)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("eventTitleField")
                    }
                    field("Date") {
                        DatePicker("Target", selection: $draft.targetDate, displayedComponents: [.date])
                            .labelsHidden()
                            .accessibilityIdentifier("eventTargetPicker")
                        if draft.targetDate <= Date() {
                            Text("This date is in the past — the countdown will show as ended.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    field("Progress") {
                        Toggle("Track progress from a start date", isOn: $draft.hasStartDate)
                        if draft.hasStartDate {
                            DatePicker("Start", selection: $draft.startDate, displayedComponents: [.date]).labelsHidden()
                        }
                    }
                    field("Icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
                            ForEach(EventIcons.all, id: \.self) { icon in
                                Button { draft.iconName = icon } label: {
                                    Image(systemName: icon).frame(width: 32, height: 32)
                                        .background(draft.iconName == icon ? draft.colorToken.color.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(draft.iconName == icon ? draft.colorToken.color : .clear, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain).accessibilityLabel(icon)
                            }
                        }
                    }
                    field("Colour") {
                        HStack(spacing: 10) {
                            ForEach(EventColor.allCases, id: \.self) { c in
                                Button { draft.colorToken = c } label: {
                                    Circle().fill(c.color).frame(width: 24, height: 24)
                                        .overlay(Circle().stroke(.primary.opacity(draft.colorToken == c ? 0.9 : 0), lineWidth: 2).padding(-3))
                                }
                                .buttonStyle(.plain).accessibilityLabel(c.title)
                            }
                        }
                    }
                    field("Card background") {
                        HStack {
                            if let name = draft.backgroundImageFileName {
                                CachedImage(fileName: name, maxPixel: 200) { img in
                                    Group {
                                        if let img { Image(nsImage: img).resizable().scaledToFill() } else { Color.gray.opacity(0.3) }
                                    }
                                    .frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Button("Replace…") { showImporter = true }
                                Button("Remove", role: .destructive) { draft.backgroundImageFileName = nil }
                            } else {
                                Button("Choose Image…") { showImporter = true }
                            }
                        }
                    }
                    field("Reminders") {
                        Toggle("Remind me about this event", isOn: $draft.remindersEnabled)
                        Text("Reminder times are set in Settings › Notifications.").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Show as the featured countdown", isOn: $draft.makeFeatured)
                    ForEach(issues, id: \.self) { Text($0.message).font(.callout).foregroundStyle(.red) }
                }
                .padding(.horizontal, 28).padding(.vertical, 12)
            }
            Divider()
            HStack {
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(editingID == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!issues.isEmpty)
                    .accessibilityIdentifier("saveEvent")
            }
            .padding(16)
        }
        .frame(width: 480, height: 640)
        .onAppear { model.beginImageSession(imageSessionID); load() }
        .onDisappear { model.endImageSession(imageSessionID) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: BackgroundImageStore.allowedTypes) { result in
            guard case .success(let url) = result else { return }
            Task {
                if let name = await model.importImage(url, for: imageSessionID) {
                    draft.backgroundImageFileName = name
                }
            }
        }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = editingID, let e = model.store.event(id: id) {
            draft = EventDraft(event: e, isFeatured: model.store.featuredEvent?.id == id)
        }
    }

    private func save() {
        let store = model.store
        if let id = editingID, let existing = store.event(id: id) {
            guard var updated = draft.makeEvent(id: id, createdAt: existing.createdAt) else { return }
            updated.createdAt = existing.createdAt
            store.update(updated, featured: draft.makeFeatured)
        } else if let event = draft.makeEvent() {
            store.add(event, featured: draft.makeFeatured)
        }
        model.endImageSession(imageSessionID)   // saved references now protect the chosen image
        dismiss()
    }

    private func cancel() {
        model.endImageSession(imageSessionID)
        dismiss()
    }
}
