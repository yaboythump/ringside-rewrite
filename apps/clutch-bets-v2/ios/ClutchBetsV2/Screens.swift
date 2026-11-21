import SwiftUI

private struct ClutchInput: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var numeric = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                .foregroundStyle(ClutchStyle.muted)
            TextField(placeholder, text: $text)
                .keyboardType(numeric ? .numbersAndPunctuation : .default)
                .textInputAutocapitalization(numeric ? .never : .words)
                .foregroundStyle(.white)
                .padding(13)
                .background(ClutchStyle.panelLight, in: RoundedRectangle(cornerRadius: 11))
                .autocorrectionDisabled()
        }
    }
}

struct SlipBuilderView: View {
    @EnvironmentObject var store: ClutchStore
    @State private var sport = "NBA"
    @State private var matchup = ""
    @State private var market = "Player Points"
    @State private var pick = ""
    @State private var odds = "-110"
    @State private var note = ""
    @State private var legs: [BetLeg] = []
    @State private var units = 1.0
    @State private var feedback: String?
    private let sports = ["NBA", "NFL", "MLB", "NHL", "NCAAF", "NCAAB", "WNBA", "Other"]

    var body: some View {
        SectionIntro(eyebrow: "BETSLIP LAB", title: "Build Your Slip.", subtitle: "Research the selection, enter the line, then calculate your exposure.")
        PremiumPanel("Add a selection") {
            HStack {
                Text("SPORT").font(.system(size: 10, weight: .black)).foregroundStyle(ClutchStyle.muted)
                Spacer()
                Picker("Sport", selection: $sport) {
                    ForEach(sports, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
            }
            ClutchInput(label: "Matchup", text: $matchup, placeholder: "e.g. Boston vs Miami")
            ClutchInput(label: "Market", text: $market, placeholder: "Player points, spread, total...")
            ClutchInput(label: "Your selection", text: $pick, placeholder: "e.g. Player over 24.5")
            ClutchInput(label: "American odds", text: $odds, placeholder: "-110 or +145", numeric: true)
            ClutchInput(label: "Research note (optional)", text: $note, placeholder: "Last 10, injuries, line value...")
            if let error = feedback {
                Text(error).font(.system(size: 12)).foregroundStyle(ClutchStyle.gold)
            }
            GoldenButton(title: "ADD TO SLIP", symbol: "plus", action: addLeg)
        }

        PremiumPanel("Current slip  •  \(legs.count) legs") {
            if legs.isEmpty {
                Label("Your slip is empty. Add a researched selection above.", systemImage: "square.stack")
                    .font(.system(size: 13))
                    .foregroundStyle(ClutchStyle.muted)
            } else {
                ForEach(legs) { leg in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(leg.sport)  •  \(leg.matchup)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(ClutchStyle.muted)
                            Text(leg.pick)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                            Text(leg.market)
                                .font(.system(size: 12))
                                .foregroundStyle(ClutchStyle.silver)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 9) {
                            Text(leg.displayOdds)
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(ClutchStyle.gold)
                            Button(role: .destructive) {
                                legs.removeAll { $0.id == leg.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(ClutchStyle.muted)
                            }
                            .accessibilityLabel("Remove \(leg.pick)")
                        }
                    }
                    Divider().overlay(ClutchStyle.border)
                }

                Stepper(value: $units, in: 0.25...100, step: 0.25) {
                    HStack {
                        Text("STAKE").foregroundStyle(ClutchStyle.silver)
                        Spacer()
                        Text(String(format: "%.2f units", units))
                            .fontWeight(.bold)
                            .foregroundStyle(ClutchStyle.gold)
                    }
                    .font(.system(size: 13))
                }
                HStack {
                    Text("1 unit = \(store.unitValue.money)")
                    Spacer()
                    Text("Stake: \((units * store.unitValue).money)")
                }
                .font(.system(size: 12))
                .foregroundStyle(ClutchStyle.muted)

                if let gross = SportsbookMath.payout(odds: legs.map(\.americanOdds), stake: units * store.unitValue) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("POTENTIAL RETURN").font(.system(size: 10, weight: .black)).tracking(1.2)
                            Text(gross.money).font(.system(size: 27, weight: .black))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("POTENTIAL PROFIT").font(.system(size: 10, weight: .black)).tracking(1.2)
                            Text((gross - units * store.unitValue).money)
                                .font(.system(size: 20, weight: .black))
                        }
                    }
                    .foregroundStyle(ClutchStyle.gold)
                }
                Text("Returns are mathematical estimates from manually entered odds, not an offered sportsbook price.")
                    .font(.system(size: 11))
                    .foregroundStyle(ClutchStyle.muted)
                GoldenButton(title: "SAVE TO MY BETS", symbol: "tray.and.arrow.down.fill", action: saveTicket)
            }
        }
        PremiumPanel("Green Slip Rules") {
            Text("A Green Slip should pass lineup, minutes, recent-form, opponent, injury and price checks before being considered. No wager is risk-free.")
                .font(.system(size: 13))
                .foregroundStyle(ClutchStyle.silver)
        }
    }

    private func addLeg() {
        guard !matchup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !market.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            feedback = "Enter a matchup, market and selection."
            return
        }
        guard let american = Int(odds.trimmingCharacters(in: .whitespacesAndNewlines)),
              SportsbookMath.decimalOdds(american) != nil else {
            feedback = "Use valid American odds, such as -110 or +145."
            return
        }
        let leg = BetLeg(sport: sport, matchup: matchup, market: market, pick: pick,
                         americanOdds: american, researchNote: note)
        legs.append(leg)
        matchup = ""
        pick = ""
        note = ""
        odds = "-110"
        feedback = nil
    }

    private func saveTicket() {
        guard !legs.isEmpty, store.unitValue > 0 else { return }
        store.add(BetTicket(legs: legs, stakeUnits: units, unitAtPlacement: store.unitValue))
        legs = []
        units = 1
        feedback = "Slip saved. Open My Bets to track the result."
    }
}

