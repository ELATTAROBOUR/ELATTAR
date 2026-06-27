import 'dart:convert';
import 'package:cryptography/cryptography.dart';

// Helper to convert hex string to Uint8List
List<int> hexToBytes(String hex) {
  final bytes = <int>[];
  for (int i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

// Helper to convert bytes to hex string
String bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void main() async {
  final algorithm = Ed25519();

  // Generated keys from previous step
  final privateKeyHex = "964c159eebbddb15fa5f130b2d8f8227fce3319bd304246f1de2ae470dac37f0";
  final publicKeyHex = "69042be4b918cea159328a6e86799a02b835b80a8c2bf93fa7f657233fef3a51";

  // 1. Reconstruct Private Key and KeyPair
  final privateKeyBytes = hexToBytes(privateKeyHex);
  final keyPair = SimpleKeyPairData(
    privateKeyBytes,
    publicKey: SimplePublicKey(hexToBytes(publicKeyHex), type: KeyPairType.ed25519),
    type: KeyPairType.ed25519,
  );

  // 2. Message to sign
  final messageStr = "TEST_HWID|2027-06-19";
  final messageBytes = utf8.encode(messageStr);

  // 3. Sign message
  final signature = await algorithm.sign(messageBytes, keyPair: keyPair);
  final signatureHex = bytesToHex(signature.bytes);
  print("Signature HEX: $signatureHex");

  // 4. Verify signature using Public Key only
  final publicKey = SimplePublicKey(hexToBytes(publicKeyHex), type: KeyPairType.ed25519);
  
  final sigToVerify = Signature(
    hexToBytes(signatureHex),
    publicKey: publicKey,
  );

  final isVerified = await algorithm.verify(messageBytes, signature: sigToVerify);
  print("Verification result: $isVerified");
}
