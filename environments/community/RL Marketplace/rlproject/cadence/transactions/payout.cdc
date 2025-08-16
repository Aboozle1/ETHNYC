import "FungibleToken"
import "FlowToken"
import "WordHunt"

// This transaction pays out the prize pool to the winner.
transaction {
    let prizeReceiver: Capability<&{FungibleToken.Receiver}>
    let prizeAmount: UFix64

    prepare(signer: AuthAccount) {
        // Get the prize vault from the contract.
        let prize <- WordHunt.payout()
        self.prizeAmount = prize.balance

        // Get a reference to the winner's vault.
        self.prizeReceiver = signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(/storage/flowTokenVault)
        
        // Deposit the prize.
        let receiver = self.prizeReceiver.borrow()!
        receiver.deposit(from: <-prize)
    }

    pre {
        self.prizeAmount > 0.0: "Prize amount must be positive"
    }

    post {
        self.prizeReceiver.borrow()!.balance > 0.0: "Winner did not receive prize"
    }

    execute {
        log("Payout successful")
    }
}