struct TicketsView: View {
    @EnvironmentObject var store: ClutchStore

    var body: some View {
        SectionIntro(eyebrow: "YOUR LEDGER", title: "Every Bet Counts.", subtitle: "Your personal on-device ledger. Results are updated by you.")
        HStack(spacing: 12) {
            valueChip("WINS", "\(store.wins)", ClutchStyle.green)
            valueChip("LOSSES", "\(store.losses)", ClutchStyle.silver)
            valueChip("ROI", String(format: "%.1f%%", store.roi), ClutchStyle.gold)
        }
        if store.tickets.isEmpty {
            PremiumPanel("No saved tickets") {
                Text("Build your first slip to see your tickets, returns and tracked results here.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClutchStyle.muted)
            }
        } else {
            ForEach(store.tickets) { ticket in
                PremiumPanel(ticket.legs.count == 1 ? "Straight bet" : "\(ticket.legs.count)-leg parlay") {
                    HStack {
                        Text(ticket.createdAt, style: .date)
                            .font(.system(size: 11))
                            .foregroundStyle(ClutchStyle.muted)
                        Spacer()
                        Menu {
                            ForEach(BetStatus.allCases) { status in
                                Button(status.rawValue) { store.updateStatus(id: ticket.id, status: status) }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(ticket.status.rawValue)
                                Image(systemName: "chevron.down")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ticket.status == .won ? ClutchStyle.green : ClutchStyle.gold)
                        }
                    }
                    ForEach(ticket.legs) { leg in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(leg.sport)  •  \(leg.matchup)")
                                .font(.system(size: 11)).foregroundStyle(ClutchStyle.muted)
                            HStack {
                                Text(leg.pick).foregroundStyle(.white).fontWeight(.bold)
                                Spacer()
                                Text(leg.displayOdds).foregroundStyle(ClutchStyle.gold).fontWeight(.black)
                            }
                            .font(.system(size: 13))
                            if !leg.researchNote.isEmpty {
                                Text(leg.researchNote).font(.system(size: 11)).foregroundStyle(ClutchStyle.muted)
                            }
                        }
                    }
                    Divider().overlay(ClutchStyle.border)
                    HStack {
                        infoValue("STAKED", ticket.stake.money)
                        Spacer()
                        infoValue("TO RETURN", ticket.grossPayout.money)
                        Spacer()
                        infoValue("P/L", ticket.status == .pending ? "Pending" : ticket.realizedProfit.signedMoney)
                    }
                }
            }
        }
        Text("Tap each ticket status to mark it Won, Lost, Void or Open. Only completed tickets affect your P/L.")
            .font(.system(size: 11))
            .foregroundStyle(ClutchStyle.muted)
    }

