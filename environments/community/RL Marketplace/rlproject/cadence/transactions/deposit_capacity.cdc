import "FungibleToken"
import "FlowToken"
import "WordHunt"

// This transaction allows a user to deposit FLOW into the WordHunt contract
// to gain credits for accessing training data (solutions).
transaction(amount: UFix64) {
    let sink: WordHunt.WordHuntSink
    let user: Address

    prepare(signer: AuthAccount) {
        // Create the sink (it's a stateless struct, so this is cheap and safe)
        self.sink = WordHunt.createSink()
        self.user = signer.address

        // Get a reference to the signer's FlowToken vault
        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("Could not borrow reference to the owner's Vault!")

        // Withdraw the specified amount from the vault
        let payment <- vaultRef.withdraw(amount: amount)

        // Use the custom method that credits the user (combines deposit + credit)
        self.sink.depositAndCredit(payment: <-payment, user: self.user)
    }

    pre {
        amount > 0.0: "Deposit amount must be positive"
    }

    post {
        // We can't easily check the new credit balance here without modifying the contract
        // to return it or making the credits public.
    }

    execute {
        log("Deposit and credit successful")
    }
}
