import "FungibleToken"
import "FlowToken"

// This transaction sets up a user's account to receive FLOW.
transaction {
    prepare(signer: AuthAccount) {
        // It's not necessary to borrow a reference to the Vault,
        // but it's okay to do so if you want to test that it's possible.
        if signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault) == nil {
            // Create a new flowToken Vault and put it in storage
            signer.storage.save(<-FlowToken.createEmptyVault(), to: /storage/flowTokenVault)

            // Create a public capability to the Vault that only exposes
            // the deposit function through the Receiver interface
            signer.capabilities.publish(
                signer.capabilities.storage.issue<&FlowToken.Vault>(/storage/flowTokenVault),
                at: /public/flowTokenReceiver
            )
        }
    }
}
