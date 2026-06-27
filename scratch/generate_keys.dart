import 'package:cryptography/cryptography.dart';

void main() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateKey = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();
  final publicKeyBytes = publicKey.bytes;
  
  print("--- ED25519 KEYS GENERATED ---");
  print("Private Key (HEX): ${privateKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}");
  print("Public Key (HEX): ${publicKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}");
}
