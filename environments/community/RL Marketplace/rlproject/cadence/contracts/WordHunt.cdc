import "FungibleToken"
import "FlowToken"
import "DeFiActions"

access(all) contract WordHunt {

    // --- Public Interface ---
    access(all) resource interface Public {
        access(all) fun createSink(): WordHunt.WordHuntSink
    }

    // This resource implements the public interface and is what we will
    // expose to the public. It acts as a secure forwarder.
    access(all) resource PublicProvider: Public {
        access(all) fun createSink(): WordHunt.WordHuntSink {
            return WordHunt.createSink()
        }
    }

    // --- Game State ---
    access(all) let prizeVault: @FlowToken.Vault
    access(all) var entrants: [Address]
    access(all) var oracleSolutions: {String: [String]} // Board-ID -> Solutions

    // --- Training Data Sink State ---
    access(self) let treasury: @FlowToken.Vault
    access(all) let treasuryReceiverCap: Capability<&{FungibleToken.Receiver}>
    access(self) var credits: {Address: UFix64}

    // --- FlowActions-compliant Sink ---
    access(all) struct WordHuntSink: DeFiActions.Sink {
        access(self) let receiver: Capability<&{FungibleToken.Receiver}>
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(receiver: Capability<&{FungibleToken.Receiver}>) {
            self.receiver = receiver
            self.uniqueID = nil // We'll keep this simple for now
        }

        // FlowActions Sink interface implementation
        access(all) view fun getSinkType(): Type {
            return Type<@FlowToken.Vault>()
        }

        access(all) fun minimumCapacity(): UFix64 {
            // For simplicity, we'll accept any amount
            return 0.0
        }

        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            // This is the FlowActions standard deposit method
            let amount = from.balance
            let payment <- from.withdraw(amount: amount)
            let recv = self.receiver.borrow() ?? panic("bad receiver cap")
            recv.deposit(from: <-payment)
        }

        // Custom method for crediting users and getting solutions
        access(all) fun depositAndCredit(payment: @FlowToken.Vault, user: Address) {
            let amount: UFix64 = payment.balance
            let recv = self.receiver.borrow() ?? panic("bad receiver cap")
            recv.deposit(from: <-payment)
            WordHunt.addCredits(user: user, amount: amount)
        }

        access(all) fun getSolutions(boardId: String, user: Address): [String] {
            if (WordHunt.credits[user] ?? 0.0) <= 0.0 { return [] }
            // Optional: Decrement credits per call
            // WordHunt.credits[user] = WordHunt.credits[user]! - 1.0
            return WordHunt.getAgentSolutions(boardId: boardId)
        }

        // IdentifiableStruct interface implementation
        access(all) view fun id(): UInt64? {
            return self.uniqueID?.id
        }

        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: []
            )
        }

        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }

        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }
    }
    
    // --- Public Factory for Sink ---
    access(all) fun createSink(): WordHuntSink {
        return WordHuntSink(receiver: self.treasuryReceiverCap)
    }

    // A function to accept an entry fee.
    access(all) fun payEntryFee(payment: @FlowToken.Vault, from: Address) {
        self.entrants.append(from)
        self.prizeVault.deposit(from: <-payment)
    }

    // A function to let the Oracle submit solutions for a given board.
    access(all) fun submitSolutions(boardId: String, solutions: [String]) {
        // In a real-world scenario, you would add access control here
        // to ensure only your trusted Oracle can call this function.
        // For the hackathon, we'll allow anyone to call it.
        self.oracleSolutions[boardId] = solutions
        log("Solutions stored on-chain for Board-ID:")
        log(boardId)
    }

    // A function to pay out the prize pool to the winner.
    access(all) fun payout(): @FlowToken.Vault {
        // The winner is the first person who entered.
        let winner = self.entrants[0]

        // Get the total prize pool.
        let prizeAmount = self.prizeVault.balance

        // Withdraw the prize pool.
        let prize <- self.prizeVault.withdraw(amount: prizeAmount) as! @FlowToken.Vault

        // Reset the entrants for the next round.
        self.entrants = []

        return <-prize
    }

    // --- Internal Sink Helpers ---
    access(self) fun addCredits(user: Address, amount: UFix64) {
        self.credits[user] = (self.credits[user] ?? 0.0) + amount
    }
    access(self) fun getAgentSolutions(boardId: String): [String] {
        // This is where you would implement your logic to return solutions.
        // For now, it returns an empty array.
        return []
    }

    init() {
        // Initialize game state
        self.prizeVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        self.entrants = []
        self.oracleSolutions = {}

        // Initialize sink state
        let treasury <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        self.account.storage.save(<-treasury, to: /storage/wordHuntTreasury)

        self.treasuryReceiverCap = self.account.capabilities.storage.issue<&{FungibleToken.Receiver}>(/storage/wordHuntTreasury)
        self.account.capabilities.publish(self.treasuryReceiverCap, at: /public/wordHuntTreasuryReceiver)
        
        // We must borrow the vault back after saving it to storage
        self.treasury <- self.account.storage.load<@FlowToken.Vault>(from: /storage/wordHuntTreasury)!
        
        self.credits = {}

        // Save the public provider resource to storage and publish a capability to it.
        self.account.storage.save(<-create PublicProvider(), to: /storage/WordHuntPublicProvider)
        self.account.capabilities.publish(
            self.account.capabilities.storage.issue<&PublicProvider>(/storage/WordHuntPublicProvider),
            at: /public/WordHuntPublicProvider
        )
    }
}