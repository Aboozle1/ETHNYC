import "WordHunt"

// This script returns the balance of the WordHunt contract's vault.
access(all) fun main(): UFix64 {
    return WordHunt.prizeVault.balance
}
