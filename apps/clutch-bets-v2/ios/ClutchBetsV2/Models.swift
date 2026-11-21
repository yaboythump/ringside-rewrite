import Foundation
import Combine

enum BetStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "Open"
    case won = "Won"
    case lost = "Lost"
    case voided = "Void"
    var id: String { rawValue }
}

enum SportsbookMath {
    static func decimalOdds(_ american: Int) -> Double? {
        guard american != 0, american >= 100 || american <= -100 else { return nil }
        return american > 0 ? 1 + Double(american) / 100 : 1 + 100 / Double(-american)
    }

    static func impliedProbability(_ american: Int) -> Double? {
        guard let decimal = decimalOdds(american) else { return nil }
        return 1 / decimal
    }

    static func payout(odds: [Int], stake: Double) -> Double? {
        guard stake > 0, !odds.isEmpty else { return nil }
        let decimals = odds.compactMap(decimalOdds)
        guard decimals.count == odds.count else { return nil }
        return stake * decimals.reduce(1, *)
    }

    static func arbitrage(a: Int, b: Int, totalStake: Double) -> (stakeA: Double, stakeB: Double, profit: Double)? {
        guard let pA = impliedProbability(a), let pB = impliedProbability(b), totalStake > 0 else { return nil }
        let combined = pA + pB
        guard combined < 1 else { return nil }
        return (totalStake * pA / combined, totalStake * pB / combined, totalStake * (1 / combined - 1))
    }
}

struct BetLeg: Identifiable, Codable, Equatable {
    var id = UUID()
    var sport: String
    var matchup: String
    var market: String
    var pick: String
    var americanOdds: Int
    var researchNote: String

    var decimalOdds: Double { SportsbookMath.decimalOdds(americanOdds) ?? 1 }
    var displayOdds: String { americanOdds > 0 ? "+\(americanOdds)" : "\(americanOdds)" }
}

struct BetTicket: Identifiable, Codable {
    var id = UUID()
    var createdAt = Date()
    var legs: [BetLeg]
    var stakeUnits: Double
    var status: BetStatus = .pending
    var notes: String = ""
    var unitAtPlacement: Double

    var stake: Double { stakeUnits * unitAtPlacement }
    var grossPayout: Double { SportsbookMath.payout(odds: legs.map(\.americanOdds), stake: stake) ?? 0 }
    var potentialProfit: Double { max(0, grossPayout - stake) }
    var realizedProfit: Double {
        switch status {
        case .won: return potentialProfit
        case .lost: return -stake
        case .pending, .voided: return 0
        }
    }
}

final class ClutchStore: ObservableObject {
    private static let ticketsKey = "ClutchBetsV2.tickets"
    private static let unitKey = "ClutchBetsV2.unitValue"
    private static let bankrollKey = "ClutchBetsV2.bankroll"

    @Published var tickets: [BetTicket] {
        didSet { saveTickets() }
    }
    @Published var unitValue: Double {
        didSet { UserDefaults.standard.set(unitValue, forKey: Self.unitKey) }
    }
    @Published var openingBankroll: Double {
        didSet { UserDefaults.standard.set(openingBankroll, forKey: Self.bankrollKey) }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.ticketsKey),
           let saved = try? JSONDecoder().decode([BetTicket].self, from: data) {
            tickets = saved
        } else {
            tickets = []
        }
        let savedUnit = UserDefaults.standard.double(forKey: Self.unitKey)
        unitValue = savedUnit > 0 ? savedUnit : 25
        let savedBankroll = UserDefaults.standard.double(forKey: Self.bankrollKey)
        openingBankroll = savedBankroll > 0 ? savedBankroll : 1000
    }

    var openTickets: [BetTicket] { tickets.filter { $0.status == .pending } }
    var settledTickets: [BetTicket] { tickets.filter { $0.status == .won || $0.status == .lost } }
    var settledStakes: Double { settledTickets.reduce(0) { $0 + $1.stake } }
    var realizedProfit: Double { tickets.reduce(0) { $0 + $1.realizedProfit } }
    var bankroll: Double { openingBankroll + realizedProfit }
    var wins: Int { tickets.filter { $0.status == .won }.count }
    var losses: Int { tickets.filter { $0.status == .lost }.count }
    var winRate: Double {
        let count = wins + losses
        return count == 0 ? 0 : 100 * Double(wins) / Double(count)
    }
    var roi: Double { settledStakes == 0 ? 0 : 100 * realizedProfit / settledStakes }

    func add(_ ticket: BetTicket) { tickets.insert(ticket, at: 0) }

    func updateStatus(id: UUID, status: BetStatus) {
        guard let index = tickets.firstIndex(where: { $0.id == id }) else { return }
        tickets[index].status = status
    }

    func delete(at offsets: IndexSet) { for index in offsets.sorted(by: >) { tickets.remove(at: index) } }

    private func saveTickets() {
        guard let data = try? JSONEncoder().encode(tickets) else { return }
        UserDefaults.standard.set(data, forKey: Self.ticketsKey)
    }
}

extension Double {
    var money: String { String(format: "$%.2f", self) }
    var signedMoney: String { self >= 0 ? "+" + money : "-" + abs(self).money }
}
