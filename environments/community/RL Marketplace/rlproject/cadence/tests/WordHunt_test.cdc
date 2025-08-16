import Test
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import WordHunt from "WordHunt"

// Test Suite for WordHunt Contract

// Emulator addresses (can be overridden in flow.json for test environment)
access(all) let FungibleTokenAddress: Address = 0xee82856bf20e2aa6
access(all) let FlowTokenAddress: Address = 0x0ae53cb6e3f42a79
access(all) let WordHuntAdmin: Address = Test.getAccount(0x01cf0e2f2f715450) // Using address from flow.json

// Helper to deploy the WordHunt contract
access(all) fun deployContract(): Address {
    let address = Test.deployContract(
        name: "WordHunt",
        path: "../contracts/WordHunt.cdc",
        arguments: []
    )
    return address
}

// Helper to setup a player account with FlowToken Vault
access(all) fun setupPlayerAccount(account: Test.Account) {
    // Setup FlowToken Vault if it doesn't exist (critical for paying entry fees)
    let vaultPath = /storage/flowTokenVault
    if account.storage.type(at: vaultPath) == nil {
        let setupTx = Test.Transaction(
            code: "import FungibleToken from \"FungibleToken\"\nimport FlowToken from \"FlowToken\"\ntransaction {\n    prepare(signer: &Account) {\n        if signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault) == nil {\n            signer.storage.save(<-FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()), to: /storage/flowTokenVault)\n            signer.capabilities.unpublish(/public/flowTokenReceiver)\n            signer.capabilities.publish(\n                signer.capabilities.storage.issue<&FlowToken.Vault{FungibleToken.Receiver}>(\n                    /storage/flowTokenVault\n                ),\n                at: /public/flowTokenReceiver\n            )\n            signer.capabilities.unpublish(/public/flowTokenBalance)\n            signer.capabilities.publish(\n                signer.capabilities.storage.issue<&FlowToken.Vault{FungibleToken.Balance}>(\n                    /storage/flowTokenVault\n                ),\n                at: /public/flowTokenBalance\n            )\n        }\n    }\n}",
            signers: [account],
            imports: {
                "FungibleToken": FungibleTokenAddress,
                "FlowToken": FlowTokenAddress
            }
        )
        let result = Test.executeTransaction(tx: setupTx)
        if result.error != nil {
            panic("Failed to setup FlowToken vault: ".concat(result.error!.message))
        }
    }
    
    // Fund account with initial Flow tokens for testing
    Test.mintFlow(to: account.address, amount: 1000.0)
    
    Test.log("Player account setup complete for: ".concat(account.address.toString()))
}

// Helper to get contract balance
access(all) fun getContractBalance(contractAddress: Address): UFix64 {
    let scriptCode = "import WordHunt from \"WordHunt\"\npub fun main(): UFix64 {\n    return WordHunt.getPrizePool()\n}"
    let result = Test.executeScript(
        code: scriptCode,
        arguments: [],
        imports: {"WordHunt": contractAddress}
    )
    if result.error != nil {
        panic("Failed to get contract balance: ".concat(result.error!.message))
    }
    return result.returnValue! as! UFix64
}