    private func infoValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(ClutchStyle.muted)
            Text(value).font(.system(size: 13, weight: .black)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.65)
        }
    }

    private func valueChip(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 10, weight: .black)).foregroundStyle(ClutchStyle.muted)
            Text(value).font(.system(size: 22, weight: .black)).foregroundStyle(color).minimumScaleFactor(0.65).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(ClutchStyle.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct EdgeToolsView: View {
    @EnvironmentObject var store: ClutchStore
    @State private var odds = "-110"
    @State private var oddsA = "+115"
    @State private var oddsB = "+110"
    @State private var arbStake = "100"
    @State private var calcUnits = 1.0

    var body: some View {
        SectionIntro(eyebrow: "NUMBERS DON'T GUESS", title: "Edge Tools.", subtitle: "Clear calculations for prices, exposure and your bankroll.")
        PremiumPanel("Bankroll & Unit System") {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TRACKED BANKROLL").font(.system(size: 10, weight: .black)).foregroundStyle(ClutchStyle.muted)
                    Text(store.bankroll.money).font(.system(size: 27, weight: .black)).foregroundStyle(ClutchStyle.gold)
                }
                Spacer()
                Image(systemName: "chart.pie.fill").font(.system(size: 27)).foregroundStyle(ClutchStyle.gold)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("OPENING BANKROLL").font(.system(size: 10, weight: .bold)).foregroundStyle(ClutchStyle.muted)
                TextField("Opening bankroll", value: $store.openingBankroll, format: .number)
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(ClutchStyle.panelLight, in: RoundedRectangle(cornerRadius: 10))
                Text("UNIT SIZE (USD)").font(.system(size: 10, weight: .bold)).foregroundStyle(ClutchStyle.muted)
                TextField("Unit size", value: $store.unitValue, format: .number)
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(ClutchStyle.panelLight, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Defaults: $1,000 opening bankroll and $25 per unit. Existing tickets keep their original unit value.")
                .font(.system(size: 11)).foregroundStyle(ClutchStyle.muted)
        }
        PremiumPanel("Odds & Payout Calculator") {
            ClutchInput(label: "American odds", text: $odds, placeholder: "-110", numeric: true)
            Stepper(value: $calcUnits, in: 0.25...100, step: 0.25) {
                Text(String(format: "Stake: %.2f units", calcUnits))
                    .foregroundStyle(ClutchStyle.silver).font(.system(size: 13))
            }
            if let value = Int(odds), let decimal = SportsbookMath.decimalOdds(value) {
                HStack {
                    calculation("STAKE", (calcUnits * store.unitValue).money)
                    Spacer()
                    calculation("RETURN", (calcUnits * store.unitValue * decimal).money)
                    Spacer()
                    calculation("IMPLIED", String(format: "%.1f%%", 100 / decimal))
                }
            } else {
                Text("Enter valid American odds (absolute value 100 or greater).")
                    .font(.system(size: 12)).foregroundStyle(ClutchStyle.muted)
            }
        }
        PremiumPanel("Two-Way Arbitrage Check") {
            Text("Enter opposing outcomes at different books. Both prices must be for a market with exactly two exhaustive outcomes and identical settlement rules.")
                .font(.system(size: 12)).foregroundStyle(ClutchStyle.muted)
            ClutchInput(label: "Side A American odds", text: $oddsA, placeholder: "+115", numeric: true)
            ClutchInput(label: "Side B American odds", text: $oddsB, placeholder: "+110", numeric: true)
            ClutchInput(label: "Total amount to stake ($)", text: $arbStake, placeholder: "100", numeric: true)
            if let a = Int(oddsA), let b = Int(oddsB),
               let pA = SportsbookMath.impliedProbability(a),
               let pB = SportsbookMath.impliedProbability(b),
               let stake = Double(arbStake), stake > 0 {
                if let result = SportsbookMath.arbitrage(a: a, b: b, totalStake: stake) {
                    Label("Mathematical arbitrage detected", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(ClutchStyle.green)
                    HStack {
                        calculation("SIDE A", result.stakeA.money)
                        Spacer()
                        calculation("SIDE B", result.stakeB.money)
                        Spacer()
                        calculation("GROSS EDGE", result.profit.money)
                    }
                } else {
                    Label(String(format: "No positive two-way edge (implied total %.1f%%).", 100 * (pA + pB)),
                          systemImage: "minus.circle")
                        .font(.system(size: 12)).foregroundStyle(ClutchStyle.silver)
                }
            } else {
                Text("Enter valid odds and a positive total stake.")
                    .font(.system(size: 12)).foregroundStyle(ClutchStyle.muted)
            }
            Text("Before betting, check limits, market rules, rounding, timing and void risk. These figures do not guarantee profit.")
                .font(.system(size: 11)).foregroundStyle(ClutchStyle.muted)
        }
        PremiumPanel("Data & Transparency") {
            Label("V2 stores your tickets locally on this device.", systemImage: "lock.shield")
                .foregroundStyle(ClutchStyle.silver).font(.system(size: 12))
            Label("No live odds, sportsbooks or verified-pick API connected yet.", systemImage: "network.slash")
                .foregroundStyle(ClutchStyle.silver).font(.system(size: 12))
            Label("V2 does not place bets or transfer money.", systemImage: "hand.raised")
                .foregroundStyle(ClutchStyle.silver).font(.system(size: 12))
        }
    }

    private func calculation(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(ClutchStyle.muted)
            Text(value).font(.system(size: 17, weight: .black)).foregroundStyle(ClutchStyle.gold)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}
