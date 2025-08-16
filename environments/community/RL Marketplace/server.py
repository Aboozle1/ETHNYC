from flask import Flask, request, jsonify
import hashlib
# We will use the ecdsa library for cryptographic signatures.
# You may need to install it: pip3 install ecdsa
import ecdsa

app = Flask(__name__)

# This would be loaded securely in a real application,
# but for the hackathon, we'll define it here.
# This is the private key for our server's signing identity.
SERVER_PRIVATE_KEY_HEX = "bf67b2c645ad0f354e70924fa86b84ff653ece165e9c12ecc34f04e73b8ea47d"
SIGNING_KEY = ecdsa.SigningKey.from_string(bytes.fromhex(SERVER_PRIVATE_KEY_HEX), curve=ecdsa.SECP256k1, hashfunc=hashlib.sha256)

@app.route('/generate_board', methods=['GET'])
def generate_board():
    # TODO: Implement actual board generation from word_hunt_env.py
    board_data = "P,L,A,C,E,H,O,L,D,E,R,B,O,A,R,D"
    board_hash = hashlib.sha256(board_data.encode()).hexdigest()
    
    return jsonify({
        "board": board_data,
        "board_hash": board_hash
    })

@app.route('/sign_score', methods=['POST'])
def sign_score():
    data = request.json
    board_hash = data.get('board_hash')
    score = data.get('score')
    player_address = data.get('player_address')

    if not all([board_hash, score, player_address]):
        return jsonify({"error": "Missing data"}), 400

    # Create the message to be signed.
    # It's crucial that this format matches what the smart contract expects.
    message = f"{board_hash}:{score}:{player_address}".encode()

    # Sign the message with the private key.
    signature = SIGNING_KEY.sign(message).hex()

    return jsonify({
        "message": message.decode(),
        "signature": signature
    })

if __name__ == '__main__':
    app.run(debug=True, port=5001)
