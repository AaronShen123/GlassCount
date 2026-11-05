import Testing
import Foundation
@testable import GlassCount

@MainActor
@Suite("Persistence & store")
struct PersistenceTests {
    func makeStore(_ dir: URL) -> AppStore { AppStore(persistence: JSONFilePersistence(directory: dir), saveDelay: .milliseconds(10)) }
    func ev(_ t: String, _ offset: TimeInterval = 3600) -> CountdownEvent { CountdownEvent(title: t, targetDate: Date().addingTimeInterval(offset)) }

    @Test func createUpdateDelete() {
        let s = makeStore(makeTempDir())
        let a = ev("A"); s.add(a)
        #expect(s.events.map(\.title) == ["A"])
        var changed = a; changed.title = "A2"; changed.iconName = "gift"
        s.update(changed)
        #expect(s.event(id: a.id)?.title == "A2" && s.event(id: a.id)?.iconName == "gift")
        s.delete(id: a.id)
        #expect(s.events.isEmpty)
    }

    @Test func eventsAndSettingsSurviveRelaunch() {
        let dir = makeTempDir()
        let s1 = makeStore(dir)
        let a = ev("A"), b = CountdownEvent(title: "B", targetDate: Date(timeIntervalSince1970: 2_000_000_000), startDate: Date(timeIntervalSince1970: 1_900_000_000),
                                           iconName: "gift", colorToken: .pink, backgroundImageFileName: "\(UUID().uuidString).jpg", remindersEnabled: false, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        s1.add(a); s1.add(b, featured: true)
        s1.updateSettings {
            $0.background.imageFileName = "\(UUID().uuidString).jpg"; $0.background.blur = 12; $0.background.dimming = 0.4
            $0.background.opacity = 0.7; $0.background.fit = .fit
            $0.notifications.enabled = true; $0.notifications.offsets = [.sevenDays, .oneHour]
            $0.appearance = .dark; $0.menuBarDisplay = .daysOnly; $0.showMenuBarItem = false
        }
        s1.flushNow()

        let s2 = makeStore(dir)   // "relaunch"
        #expect(s2.events.count == 2)
        #expect(s2.events[1] == b)    // every field, including dates, round-trips (ISO-8601 → whole seconds)
        #expect(s2.settings == s1.settings)
        #expect(s2.settings.featuredEventID == b.id)
        #expect(s2.featuredEvent?.id == b.id)
        #expect(s2.settings.background.imageFileName == s1.settings.background.imageFileName)
        #expect(s2.referencedImageFileNames.count == 2)
    }

    @Test func debouncedSaveReachesDisk() async throws {
        let dir = makeTempDir()
        let s = makeStore(dir)
        s.add(ev("Async"))
        try await Task.sleep(for: .milliseconds(400))
        #expect(try JSONFilePersistence(directory: dir).load()?.events.first?.title == "Async")
    }

    @Test func corruptFileIsQuarantinedNotDeleted() throws {
        let dir = makeTempDir()
        try "{ definitely not json".write(to: dir.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        let s = makeStore(dir)
        #expect(s.events.isEmpty)
        #expect(s.statusMessage != nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("state.corrupt-") })
    }

    @Test func tolerantDecodingFillsDefaults() throws {
        let json = #"{"events":[{"title":"Old","targetDate":"2030-01-01T00:00:00Z"}],"settings":{"background":{"blur":999}}}"#
        let dir = makeTempDir()
        try json.write(to: dir.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        let s = makeStore(dir)
        #expect(s.events.first?.iconName == "calendar" && s.events.first?.remindersEnabled == true)
        #expect(s.settings.background.blur == 40)   // clamped
        #expect(s.settings.showMenuBarItem)
    }

    @Test func duplicateReorderAndFeatured() {
        let s = makeStore(makeTempDir())
        let a = ev("A", 100), b = ev("B", 200), c = ev("C", 300)
        s.add(a); s.add(b); s.add(c)
        #expect(s.featuredEvent?.id == a.id)         // first added becomes featured
        let copy = s.duplicate(id: b.id)
        #expect(s.events.map(\.title) == ["A", "B", "B Copy", "C"] && copy?.id != b.id)
        s.moveEvent(id: c.id, by: -10)
        #expect(s.events.first?.id == c.id)
        s.moveEvent(id: c.id, onto: b.id)
        #expect(s.events.map(\.title) == ["A", "B", "C", "B Copy"])   // moving down lands after the target
        s.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(s.events.last?.id == a.id)
        s.setFeatured(id: c.id)
        #expect(s.featuredEvent?.id == c.id)
        s.delete(id: c.id)                            // deleting the featured event falls back gracefully
        #expect(s.settings.featuredEventID == nil)
        #expect(s.featuredEvent != nil)
    }

    @Test func featuredFallbackPrefersSoonestUpcoming() {
        let s = makeStore(makeTempDir())
        s.add(ev("Past", -1000)); s.add(ev("Far", 90_000)); s.add(ev("Soon", 500))
        s.setFeatured(id: nil)
        #expect(s.featuredEvent?.title == "Soon")
    }

    @Test func onChangeFiresForMutations() {
        let s = makeStore(makeTempDir())
        var count = 0
        s.onChange = { count += 1 }
        let e = ev("A"); s.add(e); s.updateSettings { $0.appearance = .light }; s.delete(id: e.id)
        #expect(count == 3)
    }
}

@MainActor
@Suite("Regression: settings feedback loop")
struct SettingsNoOpTests {
    @Test func unchangedSettingsDoNotNotifyOrSave() {
        let s = AppStore(persistence: JSONFilePersistence(directory: makeTempDir()), saveDelay: .milliseconds(10))
        var fired = 0
        s.onChange = { fired += 1 }
        s.updateSettings { $0.showMenuBarItem = true }   // already true
        #expect(fired == 0)
        s.updateSettings { $0.showMenuBarItem = false }
        #expect(fired == 1)
    }
}

@MainActor
@Suite("Background styles & widget setting")
struct StyleTests {
    @Test func tenBuiltInBackgroundsWithValidPalettes() {
        #expect(DefaultBackgroundStyle.allCases.count == 10)
        for s in DefaultBackgroundStyle.allCases {
            for set in [s.palette.light, s.palette.dark] {
                #expect(set.count == 4 && set.allSatisfy { $0.count == 3 && $0.allSatisfy { (0...1).contains($0) } })
            }
        }
    }
    @Test func styleAndWidgetSettingPersist() {
        let dir = makeTempDir()
        let s1 = AppStore(persistence: JSONFilePersistence(directory: dir), saveDelay: .milliseconds(10))
        s1.updateSettings { $0.background.defaultStyle = .ocean; $0.showDesktopWidget = true }
        s1.flushNow()
        let s2 = AppStore(persistence: JSONFilePersistence(directory: dir), saveDelay: .milliseconds(10))
        #expect(s2.settings.background.defaultStyle == .ocean && s2.settings.showDesktopWidget)
    }
}

@MainActor
@Suite("Card resizing")
struct CardSizeTests {
    @Test func sizesSnapClampPersistAndReset() {
        let dir = makeTempDir()
        let s = AppStore(persistence: JSONFilePersistence(directory: dir), saveDelay: .milliseconds(10))
        let e = CountdownEvent(title: "A", targetDate: Date().addingTimeInterval(1000)); s.add(e)
        s.setCardSize(id: e.id, width: 333, height: 99_999)
        #expect(s.event(id: e.id)?.cardWidth == 330 && s.event(id: e.id)?.cardHeight == 320)   // snapped / clamped
        s.setCardSize(id: e.id, width: 1, height: 1)
        #expect(s.event(id: e.id)?.cardWidth == 200 && s.event(id: e.id)?.cardHeight == 120)
        s.setCardSize(id: e.id, width: 400, height: 240); s.flushNow()
        let s2 = AppStore(persistence: JSONFilePersistence(directory: dir), saveDelay: .milliseconds(10))
        #expect(s2.event(id: e.id)?.cardWidth == 400 && s2.event(id: e.id)?.cardHeight == 240)
        s2.setCardSize(id: e.id, width: nil, height: nil)
        #expect(s2.event(id: e.id)?.cardWidth == nil)
    }
}

@Suite("Widget size & placement")
struct WidgetSizeTests {
    @Test func presetsAndNearest() {
        #expect(WidgetPreset.nearest(to: CGSize(width: 150, height: 170)) == .small)
        #expect(WidgetPreset.nearest(to: CGSize(width: 300, height: 190)) == .medium)
        #expect(WidgetPreset.nearest(to: CGSize(width: 500, height: 500)) == .large)
        #expect(WidgetPreset.nearest(to: CGSize(width: 1, height: 1)) == .small)
    }
    @Test func freeSizeIsClampedAndSnapped() {
        #expect(WidgetSize.clampWidth(10) == 160 && WidgetSize.clampWidth(9999) == 420 && WidgetSize.clampWidth(233) == 230)
        #expect(WidgetSize.clampHeight(10) == 110 && WidgetSize.clampHeight(9999) == 300)
        for p in WidgetPreset.allCases {
            #expect(WidgetSize.widthRange.contains(p.size.width) && WidgetSize.heightRange.contains(p.size.height))
        }
    }
    @Test func settingsRoundTripAndOldFiles() throws {
        var s = AppSettings(); s.widgetWidth = 300; s.widgetHeight = 200; s.widgetOrigin = [120, 340]
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.widgetWidth == 300 && back.widgetHeight == 200 && back.widgetOrigin == [120, 340])
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.widgetWidth == 170 && old.widgetHeight == 160 && old.widgetOrigin == nil)
    }
    @Test func placementSnapsToGridAndStaysOnScreen() {
        let vis = CGRect(x: 0, y: 80, width: 1440, height: 800)           // e.g. Dock at bottom, menu bar excluded
        let area = vis.insetBy(dx: WidgetPlacement.margin, dy: WidgetPlacement.margin)
        let snapped = WidgetPlacement.snap(card: CGRect(x: 205, y: 507, width: 160, height: 160), in: vis)
        #expect((snapped.minX - area.minX).truncatingRemainder(dividingBy: 20) == 0)
        #expect((area.maxY - snapped.maxY).truncatingRemainder(dividingBy: 20) == 0)
        // Dragged under the Dock / off the right edge / above the menu bar → pushed back inside.
        let low = WidgetPlacement.snap(card: CGRect(x: 100, y: -50, width: 160, height: 160), in: vis)
        #expect(low.minY >= area.minY)
        let right = WidgetPlacement.snap(card: CGRect(x: 1500, y: 300, width: 340, height: 160), in: vis)
        #expect(right.maxX <= area.maxX)
        let high = WidgetPlacement.snap(card: CGRect(x: 100, y: 2000, width: 160, height: 160), in: vis)
        #expect(high.maxY <= area.maxY)
        // Oversized card is shrunk to fit rather than overflowing.
        #expect(WidgetPlacement.snap(card: CGRect(x: 0, y: 0, width: 5000, height: 5000), in: vis).width <= area.width)
    }
    @Test func placementAvoidsOtherWidgets() {
        let vis = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let area = vis.insetBy(dx: WidgetPlacement.margin, dy: WidgetPlacement.margin)
        let other = CGRect(x: 600, y: 400, width: 340, height: 160)
        let want = CGRect(x: 620, y: 420, width: 160, height: 160)          // overlaps `other`
        let r = WidgetPlacement.resolve(card: want, in: vis, avoiding: [other])
        #expect(!r.intersects(other))
        #expect(area.contains(r))
        #expect(hypot(r.minX - want.minX, r.minY - want.minY) < 300)         // moved to a nearby free spot
        // No obstacle → same as plain snap. Fully blocked → keeps the snapped spot instead of crashing.
        #expect(WidgetPlacement.resolve(card: want, in: vis, avoiding: []) == WidgetPlacement.snap(card: want, in: vis))
        #expect(WidgetPlacement.resolve(card: want, in: vis, avoiding: [vis]) == WidgetPlacement.snap(card: want, in: vis))
    }
}
