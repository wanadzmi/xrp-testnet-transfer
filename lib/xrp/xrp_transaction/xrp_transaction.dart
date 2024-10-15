import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:hex/hex.dart';
import 'package:web3dart/crypto.dart';
import '../xrp.dart';
import 'xrp_definitions.dart';
import 'xrp_ordinal.dart';

Uint8List decodeClassicAddress(String classicAddress) {
  return _decode(classicAddress, _classicAddressPrefix);
}

Uint8List _decode(String classicAddress, List<dynamic> prefix) {
  final decoded = xrpBaseCodec.decode(classicAddress);
  return decoded.sublist(prefix.length, decoded.length - 4);
}

bool isXrpXAddress(String xAddress) {
  try {
    xaddressToClassicAddress(xAddress);
    return true;
  } catch (e) {
    return false;
  }
}

String encodeXrpJson(Map<dynamic, dynamic> sampleXrpJson) {
  final xrpTransactionPrefix = [83, 84, 88, 0];

  if (isXrpXAddress(sampleXrpJson['Destination'] as String)) {
    final destinationXDetails =
        xaddressToClassicAddress(sampleXrpJson['Destination'] as String);
    sampleXrpJson['Destination'] = destinationXDetails['classicAddress'];
    sampleXrpJson['DestinationTag'] = destinationXDetails['tag'];
  } else if (isXrpXAddress(sampleXrpJson['Account'] as String)) {
    final sourceXDetails =
        xaddressToClassicAddress(sampleXrpJson['Account'] as String);
    sampleXrpJson['Account'] = sourceXDetails['classicAddress'];
    sampleXrpJson['SourceTag'] = sourceXDetails['tag'];
  }

  var xrpJson = sampleXrpJson.keys.toList();
  var sorted = xrpJson.map((e) {
    return xrpOrdinal[e];
  }).toList()
    ..removeWhere((f) {
      return f == null || f['isSerialized'] == null;
    })
    ..sort((a, b) {
      return (a!['ordinal']! as num).toInt() - (b!['ordinal']! as num).toInt();
    });
  final fields = rippleDefinitions['FIELDS'] as List;
  var trxFieldInfo = <dynamic, dynamic>{};
  for (final field in fields) {
    final key = field[0];
    final value = field[1];
    trxFieldInfo[key] = value;
  }

  var serializer = <dynamic>[];

  for (var i = 0; i < sorted.length; i++) {
    final sortedKeys = sorted[i]!['name'];

    trxFieldInfo[sortedKeys]['ordinal'] = sorted[i]!['ordinal'];
    trxFieldInfo[sortedKeys]['name'] = sorted[i]!['name'];
    trxFieldInfo[sortedKeys]['nth'] = sorted[i]!['nth'];

    final typeCode =
        rippleDefinitions['TYPES'][trxFieldInfo[sortedKeys]['type']] as int;
    final fieldCode = trxFieldInfo[sortedKeys]['nth'] as int;

    var isVariableEncoded = trxFieldInfo[sortedKeys]['isVLEncoded'] as bool;
    var associatedValue = Uint8List(0);

    if (sortedKeys == 'TransactionType') {
      final transType =
          rippleDefinitions['TRANSACTION_TYPES'][sampleXrpJson[sortedKeys]];
      associatedValue = _toUint16(transType as int);
    } else if (trxFieldInfo[sortedKeys]['type'] == 'UInt32') {
      associatedValue = _toUint32(sampleXrpJson[sortedKeys] as int);
    } else if (trxFieldInfo[sortedKeys]['type'] == 'UInt16') {
      associatedValue = _toUint32(sampleXrpJson[sortedKeys] as int);
    } else if (trxFieldInfo[sortedKeys]['type'] == 'Amount') {
      associatedValue =
          _toAmount(int.parse(sampleXrpJson[sortedKeys] as String));
    } else if (trxFieldInfo[sortedKeys]['type'] == 'AccountID') {
      associatedValue =
          decodeClassicAddress(sampleXrpJson[sortedKeys] as String);
    } else if (trxFieldInfo[sortedKeys]['type'] == 'Blob') {
      associatedValue =
          Uint8List.fromList(HEX.decode(sampleXrpJson[sortedKeys] as String));
    }

    var header = <int>[];
    if (typeCode < 16) {
      if (fieldCode < 16) {
        header.add(typeCode << 4 | fieldCode);
      } else {
        header
          ..add(typeCode << 4)
          ..add(fieldCode);
      }
    } else if (fieldCode < 16) {
      header.addAll([fieldCode, typeCode]);
    } else {
      header.addAll([0, typeCode, fieldCode]);
    }

    serializer.addAll(header);

    if (isVariableEncoded) {
      final byteObject = [...associatedValue];

      var lengthPrefix = _encodeVariableLengthPrefix(byteObject.length);

      serializer += lengthPrefix;
      serializer += byteObject;
    } else {
      serializer.addAll(associatedValue);
    }
  }
  serializer.insertAll(0, xrpTransactionPrefix);
  return HEX.encode(List<int>.from(serializer)).toUpperCase();
}

const int _MAX_SINGLE_BYTE_LENGTH = 192;
const int _MAX_DOUBLE_BYTE_LENGTH = 12481;
const int _MAX_LENGTH_VALUE = 918744;
const int _MAX_SECOND_BYTE_VALUE = 240;

