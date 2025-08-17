from flask import Flask, jsonify, request
import time
import uuid
import re
import os
import requests
from flow_client import flow_client

app = Flask(__name__)

# Constants for Nous API
NOUS_API_URL = "https://inference-api.nousresearch.com/v1/chat/completions" # Use the chat endpoint
NOUS_MODEL = "DeepHermes-3-Llama-3-8B-Preview"


def extract_board_from_prompt(prompt):
    """Extract the 4x4 board from the Atropos prompt text.
    
    Args:
        prompt (str): The full prompt text from Atropos
        
    Returns:
        list: 4x4 board as list of lists, or None if not found
    """
    try:
        # Look for the board pattern - 4 lines with letters separated by spaces
        # This regex finds 4 consecutive lines that look like "A B C D"
        board_pattern = r'([A-Z]\s+[A-Z]\s+[A-Z]\s+[A-Z])\s*\n([A-Z]\s+[A-Z]\s+[A-Z]\s+[A-Z])\s*\n([A-Z]\s+[A-Z]\s+[A-Z]\s+[A-Z])\s*\n([A-Z]\s+[A-Z]\s+[A-Z]\s+[A-Z])'
        
        match = re.search(board_pattern, prompt)
        if match:
            board = []
            for i in range(1, 5):  # Groups 1-4 from regex
                row_text = match.group(i)
                row = row_text.split()  # Split on whitespace
                board.append(row)
            
            print(f"✅ Extracted board:")
            for row in board:
                print(f"  {' '.join(row)}")
            
            return board
        else:
            print("❌ No board pattern found in prompt")
            return None
            
    except Exception as e:
        print(f"❌ Error extracting board: {e}")
        return None

def extract_board_id(prompt):
    """Extract the Board-ID from the prompt."""
    try:
        match = re.search(r"Board-ID: ([\w-]+)", prompt)
        if match:
            board_id = match.group(1)
            print(f"✅ Extracted Board-ID: {board_id}")
            return board_id
        else:
            print("❌ No Board-ID found in prompt")
            return None
    except Exception as e:
        print(f"❌ Error extracting Board-ID: {e}")
        return None

DEEP_HERMES_SYSTEM_PROMPT = "You are a puzzle-solving AI. Your task is to find all valid English words of three or more letters in the provided 4x4 grid of letters. Words can be formed from letters connecting horizontally, vertically, or diagonally. Letters can be used more than once in a single word if the path loops. List the words you find as a comma-separated list."

def clean_prompt(prompt: str) -> str:
    """Remove special tokens from the Atropos prompt."""
    # This regex removes tokens like <|begin_of_text|>, <|eot_id|>, etc.
    cleaned_prompt = re.sub(r'<\|.*?\|>', '', prompt)
    return cleaned_prompt.strip()

def get_solutions_from_nous(prompt):
    """Call the Nous API to get word hunt solutions with retry logic."""
    api_key = os.getenv("NOUS_API_KEY")
    if not api_key:
        print("⚠️ NOUS_API_KEY not found. Returning mock data.")
        return ["NOUS", "API", "KEY", "MISSING"]

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    # Clean the prompt before sending it to the API
    cleaned_prompt = clean_prompt(prompt)
    
    data = {
        "model": NOUS_MODEL,
        "messages": [
            {"role": "user", "content": cleaned_prompt}
        ],
        "max_tokens": 150,
        "temperature": 0.5
    }
    
    # Add retry logic to handle intermittent API failures
    for attempt in range(2): # Try up to 2 times
        try:
            print(f"Constructed Nous API payload (Attempt {attempt + 1}): {data}")
            response = requests.post(NOUS_API_URL, headers=headers, json=data, timeout=30)
            response.raise_for_status() # Raise an exception for bad status codes
            
            completion = response.json()
            # Chat endpoint returns content in a message object
            text_response = completion['choices'][0]['message']['content']
            
            # Clean and split the response
            words = [word.strip() for word in text_response.split(',') if word.strip()]
            print(f"✅ Got {len(words)} solutions from Nous API: {words}")
            return words # Success, exit the loop
            
        except requests.exceptions.RequestException as e:
            print(f"❌ Error calling Nous API on attempt {attempt + 1}: {e}")
            if attempt < 1:
                print("Retrying in 1 second...")
                time.sleep(1)
            else:
                print("❌ Max retries reached. API call failed.")
                return None
    
    return None # Should not be reached, but for safety

@app.route('/')
def health_check():
    """A simple health check endpoint to confirm the server is running."""
    return jsonify({"status": "ok", "message": "Proxy server is running."})

@app.route('/v1/completions', methods=['POST'])
def completions():
    """OpenAI-compatible completions endpoint that Atropos will call."""
    try:
        # Get the request data from Atropos
        data = request.get_json()
        
        if not data or 'prompt' not in data:
            return jsonify({"error": "Missing prompt in request"}), 400
        
        prompt = data['prompt']
        n = data.get('n', 1)  # Number of completions to generate
        max_tokens = data.get('max_tokens', 100)
        
        print(f"🔍 Received prompt from Atropos:")
        print(f"Prompt length: {len(prompt)} chars")
        print(f"Number of completions requested: {n}")
        print("=" * 50)
        print(prompt)
        print("=" * 50)
        
        # Step 1: Extract Board-ID from prompt
        board_id = extract_board_id(prompt)
        
        # Step 2: Call the Oracle (Nous API) to get solutions
        solutions = get_solutions_from_nous(prompt)
        
        if solutions is None:
            # Handle API failure
            solutions = ["API", "CALL", "FAILED"]
        
        # Step 3: Submit the solutions to the smart contract
        transaction_id = flow_client.execute_transaction(
            "cadence/transactions/submit_solutions.cdc",
            arguments=[board_id or "unknown-board-id", solutions] # Use a default board_id if None
        )
        
        if transaction_id:
            print(f"✅ Solutions submitted on-chain. Transaction ID: {transaction_id}")
        else:
            print("❌ Failed to submit solutions on-chain.")
            
        # Format the response using the solutions from the API
        response_text = ", ".join(solutions)
        
        # Create OpenAI-compatible response structure
        choices = []
        for i in range(n):
            choices.append({
                "text": response_text,
                "index": i,
                "logprobs": None,
                "finish_reason": "stop"
            })
        
        response = {
            "id": f"cmpl-{uuid.uuid4().hex[:8]}",
            "object": "text_completion",
            "created": int(time.time()),
            "model": "word-hunt-smart-contract",
            "choices": choices,
            "usage": {
                "prompt_tokens": len(prompt.split()),
                "completion_tokens": len(response_text.split()),
                "total_tokens": len(prompt.split()) + len(response_text.split())
            }
        }
        
        print(f"✅ Returning response with {len(choices)} choices")
        return jsonify(response)
        
    except Exception as e:
        print(f"❌ Error in completions endpoint: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    # Running on port 8080, can be configured as needed.
    app.run(host='0.0.0.0', port=8080, debug=True)
