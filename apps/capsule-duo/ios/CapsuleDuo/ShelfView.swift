import SwiftUI
import UIKit
import UserNotifications

extension Capsule {
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Message from \(createdAt.formatted(date: .abbreviated, time: .omitted))" : trimmed
    }

    /// How far along the wait is, for the orbit ring. Nil for "Open when…" and opened capsules.
    func progress(at now: Date) -> Double? {
        guard !isOpened, let date = unlockDate else { return nil }
        let total = date.timeIntervalSince(createdAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(createdAt) / total))
    }

    func statusLine(at now: Date) -> String {
        if let openedAt {
            return "Opened \(openedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        switch lock {
        case .openWhen(let text):
            return "Open when \(text)"
        case .date(let date):
            if date <= now { return "Ready to open · sealed \(CapsuleFormat.ago(createdAt, from: now))" }
            return "\(CapsuleFormat.countdown(to: date, from: now)) · \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

struct ShelfView: View {
    @EnvironmentObject private var store: CapsuleStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var composing = false
    @State private var composeFocus = "Record"
    @State private var destination = "Home"
    @AppStorage("dearTomorrowName") private var displayName = ""
    @State private var panel: String?
    @State private var selected: UUID?
    @State private var startedDemo = false
    @State private var vaultFilter = "All"

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Group {
                    if destination == "Home" {
                        DuoSplit { primary(now:context.date) } secondary: { secondary(now:context.date) }
                    } else {
                        ScrollView { collection(now:context.date).padding(16).frame(maxWidth:640).frame(maxWidth:.infinity) }
                    }
                }
            }
            .background(CosmicBackground())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge:.bottom,spacing:0) { navigationBar }
            .navigationDestination(item:$selected) { CapsuleView(capsuleID:$0) }
        }
        .tint(Palette.gold)
        .fullScreenCover(isPresented:$composing) { ComposeView(initialFocus:composeFocus) }
        .sheet(isPresented:Binding(get:{panel != nil},set:{if !$0 {panel=nil}})) {
            PremiumAccountView(section:panel ?? "Settings")
        }
        .task { startDemoIfAsked() }
    }

    private func primary(now:Date) -> some View {
        VStack(spacing:12) {
            header
            greeting(now:now)
            actionCards
        }
    }

    private var header: some View {
        ZStack(alignment:.top) {
            VStack(spacing:0) {
                EnvelopeEmblem(size:110)
                BrandWordmark(size:39).padding(.top,-14)
                Text("MESSAGES TO YOUR FUTURE SELF")
                    .font(.system(size:9,weight:.medium)).tracking(2.1)
                    .foregroundStyle(Palette.ink).padding(.top,6)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth:.infinity)
            HStack(spacing:8) {
                headerButton("Profile")
                Spacer(minLength:140)
                headerButton("Notifications")
                headerButton("Settings")
            }.padding(.top,28)
        }
        .accessibilityElement(children:.contain)
    }

    private func headerButton(_ title:String) -> some View {
        Button {panel=title} label: {
            PremiumIcon(name:title,size:24)
                .frame(width:38,height:38)
                .background(Circle().fill(Palette.card.opacity(0.75)))
                .overlay(Circle().stroke(Palette.lavender.opacity(0.5),lineWidth:1))
                .frame(minWidth:44,minHeight:44)
        }.buttonStyle(.plain).accessibilityLabel(title)
    }

    private func greeting(now:Date) -> some View {
        VStack(alignment:.leading,spacing:6) {
            let hour=Calendar.current.component(.hour,from:now)
            let salutation=hour < 12 ? "Good Morning" : hour < 18 ? "Good Afternoon" : "Good Evening"
            (Text(salutation + (displayName.isEmpty ? "" : ", ")).foregroundColor(Palette.ink)
             + Text(displayName).foregroundColor(Palette.gold))
                .font(.custom("Baskerville-SemiBold",size:24,relativeTo:.title2))
                .fixedSize(horizontal:false,vertical:true)
            Text("Leave a thought, a plan, a promise or a reminder for the person you’ll become.")
                .font(.system(size:13)).foregroundStyle(Palette.muted)
                .lineSpacing(2).frame(maxWidth:.infinity,alignment:.leading)
        }
        .padding(.horizontal,6).padding(.top,8).padding(.bottom,10)
        .frame(maxWidth:.infinity,alignment:.leading)
        .background {
            GeometryReader {g in
                Image("MountainSunrise").resizable().scaledToFill()
                    .frame(width:g.size.width+32,height:g.size.height+40).clipped()
                    .mask(LinearGradient(colors:[.clear,.white,.white,.clear],startPoint:.top,endPoint:.bottom))
                    .offset(x:-16,y:-20)
            }.accessibilityHidden(true)
        }
    }

    private var actionCards: some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:9),count:typeSize.isAccessibilitySize ? 2 : 4),spacing:10) {
            actionTile("Record","Voice Message","Record",highlighted:true) {openComposer("Record")}
            actionTile("Write","A Note","Write") {openComposer("Write")}
            actionTile("Seal & Send","Choose a Date","Scheduled") {openComposer("Schedule")}
            actionTile("My Vault","All Capsules","Vault") {destination="Vault"}
        }
    }

    private func actionTile(_ title:String,_ subtitle:String,_ icon:String,highlighted:Bool=false,action:@escaping ()->Void) -> some View {
        Button(action:action) {
            VStack(spacing:7) {
                PremiumIcon(name:icon,size:29,gold:icon == "Write" || icon == "Scheduled",glow:highlighted)
                Text(title).font(.system(size:12,weight:.medium)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(subtitle).font(.system(size:10)).foregroundStyle(Palette.muted)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal,3).frame(maxWidth:.infinity).frame(minHeight:92)
            .background(GlassSurface(radius:17,illuminated:highlighted))
        }.buttonStyle(.plain).accessibilityLabel("\(title), \(subtitle)")
    }

    private func secondary(now:Date) -> some View {
        let waiting=store.capsules.filter{!$0.isOpened && !$0.canOpen(at:now)}.sorted{($0.unlockDate ?? .distantFuture)<($1.unlockDate ?? .distantFuture)}
        let ready=store.capsules.filter{!$0.isOpened && $0.unlockDate != nil && $0.canOpen(at:now)}
        let openWhen=store.capsules.filter{!$0.isOpened && $0.openWhenText != nil}
        let delivered=store.capsules.filter{$0.isOpened || ($0.unlockDate != nil && $0.canOpen(at:now))}.count
        return VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                SwiftUI.Capsule().fill(Palette.glow).frame(width:3,height:14)
                Text("Upcoming Deliveries").font(.system(size:16,weight:.semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength:0)
                Button("See All ›"){destination="Scheduled"}
                    .font(.system(size:12,weight:.medium)).foregroundStyle(Palette.gold).frame(minHeight:44)
            }
            if let next=waiting.first {
                capsuleButton(next,now:now)
            } else {
                HStack(spacing:12) {
                    PremiumIcon(name:"Envelope",size:28,glow:true).padding(9).background(Circle().fill(Palette.nebula.opacity(0.4)))
                    VStack(alignment:.leading,spacing:4) {
                        Text("Your future is waiting").font(.system(size:14,weight:.semibold)).foregroundStyle(Palette.ink)
                        Text("Seal a message to see its delivery here.").font(.system(size:11)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength:0)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(GlassSurface())
            }
            HStack(spacing:8) {
                statistic("Envelope","Total Capsules",store.capsules.count)
                statistic("Lock","Sealed (Waiting)",waiting.count+openWhen.count)
                statistic("Delivered","Delivered",delivered)
            }
            QuoteBanner()
            if !ready.isEmpty {
                SectionTitle(text:"Ready to open")
                rows(ready,now:now)
            }
            if !openWhen.isEmpty {
                SectionTitle(text:"Open when…")
                rows(openWhen,now:now)
            }
        }
    }

    private func statistic(_ icon:String,_ label:String,_ count:Int) -> some View {
        HStack(spacing:6) {
            PremiumIcon(name:icon,size:22,gold:icon != "Envelope",glow:icon == "Lock")
                .padding(7).background(Circle().fill(Palette.nebula.opacity(0.28)))
            VStack(alignment:.leading,spacing:2) {
                Text(count.formatted()).font(.system(size:23,weight:.semibold)).foregroundStyle(Palette.ink).minimumScaleFactor(0.7)
                Text(label).font(.system(size:8)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength:0)
        }.padding(.horizontal,7).frame(maxWidth:.infinity).frame(minHeight:58).background(GlassSurface(radius:14))
        .accessibilityElement(children:.combine)
    }

    private var navigationBar: some View {
        HStack(spacing:0) {
            ForEach(["Home","Record","Write","Scheduled","Vault"],id:\.self) { item in
                Button {
                    if item == "Record" || item == "Write" {openComposer(item)} else {destination=item}
                } label: {
                    VStack(spacing:5) {
                        PremiumIcon(name:item,size:25,glow:destination == item)
                        Text(item).font(.system(size:10,weight:destination == item ? .semibold : .regular))
                            .foregroundStyle(destination == item ? Palette.ink : Palette.muted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth:.infinity).frame(height:58)
                    .background {
                        if destination == item { RadialGradient(colors:[Color.purple.opacity(0.45),.clear],center:.center,startRadius:1,endRadius:44) }
                    }
                    .overlay(alignment:.bottom) {
                        if destination == item {SwiftUI.Capsule().fill(Palette.glow).frame(width:27,height:2).shadow(color:Palette.gold,radius:4)}
                    }
                }.buttonStyle(.plain).accessibilityAddTraits(destination == item ? .isSelected : [])
            }
        }
        .padding(.horizontal,8).padding(.vertical,3)
        .background(GlassSurface(radius:32))
        .padding(.horizontal,12).padding(.top,8).padding(.bottom,5)
        .background(Palette.paper.opacity(0.96))
    }

    private func openComposer(_ focus:String) {composeFocus=focus;composing=true}

    private func collection(now:Date) -> some View {
        let items=store.capsules.filter { capsule in
            if destination == "Scheduled" {return !capsule.isOpened && (capsule.unlockDate == nil || !capsule.canOpen(at:now))}
            if vaultFilter == "Delivered" {return capsule.isOpened || (capsule.unlockDate != nil && capsule.canOpen(at:now))}
            return true
        }.sorted{($0.unlockDate ?? .distantFuture)<($1.unlockDate ?? .distantFuture)}
        return VStack(alignment:.leading,spacing:16) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text(destination == "Vault" ? "My Vault" : "Scheduled Deliveries").font(.custom("Baskerville",size:30,relativeTo:.largeTitle)).foregroundStyle(Palette.gold)
                    Text(destination == "Vault" ? "Every chapter of your story." : "Good things take a little time.").font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer()
                PremiumIcon(name:destination == "Vault" ? "Vault" : "Scheduled",size:36,gold:true)
            }.padding(.vertical,12)
            if destination == "Vault" {
                Picker("Capsules",selection:$vaultFilter) {Text("All Capsules").tag("All");Text("Delivered").tag("Delivered")}.pickerStyle(.segmented)
            }
            if items.isEmpty {
                VStack(spacing:18) {
                    EnvelopeEmblem(size:125)
                    Text(destination == "Vault" ? "Your memories belong here." : "Nothing scheduled yet.").font(.title3).foregroundStyle(Palette.ink)
                    Text("Record your voice or write a letter, then choose when it finds you.").font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    Button("Write your first message"){openComposer("Write")}.buttonStyle(GlowButtonStyle())
                }.frame(maxWidth:.infinity).padding(.vertical,25)
            }
            rows(items,now:now)
        }
    }

    private func capsuleButton(_ capsule:Capsule,now:Date) -> some View {
        Button {selected=capsule.id} label:{CapsuleRow(capsule:capsule,now:now)}.buttonStyle(.plain)
    }
    private func rows(_ capsules:[Capsule],now:Date) -> some View {
        VStack(spacing:10) {ForEach(capsules) {capsule in capsuleButton(capsule,now:now)}}
    }

    private func startDemoIfAsked() {
        guard !startedDemo else{return};startedDemo=true
        let args=ProcessInfo.processInfo.arguments
        if args.contains("-CapsuleLandscape"),let scene=UIApplication.shared.connectedScenes.first as? UIWindowScene {scene.requestGeometryUpdate(.iOS(interfaceOrientations:.landscapeRight)){_ in}}
        if args.contains("-CapsuleCompose") {composeFocus="Record";composing=true}
        if args.contains("-CapsuleWrite") {composeFocus="Write";composing=true}
        if args.contains("-CapsuleSchedule") {composeFocus="Schedule";composing=true}
        if args.contains("-CapsuleScheduled") {destination="Scheduled"}
        if args.contains("-CapsuleVault") {destination="Vault"}
        if args.contains("-CapsuleSettings") {panel="Settings"}
        if args.contains("-CapsuleSealedDemo") {selected=store.capsules.first{!$0.canOpen(at:Date())}?.id}
        if args.contains("-CapsuleOpenedDemo") {selected=store.capsules.first(where:\.isOpened)?.id}
    }
}

struct CapsuleRow: View {
    let capsule:Capsule
    let now:Date
    var body: some View {
        let ready = !capsule.isOpened && capsule.unlockDate != nil && capsule.canOpen(at:now)
        HStack(spacing:10) {
            ZStack {
                Circle().fill(Palette.nebula.opacity(0.5)).overlay(Circle().stroke(Palette.lavender.opacity(0.5)))
                PremiumIcon(name:capsule.isOpened ? "Delivered" : "Envelope",size:27,gold:capsule.isOpened,glow:true)
                if !capsule.isOpened {PremiumIcon(name:"Lock",size:13).offset(y:-13)}
            }.frame(width:43,height:43)
            VStack(alignment:.leading,spacing:4) {
                Text(capsule.displayTitle).font(.system(size:14,weight:.semibold)).foregroundStyle(Palette.ink).lineLimit(2).multilineTextAlignment(.leading)
                Text(capsule.statusLine(at:now)).font(.system(size:11)).foregroundStyle(ready ? Palette.gold : Palette.muted).lineLimit(2).multilineTextAlignment(.leading)
            }.frame(maxWidth:.infinity,alignment:.leading)
            if !capsule.isOpened,let date=capsule.unlockDate,date > now {
                Text(CapsuleFormat.clock(to:date,from:now))
                    .font(.system(size:12,weight:.semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink).padding(.horizontal,9).padding(.vertical,7)
                    .background(SwiftUI.Capsule().fill(Palette.nebula.opacity(0.5)))
                    .overlay(SwiftUI.Capsule().stroke(Palette.lavender.opacity(0.6)))
                    .accessibilityLabel("Time remaining: \(CapsuleFormat.clock(to:date,from:now))")
            }
            Text("›").font(.title2).foregroundStyle(Palette.lavender)
        }.padding(12).frame(minHeight:64).background(GlassSurface())
        .accessibilityElement(children:.combine)
    }
}

struct PremiumAccountView: View {
    let section:String
    @EnvironmentObject private var store:CapsuleStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dearTomorrowName") private var name=""
    @AppStorage("dearTomorrowSound") private var sound=true
    @State private var notificationStatus="Checking…"
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    HStack {Text(section).font(.custom("Baskerville",size:32)).foregroundStyle(Palette.gold);Spacer();PremiumIcon(name:section,size:32,gold:true)}
                    if section == "Profile" {
                        Text("What should your future self call you?").foregroundStyle(Palette.muted)
                        TextField("Your preferred name",text:$name).textContentType(.givenName).textInputAutocapitalization(.words).card().accessibilityLabel("Preferred name")
                    } else if section == "Notifications" {
                        Text("Delivery reminders").font(.headline).foregroundStyle(Palette.ink)
                        Text(notificationStatus).foregroundStyle(Palette.muted)
                        Button("Enable reminders") {Task{await store.requestNotificationPermission();await refreshStatus()}}.buttonStyle(GlowButtonStyle())
                        Button("Open iPhone notification settings"){openSettings()}.foregroundStyle(Palette.gold).frame(minHeight:44)
                        TimelineView(.periodic(from:.now,by:1)) {context in
                            VStack(spacing:12) {
                                let deliveries=store.capsules.filter{!$0.isOpened && $0.unlockDate != nil}.sorted{($0.unlockDate ?? .distantFuture)<($1.unlockDate ?? .distantFuture)}
                                if deliveries.isEmpty {Text("Your scheduled messages will appear here.").foregroundStyle(Palette.muted).card()}
                                ForEach(deliveries) {capsule in
                                    NavigationLink {CapsuleView(capsuleID:capsule.id)} label:{CapsuleRow(capsule:capsule,now:context.date)}.buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        Toggle("Signature startup sound",isOn:$sound).tint(Palette.gold).card()
                        NavigationLink("Your profile") {PremiumAccountView(section:"Profile")}.foregroundStyle(Palette.ink).card()
                        NavigationLink("Notifications") {PremiumAccountView(section:"Notifications")}.foregroundStyle(Palette.ink).card()
                        VStack(alignment:.leading,spacing:10) {
                            Text("Private by design").font(.headline).foregroundStyle(Palette.gold)
                            Text("Your recordings, notes and photos stay on this iPhone. Sealed messages remain locked until their delivery date. Keep the app installed to preserve your capsules.").font(.subheadline).foregroundStyle(Palette.muted)
                        }.card()
                        VStack(spacing:8) {
                            BrandWordmark(size:30)
                            Text("CTNETWORK Studios").font(.caption).foregroundStyle(Palette.gold)
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") • Build \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "")").font(.caption2).foregroundStyle(Palette.muted)
                        }.frame(maxWidth:.infinity).padding(.vertical,20)
                    }
                }.padding(20).frame(maxWidth:600).frame(maxWidth:.infinity)
            }
            .background(CosmicBackground())
            .toolbar {ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}}}
        }.tint(Palette.gold).task{await refreshStatus()}
    }
    private func refreshStatus() async {
        let settings=await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional ? "Reminders are enabled. You’ll hear when your messages arrive." : "Reminders are off. Your capsules still unlock on schedule."
    }
    private func openSettings(){if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}
}