Uint8List _encodeVariableLengthPrefix(int length) {
  var localLength = length;

  if (localLength <= _MAX_SINGLE_BYTE_LENGTH) {
    return Uint8List.fromList([localLength]);
  } else if (localLength < _MAX_DOUBLE_BYTE_LENGTH) {
    localLength -= _MAX_SINGLE_BYTE_LENGTH + 1;
    final byte1 = ((_MAX_SINGLE_BYTE_LENGTH + 1) + (localLength >> 8)).toByte();
    final byte2 = (localLength & 0xFF).toByte();
    return Uint8List.fromList([byte1, byte2]);
  } else if (localLength <= _MAX_LENGTH_VALUE) {
    localLength -= _MAX_DOUBLE_BYTE_LENGTH;
    final byte1 = ((_MAX_SECOND_BYTE_VALUE + 1) + (localLength >> 16)).toByte();
    final byte2 = ((localLength >> 8) & 0xFF).toByte();
    final byte3 = (localLength & 0xFF).toByte();
    return Uint8List.fromList([byte1, byte2, byte3]);
  }
  throw Exception(
    'VariableLength field must be <= $_MAX_LENGTH_VALUE bytes long',
  );
}

extension IntToByte on int {
  int toByte() {
    return this & 0xff;
  }
}

Uint8List _toUint16(int value) {
  var buffer = ByteData(2)..setUint16(0, value);
  return buffer.buffer.asUint8List();
}

Map<dynamic, dynamic> signXrpTransaction(
    String privateKeyHex, Map<dynamic, dynamic> xrpTransactionJson) {
  final msg = encodeXrpJson(xrpTransactionJson);

  var firstsha512 = sha512.convert(HEX.decode(msg)).bytes;
  firstsha512 = firstsha512.sublist(0, firstsha512.length ~/ 2);

  final signature = _encodeSignatureToDER(sign(Uint8List.fromList(firstsha512),
      Uint8List.fromList(HEX.decode(privateKeyHex))));

  xrpTransactionJson['TxnSignature'] = signature;
  return xrpTransactionJson;
}

Uint8List _bigIntToUint8List(BigInt number) {
  var bytes =
      number.toRadixString(16).padLeft((number.bitLength + 7) >> 3 << 1, '0');
  return Uint8List.fromList(List<int>.generate(bytes.length ~/ 2,
      (i) => int.parse(bytes.substring(i * 2, i * 2 + 2), radix: 16)));
}

String _encodeSignatureToDER(MsgSignature signature) {
  var r = Uint8List.fromList(_bigIntToUint8List(signature.r));
  var s = Uint8List.fromList(_bigIntToUint8List(signature.s));

  if ((r[0] & 0x80) == 0x80) {
    r = Uint8List.fromList([0] + r);
  }
  if ((s[0] & 0x80) == 0x80) {
    s = Uint8List.fromList([0] + s);
  }

  final sig = Uint8List.fromList(
      ([0x30] + _bigIntToUint8List(BigInt.from(r.length + s.length + 4))) +
          ([0x02] + _bigIntToUint8List(BigInt.from(r.length))) +
          r +
          ([0x02] + _bigIntToUint8List(BigInt.from(s.length))) +
          s);

  return HEX.encode(sig).toUpperCase();
}

Uint8List _toUint32(int value) {
  var buffer = ByteData(4)..setUint32(0, value);
  return buffer.buffer.asUint8List();
}

Uint8List _toAmount(int value) {
  const POS_SIGN_BIT_MASK = 0x4000000000000000;
  final valueWithPosBit = value | POS_SIGN_BIT_MASK;
  var buffer = ByteData(8)..setInt64(0, valueWithPosBit);
  return buffer.buffer.asUint8List();
}

final _prefixBytesMain = Uint8List.fromList([0x05, 0x44]);
final _prefixBytesTest = Uint8List.fromList([0x04, 0x93]);

Map<dynamic, dynamic> xaddressToClassicAddress(String xAddress) {
  var decoded = xrpBaseCodec.decode(xAddress);
  decoded = decoded.sublist(0, decoded.length - 4);
  var isXTestNet = _isTestXAddress(decoded.sublist(0, 2));
  final classicAddressByte = decoded.sublist(2, 22);
  final tag = _getTagFromBuffer(decoded.sublist(22));
  final classicAddress = encodeClassicAddress(classicAddressByte);
  return {
    'classicAddress': classicAddress,
    'is_test_network': isXTestNet,
    'tag': tag,
  };
}

const _classicAddressLength = 20;
final _classicAddressPrefix = [0x0];

String encodeClassicAddress(Uint8List bytestring) {
  return _encode(bytestring, _classicAddressPrefix, _classicAddressLength);
}

String _encode(Uint8List bytestring, List<int> prefix, int expectedLength) {
  if (bytestring.length != expectedLength) {
    throw Exception('unexpected_payload_length: len(bytestring) does '
        'not match expected_length.Ensure that the bytes are a bytestring.');
  }

  final payload = prefix + bytestring;
  final computedCheckSum = sha256
      .convert(sha256.convert([0, ...bytestring]).bytes)
      .bytes
      .sublist(0, 4);
  return xrpBaseCodec
      .encode(Uint8List.fromList([...payload, ...computedCheckSum]));
}

int? _getTagFromBuffer(Uint8List buffer) {
  var flag = buffer[0];
  if (flag >= 2) {
    throw Exception('Unsupported X-Address');
  }
  if (flag == 1) {
    return buffer[1] +
        buffer[2] * 0x100 +
        buffer[3] * 0x10000 +
        buffer[4] * 0x1000000;
  }

  if (flag != 0) {
    throw Exception('Flag must be zero to indicate no tag');
  }

  if (HEX.decode('0000000000000000') != buffer.sublist(1, 9)) {
    throw Exception('Remaining bytes must be zero');
  }

  return null;
}

bool _isTestXAddress(Uint8List prefix) {
  if (seqEqual(_prefixBytesMain, prefix)) {
    return false;
  } else if (seqEqual(_prefixBytesTest, prefix)) {
    return true;
  }
  throw Exception('Invalid X-Address: bad prefix');
}

bool seqEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
