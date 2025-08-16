"""
Flow Blockchain Client for WordHunt Smart Contract Integration
"""
import subprocess
import json
import os
from typing import List, Optional


class FlowClient:
    """Client for interacting with Flow blockchain and WordHunt smart contract."""
    
    def __init__(self, network="emulator", contract_address=None):
        """
        Initialize Flow client.
        
        Args:
            network (str): Flow network to connect to ("emulator", "testnet", "mainnet")
            contract_address (str): Address where WordHunt contract is deployed
        """
        self.network = network
        self.contract_address = contract_address
        
        # Set the working directory to the rlproject folder for Flow CLI commands
        self.flow_project_dir = os.path.join(
            os.path.dirname(__file__), 
            "rlproject"
        )
        
        print(f"🔗 FlowClient initialized:")
        print(f"  Network: {network}")
        print(f"  Contract Address: {contract_address}")
        print(f"  Project Directory: {self.flow_project_dir}")
    
    def execute_script(self, script_path: str, arguments: List = None) -> Optional[dict]:
        """
        Execute a Cadence script on the Flow blockchain.
        
        Args:
            script_path (str): Path to the .cdc script file (relative to rlproject)
            arguments (List): List of arguments to pass to the script
            
        Returns:
            dict: Script result or None if failed
        """
        try:
            # Build the flow script command
            cmd = ["flow", "scripts", "execute", script_path]
            
            # Add network flag
            if self.network != "emulator":
                cmd.extend(["--network", self.network])
            
            # Add arguments if provided
            if arguments:
                for arg in arguments:
                    cmd.extend(["--arg", str(arg)])
            
            print(f"🔍 Executing Flow script: {' '.join(cmd)}")
            
            # Execute the command in the rlproject directory
            result = subprocess.run(
                cmd,
                cwd=self.flow_project_dir,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                # Try to parse JSON output
                try:
                    output = json.loads(result.stdout.strip())
                    print(f"✅ Script executed successfully")
                    return output
                except json.JSONDecodeError:
                    # If not JSON, return raw output
                    print(f"✅ Script executed successfully (raw output)")
                    return {"raw_output": result.stdout.strip()}
            else:
                print(f"❌ Script execution failed:")
                print(f"  Return code: {result.returncode}")
                print(f"  STDOUT: {result.stdout}")
                print(f"  STDERR: {result.stderr}")
                return None
                
        except subprocess.TimeoutExpired:
            print("❌ Script execution timed out")
            return None
        except Exception as e:
            print(f"❌ Error executing script: {e}")
            return None
    
    def get_word_hunt_solutions(self, board: List[List[str]]) -> Optional[List[str]]:
        """
        Query the WordHunt smart contract for solutions to a given board.
        
        Args:
            board (List[List[str]]): 4x4 board as list of lists
            
        Returns:
            List[str]: List of valid words, or None if failed
        """
        try:
            # Flatten the board into a single array for the script
            flattened_board = []
            for row in board:
                flattened_board.extend(row)
            
            print(f"🎯 Querying smart contract for board solutions:")
            print(f"  Board: {flattened_board}")
            
            # Execute the get_board_solutions.cdc script
            result = self.execute_script(
                "cadence/scripts/get_board_solutions.cdc",
                arguments=[flattened_board]
            )
            
            if result is None:
                print("❌ Failed to get solutions from smart contract")
                return None
            
            # Extract words from the result
            # The exact format will depend on how your get_solutions.cdc script returns data
            if isinstance(result, dict) and "raw_output" in result:
                # Handle raw output format
                words_str = result["raw_output"]
                words = [word.strip() for word in words_str.split(",") if word.strip()]
            elif isinstance(result, list):
                # Handle JSON array format
                words = result
            else:
                # Handle other formats
                words = []
            
            print(f"✅ Found {len(words)} solutions: {words}")
            return words
            
        except Exception as e:
            print(f"❌ Error getting solutions: {e}")
            return None
    
    def test_connection(self) -> bool:
        """
        Test connection to Flow network.
        
        Returns:
            bool: True if connection successful, False otherwise
        """
        try:
            # Test with a simple script execution
            cmd = ["flow", "version"]
            result = subprocess.run(
                cmd,
                cwd=self.flow_project_dir,
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                print(f"✅ Flow CLI connection test passed")
                print(f"  Version: {result.stdout.strip()}")
                return True
            else:
                print(f"❌ Flow CLI connection test failed")
                return False
                
        except Exception as e:
            print(f"❌ Error testing Flow connection: {e}")
            return False


# Create a default client instance
flow_client = FlowClient(network="emulator")