// Helper to get player Flow balance
access(all) fun getPlayerBalance(playerAddress: Address): UFix64 {
    let scriptCode = "import FungibleToken from \"FungibleToken\"\nimport FlowToken from \"FlowToken\"\npub fun main(address: Address): UFix64 {\n    let account = getAccount(address)\n    let vaultRef = account.capabilities.get<&FlowToken.Vault{FungibleToken.Balance}>(/public/flowTokenBalance).borrow()\n        ?? panic(\"Could not borrow Balance reference to the Vault\")\n    return vaultRef.balance\n}"
    let result = Test.executeScript(
        code: scriptCode,
        arguments: [Test.Argument(playerAddress)],
        imports: {
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    if result.error != nil {
        panic("Failed to get player balance: ".concat(result.error!.message))
    }
    return result.returnValue! as! UFix64
}

// --- Test Cases ---

// Test contract deployment
access(all) fun testContractDeployment() {
    Test.log("Starting test: Contract Deployment")
    var deployedAddress: Address? = nil
    
    // For a successful deployment, we expect no panic.
    deployedAddress = Test.deployContract(
        name: "WordHunt",
        path: "../contracts/WordHunt.cdc",
        arguments: []
    )
    Test.assertNotNil(deployedAddress, message: "Deployed contract address should not be nil after successful deployment")
    Test.log("Contract deployed to: ".concat(deployedAddress!.toString()))
    
    // Verify initial contract state
    let initialBalance = getContractBalance(contractAddress: deployedAddress!)
    Test.assertEqual(0.0, initialBalance, message: "Initial contract balance should be 0.0")
    
    Test.log("Contract Deployment Test Passed")
}

// Test player account setup
access(all) fun testPlayerAccountSetup() {
    Test.log("Starting test: Player Account Setup")
    let player1 = Test.createAccount()
    let contractAddress = deployContract()
    
    setupPlayerAccount(account: player1)
    
    // Verify FlowToken vault was created
    let vaultExists = player1.storage.type(at: /storage/flowTokenVault) != nil
    Test.assert(vaultExists, message: "FlowToken vault should exist in storage")
    
    // Verify player has Flow tokens
    let playerBalance = getPlayerBalance(playerAddress: player1.address)
    Test.assert(playerBalance > 0.0, message: "Player should have Flow tokens after setup")
    
    Test.log("Player Account Setup Test Passed")
}

// Test entry fee payment
access(all) fun testPayEntryFee() {
    Test.log("Starting test: Pay Entry Fee")
    let player1 = Test.createAccount()
    let contractAddress = deployContract()
    setupPlayerAccount(account: player1)
    
    // Get initial balances
    let initialPlayerBalance = getPlayerBalance(playerAddress: player1.address)
    let initialContractBalance = getContractBalance(contractAddress: contractAddress)
    
    // Execute entry fee payment transaction
    let payEntryFeeCode = "import WordHunt from \"WordHunt\"\nimport FungibleToken from \"FungibleToken\"\nimport FlowToken from \"FlowToken\"\ntransaction {\n    prepare(signer: &Account) {\n        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)\n            ?? panic(\"Could not borrow reference to the owner's Vault!\")\n        let payment <- vaultRef.withdraw(amount: 10.0)\n        WordHunt.payEntryFee(payment: <-payment)\n    }\n}"
    let payTx = Test.Transaction(
        code: payEntryFeeCode,
        signers: [player1],
        arguments: [],
        imports: {
            "WordHunt": contractAddress,
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    let payResult = Test.executeTransaction(tx: payTx)
    Test.expect(payResult.error == nil, message: payResult.error?.message ?? "Pay entry fee transaction failed")
    
    // Verify balances changed correctly
    let finalPlayerBalance = getPlayerBalance(playerAddress: player1.address)
    let finalContractBalance = getContractBalance(contractAddress: contractAddress)
    
    Test.assertEqual(initialPlayerBalance - 10.0, finalPlayerBalance, message: "Player balance should decrease by 10.0")
    Test.assertEqual(initialContractBalance + 10.0, finalContractBalance, message: "Contract balance should increase by 10.0")
    
    Test.log("Pay Entry Fee Test Passed")
}

// Test two players paying entry fee
access(all) fun testTwoPlayersPayEntryFee() {
    Test.log("Starting test: Two Players Pay Entry Fee")
    let player1 = Test.createAccount()
    let player2 = Test.createAccount()
    let contractAddress = deployContract()
    setupPlayerAccount(account: player1)
    setupPlayerAccount(account: player2)
    
    // Both players pay entry fee
    let payEntryFeeCode = "import WordHunt from \"WordHunt\"\nimport FungibleToken from \"FungibleToken\"\nimport FlowToken from \"FlowToken\"\ntransaction {\n    prepare(signer: &Account) {\n        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)\n            ?? panic(\"Could not borrow reference to the owner's Vault!\")\n        let payment <- vaultRef.withdraw(amount: 10.0)\n        WordHunt.payEntryFee(payment: <-payment)\n    }\n}"
    
    // Player 1 pays
    let payTx1 = Test.Transaction(
        code: payEntryFeeCode,
        signers: [player1],
        arguments: [],
        imports: {
            "WordHunt": contractAddress,
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    let payResult1 = Test.executeTransaction(tx: payTx1)
    Test.expect(payResult1.error == nil, message: payResult1.error?.message ?? "Player 1 pay entry fee failed")
    
    // Player 2 pays
    let payTx2 = Test.Transaction(
        code: payEntryFeeCode,
        signers: [player2],
        arguments: [],
        imports: {
            "WordHunt": contractAddress,
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    let payResult2 = Test.executeTransaction(tx: payTx2)
    Test.expect(payResult2.error == nil, message: payResult2.error?.message ?? "Player 2 pay entry fee failed")
    
    // Verify total prize pool is 20.0
    let finalContractBalance = getContractBalance(contractAddress: contractAddress)
    Test.assertEqual(20.0, finalContractBalance, message: "Contract balance should be 20.0 after two players pay")
    
    Test.log("Two Players Pay Entry Fee Test Passed")
}

// Test prize payout
access(all) fun testPrizePayout() {
    Test.log("Starting test: Prize Payout")
    let player1 = Test.createAccount()
    let player2 = Test.createAccount()
    let contractAddress = deployContract()
    setupPlayerAccount(account: player1)
    setupPlayerAccount(account: player2)
    
    // Both players pay entry fee first
    let payEntryFeeCode = "import WordHunt from \"WordHunt\"\nimport FungibleToken from \"FungibleToken\"\nimport FlowToken from \"FlowToken\"\ntransaction {\n    prepare(signer: &Account) {\n        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)\n            ?? panic(\"Could not borrow reference to the owner's Vault!\")\n        let payment <- vaultRef.withdraw(amount: 10.0)\n        WordHunt.payEntryFee(payment: <-payment)\n    }\n}"
    
    let payTx1 = Test.Transaction(
        code: payEntryFeeCode,
        signers: [player1],
        imports: {
            "WordHunt": contractAddress,
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    Test.executeTransaction(tx: payTx1)
    
    let payTx2 = Test.Transaction(
        code: payEntryFeeCode,
        signers: [player2],
        imports: {
            "WordHunt": contractAddress,
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    Test.executeTransaction(tx: payTx2)
    
    // Get player 1 balance before payout
    let initialPlayer1Balance = getPlayerBalance(playerAddress: player1.address)
    
    // Player 1 claims the prize
    let payoutCode = "import WordHunt from \"WordHunt\"\nimport FungibleToken from \"FungibleToken\"\nimport FlowToken from \"FlowToken\"\ntransaction {\n    prepare(signer: &Account) {\n        let receiverRef = signer.capabilities.get<&FlowToken.Vault{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()\n            ?? panic(\"Could not borrow receiver reference to the recipient's Vault\")\n        let payout <- WordHunt.claimPrize()\n        receiverRef.deposit(from: <-payout)\n    }\n}"
    let payoutTx = Test.Transaction(
        code: payoutCode,
        signers: [player1],
        arguments: [],
        imports: {
            "WordHunt": contractAddress,
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    let payoutResult = Test.executeTransaction(tx: payoutTx)
    Test.expect(payoutResult.error == nil, message: payoutResult.error?.message ?? "Prize payout transaction failed")
    
    // Verify player 1 received the prize
    let finalPlayer1Balance = getPlayerBalance(playerAddress: player1.address)
    Test.assert(finalPlayer1Balance > initialPlayer1Balance + 10.0, message: "Player 1 should have received more than 10.0 Flow as prize")
    
    // Verify contract balance is now 0 (or close to 0 after payout)
    let finalContractBalance = getContractBalance(contractAddress: contractAddress)
    Test.assert(finalContractBalance < 1.0, message: "Contract balance should be minimal after payout")
    
    Test.log("Prize Payout Test Passed")
}

// Test full game flow
access(all) fun testFullGameFlow() {
    Test.log("Starting test: Full Game Flow")
    let player1 = Test.createAccount()
    let player2 = Test.createAccount()
    let contractAddress = deployContract()
    setupPlayerAccount(account: player1)
    setupPlayerAccount(account: player2)
    
    // Get initial balances
    let initialPlayer1Balance = getPlayerBalance(playerAddress: player1.address)
    let initialPlayer2Balance = getPlayerBalance(playerAddress: player2.address)
    let initialContractBalance = getContractBalance(contractAddress: contractAddress)
    
    Test.assertEqual(0.0, initialContractBalance, message: "Initial contract balance should be 0.0")
    
    // Both players pay entry fee
    let payEntryFeeCode = "import WordHunt from \"WordHunt\"\nimport FungibleToken from \"FungibleToken\"\nimport FlowToken from \"FlowToken\"\ntransaction {\n    prepare(signer: &Account) {\n        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)\n            ?? panic(\"Could not borrow reference to the owner's Vault!\")\n        let payment <- vaultRef.withdraw(amount: 10.0)\n        WordHunt.payEntryFee(payment: <-payment)\n    }\n}"
    
    let payTx1 = Test.Transaction(
        code: payEntryFeeCode,
        signers: [player1],
        imports: {
            "WordHunt": contractAddress,
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    Test.executeTransaction(tx: payTx1)
    
    let payTx2 = Test.Transaction(
        code: payEntryFeeCode,
        signers: [player2],
        imports: {
            "WordHunt": contractAddress,
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    Test.executeTransaction(tx: payTx2)
    
    // Verify prize pool is correct
    let midGameContractBalance = getContractBalance(contractAddress: contractAddress)
    Test.assertEqual(20.0, midGameContractBalance, message: "Contract balance should be 20.0 after both players pay")
    
    // Player 1 claims the prize
    let payoutCode = "import WordHunt from \"WordHunt\"\nimport FungibleToken from \"FungibleToken\"\nimport FlowToken from \"FlowToken\"\ntransaction {\n    prepare(signer: &Account) {\n        let receiverRef = signer.capabilities.get<&FlowToken.Vault{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()\n            ?? panic(\"Could not borrow receiver reference to the recipient's Vault\")\n        let payout <- WordHunt.claimPrize()\n        receiverRef.deposit(from: <-payout)\n    }\n}"
    let payoutTx = Test.Transaction(
        code: payoutCode,
        signers: [player1],
        imports: {
            "WordHunt": contractAddress,
            "FungibleToken": FungibleTokenAddress,
            "FlowToken": FlowTokenAddress
        }
    )
    Test.executeTransaction(tx: payoutTx)
    
    // Verify final balances
    let finalPlayer1Balance = getPlayerBalance(playerAddress: player1.address)
    let finalPlayer2Balance = getPlayerBalance(playerAddress: player2.address)
    let finalContractBalance = getContractBalance(contractAddress: contractAddress)
    
    // Player 1 should have gained net positive (prize - entry fee > 0)
    Test.assert(finalPlayer1Balance > initialPlayer1Balance - 10.0, message: "Player 1 should have net positive gain")
    
    // Player 2 should have lost exactly 10.0 (entry fee)
    Test.assertEqual(initialPlayer2Balance - 10.0, finalPlayer2Balance, message: "Player 2 should have lost exactly 10.0")
    
    // Contract should have minimal balance
    Test.assert(finalContractBalance < 1.0, message: "Contract balance should be minimal after game completion")
    
    Test.log("Full Game Flow Test Passed")
}
// TODO: Add more specific test cases as needed:
// - testInvalidEntryFeeAmount
// - testDoubleEntryFeePrevention  
// - testPrizeClaimWithoutEntries
// - testMultipleGameRounds
