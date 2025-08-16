import "FungibleToken"
import "FlowToken"
import "WordHunt"

// This transaction pays a 10.0 FLOW entry fee to the WordHunt contract.
transaction {
    let feeAmount: UFix64
    let signerAddress: Address

    prepare(signer: AuthAccount) {
        self.feeAmount = 10.0
        self.signerAddress = signer.address

        // Get a reference to the signer's FLOW vault.
        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow reference to the owner's Vault!")

        // Withdraw the entry fee.
        let payment <- vaultRef.withdraw(amount: self.feeAmount)

        // Pay the entry fee to the WordHunt contract.
        WordHunt.payEntryFee(payment: <-payment, from: self.signerAddress)
    }

    pre {
        self.feeAmount > 0.0: "Entry fee must be positive"
    }

    post {
        // Post-condition could check if the user is now an entrant,
        // but that would require a new public function in the contract.
        // For now, we'll keep it simple.
    }

    execute {
        log("Entry fee paid successfully")
    }
}
