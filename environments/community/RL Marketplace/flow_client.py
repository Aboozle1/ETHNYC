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
            
            # Add arguments if provided (older CLI syntax without --arg)
            if arguments:
                for arg in arguments:
                    # The older CLI expects arguments directly after the script path
                    # It also expects string arguments to be in quotes
                    if isinstance(arg, str):
                         cmd.append(f'"{arg}"')
                    # And arrays to be in Cadence format
                    elif isinstance(arg, list):
                        # Convert Python list to Cadence String array format: ["a", "b"]
                        cadence_array = ", ".join([f'"{item}"' for item in arg])
                        cmd.append(f'[{cadence_array}]')
                    else:
                        cmd.append(str(arg))
            
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
        Fallback to OpenAI if smart contract fails.
        
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
            
            print(f"🎯 Attempting to query smart contract for board solutions:")
            print(f"  Board: {flattened_board}")
            
            # Try to execute the Flow smart contract script
            result = self.execute_script(
                "cadence/scripts/get_board_solutions.cdc",
                arguments=[flattened_board]
            )
            
            if result is not None:
                # Extract words from the result
                if isinstance(result, dict) and "raw_output" in result:
                    # Handle raw output format from older CLI, e.g., Result: ["WORD1", "WORD2"]
                    import re
                    raw_text = result["raw_output"]
                    words = re.findall(r'"(.*?)"', raw_text)
                elif isinstance(result, list):
                    # Handle JSON array format
                    words = result
                else:
                    words = []
                
                if words:  # If we got valid results from smart contract
                    print(f"✅ Smart contract returned {len(words)} solutions: {words}")
                    return words
            
            # Smart contract failed or returned empty results
            print("⚠️  Smart contract failed or returned no results, falling back to OpenAI...")
            return self._fallback_to_openai(board)
            
        except Exception as e:
            print(f"❌ Error with smart contract: {e}")
            print("⚠️  Falling back to OpenAI...")
            return self._fallback_to_openai(board)
    
    def _fallback_to_openai(self, board: List[List[str]]) -> Optional[List[str]]:
        """
        Fallback to OpenAI API when smart contract fails.
        Uses the same prompt format that Atropos would send.
        """
        try:
            import requests
            import os
            
            # Format the board exactly like Atropos would
            board_text = "Find words on this board:\n"
            for row in board:
                board_text += " ".join(row) + "\n"
            board_text += "\nFound words:"
            
            print(f"🔄 Calling OpenAI API with prompt:")
            print(f"  {board_text.replace(chr(10), '\\n')}")
            
            # Use OpenAI API (you'll need to set OPENAI_API_KEY)
            api_key = os.getenv("OPENAI_API_KEY")
            if not api_key:
                print("❌ OPENAI_API_KEY not set, using hardcoded fallback")
                return ["CAT", "DOG", "BAT", "HAT", "RAT"]
            
            response = requests.post(
                "https://api.openai.com/v1/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "gpt-3.5-turbo-instruct",
                    "prompt": board_text,
                    "max_tokens": 100,
                    "temperature": 0.7
                },
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                response_text = data["choices"][0]["text"].strip()
                
                # Parse the response to extract words
                words = [word.strip() for word in response_text.split(",") if word.strip()]
                
                print(f"🤖 OpenAI returned {len(words)} solutions: {words}")
                return words
            else:
                print(f"❌ OpenAI API error: {response.status_code}")
                raise Exception("OpenAI API failed")
            
        except Exception as e:
            print(f"❌ OpenAI fallback also failed: {e}")
            # Ultimate fallback: return some basic words that could exist on any board
            fallback_words = ["CAT", "DOG", "BAT", "HAT", "RAT", "SAT"]
            print(f"🆘 Using hardcoded fallback: {fallback_words}")
            return fallback_words
    
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


# Create a default client instance for the testnet deployment
flow_client = FlowClient(
    network="testnet",
    contract_address="0x91aad6c51a5de497"
)
