import 'dart:typed_data';
import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;

class SeedPhraseRoot {
  SeedPhraseRoot(Uint8List seed_, bip32.BIP32 root_)
      : seed = seed_,
        root = root_;
  final Uint8List seed;
  final bip32.BIP32 root;
}

SeedPhraseRoot seedFromMnemonic(String seedPhrase) {
  var seed = bip39.mnemonicToSeed(seedPhrase);
  var root = bip32.BIP32.fromSeed(seed);

  return SeedPhraseRoot(seed, root);
}
