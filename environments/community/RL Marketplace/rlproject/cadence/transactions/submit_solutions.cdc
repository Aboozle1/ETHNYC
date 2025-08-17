import "WordHunt"

// This transaction is called by our Oracle (the Python server)
// to submit the solutions found by the LLM to the smart contract.
transaction(boardId: String, solutions: [String]) {

    let wordHunt: &{WordHunt.Public}

    prepare(signer: auth(BorrowValue) &Account) {
        // Get the public capability for the WordHunt contract
        let capability = getAccount(WordHunt.account.address).capabilities.get<&{WordHunt.Public}>(/public/WordHuntPublicProvider)
            ?? panic("Could not get WordHunt public capability")

        // Borrow a reference from the capability
        self.wordHunt = capability.borrow()
            ?? panic("Could not borrow WordHunt reference from capability")
        
        // Call the public function on the contract to submit the solutions
        self.wordHunt.submitSolutions(boardId: boardId, solutions: solutions)
    }
}
