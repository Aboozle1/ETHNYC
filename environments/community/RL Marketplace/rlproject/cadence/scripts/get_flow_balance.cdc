import "FungibleToken"
import "FlowToken"

// This script returns the FLOW balance of an account.
access(all) fun main(address: Address): UFix64 {
    let account = getAccount(address)

    let vaultRef = account.capabilities
        .get<&FlowToken.Vault{FungibleToken.Balance}>(/public/flowTokenReceiver)
        .borrow()
        ?? panic("Could not borrow Balance capability")

    return vaultRef.balance
}
