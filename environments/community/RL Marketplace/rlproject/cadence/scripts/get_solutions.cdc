import "WordHunt"

// This script allows a user to view the solutions for a given board,
// provided they have enough credits.
access(all) fun main(boardId: String, user: Address): [String] {
    // Get the public account object for the account that deployed the contract.
    let contractAccount = getAccount(0xf8d6e0586b0a20c7)

    // Borrow a reference to the contract's public interface.
    let wordHunt = contractAccount.capabilities
        .get<&WordHunt.PublicProvider>(/public/WordHuntPublicProvider)
        .borrow()
        ?? panic("Could not borrow WordHunt public capability")

    // Create the sink using the public interface.
    let sink = wordHunt.createSink()

    // Get the solutions.
    let solutions = sink.getSolutions(boardId: boardId, user: user)

    return solutions
}
