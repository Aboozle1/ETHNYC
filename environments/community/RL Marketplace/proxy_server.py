from flask import Flask, jsonify, request
import time
import uuid
import re
from flow_client import flow_client

app = Flask(__name__)

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
        
        # Step 3: Extract board from prompt
        board = extract_board_from_prompt(prompt)
        
        if board is None:
            print("❌ Could not extract board from prompt, using dummy response")
            dummy_words = "CAT, DOG, BIRD, FISH"
        else:
            # Step 6: Query smart contract with extracted board
            solutions = flow_client.get_word_hunt_solutions(board)
            
            if solutions is None or len(solutions) == 0:
                print("❌ No solutions returned from smart contract, using fallback")
                dummy_words = "NO, SOLUTIONS, FOUND"
            else:
                # Step 7: Format the contract response
                dummy_words = ", ".join(solutions)
                print(f"✅ Got {len(solutions)} solutions from smart contract: {dummy_words}")
        
        # Create OpenAI-compatible response structure
        choices = []
        for i in range(n):
            choices.append({
                "text": dummy_words,
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
                "completion_tokens": len(dummy_words.split()),
                "total_tokens": len(prompt.split()) + len(dummy_words.split())
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
