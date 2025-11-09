// lib/utils/encryptor.dart
//
// Streaming AES-256-GCM encrypt/decrypt with optional twist.
// Supports large files (streaming, low memory) with AEAD integrity check.
//
// Header layout (all multi-byte integers big-endian):
// [magic(4)='ENC1'] [salt(16)] [iv(12)]
// [twistFlag(1)=1] [fingerprintLen(1)=32] [fingerprint(32)]
// [originalLen(8)] [chunkSize(4)]
// <ciphertext...>[tag(16)]
//
// Notes:
// - Default KDF is SHA-256(passphrase || salt). Replace with scrypt/argon2 for production.
// - Fingerprint is SHA-256(firstN || lastN || fileSize).
// - Twist key = HMAC-SHA256(derivedKey, fingerprint).
// - Keystream per chunk is HMAC-SHA256(chunkIndex || block).
// - AES-GCM is AEAD; tag appended automatically at encryption.

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';
import 'package:async/async.dart';

class Encryptor {
  // -------------------- Constants --------------------
  static const magic = 'ENC1';
  static const saltLen = 16;
  static const ivLen = 12;
  static const fingerprintLen = 32;
  static const tagLen = 16;
  static const defaultChunkSize = 64 * 1024;

  // -------------------- Helpers --------------------
  static Uint8List _sha256Bytes(List<int> data) =>
      Uint8List.fromList(sha256.convert(data).bytes);

  static Uint8List _randomBytes(int n) {
    final rnd = SecureRandom('Fortuna');
    final seed = Uint8List.fromList(
        List<int>.generate(32, (_) => DateTime.now().microsecond % 256));
    rnd.seed(KeyParameter(seed));
    return rnd.nextBytes(n);
  }

  static Uint8List _deriveKeySha256(String passphrase, Uint8List salt) {
    final b = BytesBuilder();
    b.add(utf8.encode(passphrase));
    b.add(salt);
    return _sha256Bytes(b.toBytes());
  }

  static Uint8List _hmacSha256(Uint8List key, Uint8List data) {
    final h = Hmac(sha256, key);
    return Uint8List.fromList(h.convert(data).bytes);
  }

  static Uint8List _deriveTwistKey(Uint8List derivedKey, Uint8List fingerprint) =>
      _hmacSha256(derivedKey, fingerprint);

  static Uint8List _keystreamForChunk(Uint8List twistKey, int chunkIndex, int length) {
    final out = BytesBuilder();
    int block = 0;
    while (out.length < length) {
      final data = BytesBuilder();
      final c = ByteData(8)..setUint64(0, chunkIndex);
      data.add(c.buffer.asUint8List());
      final b = ByteData(4)..setUint32(0, block);
      data.add(b.buffer.asUint8List());
      out.add(_hmacSha256(twistKey, data.toBytes()));
      block++;
    }
    final ks = out.toBytes();
    return Uint8List.fromList(ks.sublist(0, length));
  }

  static Uint8List _xorBuffers(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length);
    for (var i = 0; i < a.length; i++) out[i] = a[i] ^ b[i];
    return out;
  }

  static Future<Uint8List> _computePlaintextFingerprint(File f) async {
    final len = await f.length();
    final n = len == 0 ? 0 : (len < 2048 ? (len ~/ 2) : 1024);
    final builder = BytesBuilder();
    if (n > 0) {
      final raf = await f.open(mode: FileMode.read);
      try {
        await raf.setPosition(0);
        builder.add(await raf.read(n));
        await raf.setPosition(len - n);
        builder.add(await raf.read(n));
      } finally {
        await raf.close();
      }
    }
    final sizeBytes = ByteData(8)..setUint64(0, len);
    builder.add(sizeBytes.buffer.asUint8List());
    return _sha256Bytes(builder.toBytes());
  }

  // -------------------- File-based Encryption --------------------
  static Future<void> encryptFile({
    required File inputFile,
    required File outputFile,
    required String passphrase,
    void Function(double)? onProgress,
    int chunkSize = defaultChunkSize,
  }) async {
    final salt = _randomBytes(saltLen);
    final iv = _randomBytes(ivLen);
    final key = _deriveKeySha256(passphrase, salt);
    final fingerprint = await _computePlaintextFingerprint(inputFile);
    final twistKey = _deriveTwistKey(key, fingerprint);

    final total = await inputFile.length();
    int processed = 0;

    final reader = ChunkedStreamReader(inputFile.openRead());
    final outSink = outputFile.openWrite();

    final aead = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(key), tagLen * 8, iv, Uint8List(0));
    aead.init(true, params);

    try {
      outSink.add(utf8.encode(magic));
      outSink.add(salt);
      outSink.add(iv);
      outSink.add(Uint8List.fromList([1]));
      outSink.add(Uint8List.fromList([fingerprintLen]));
      outSink.add(fingerprint);
      final origLenBytes = ByteData(8)..setUint64(0, total);
      outSink.add(origLenBytes.buffer.asUint8List());
      final csBytes = ByteData(4)..setUint32(0, chunkSize);
      outSink.add(csBytes.buffer.asUint8List());

      int chunkIndex = 0;
      final outBuffer = Uint8List(chunkSize + tagLen);

      while (true) {
        final List<int> chunkList = await reader.readChunk(chunkSize);
        final Uint8List chunk = Uint8List.fromList(chunkList);
        if (chunk.isEmpty) break;
        processed += chunk.length;

        Uint8List toEncrypt = chunk;
        if (twistKey.isNotEmpty) {
          final ks = _keystreamForChunk(twistKey, chunkIndex, chunk.length);
          toEncrypt = _xorBuffers(Uint8List.fromList(chunk), ks);
        }

        final outLen = aead.processBytes(toEncrypt, 0, toEncrypt.length, outBuffer, 0);
        if (outLen > 0) outSink.add(outBuffer.sublist(0, outLen));

        chunkIndex++;
        onProgress?.call(total > 0 ? processed / total : 0.0);
      }

      final finalLen = aead.doFinal(outBuffer, 0);
      if (finalLen > 0) outSink.add(outBuffer.sublist(0, finalLen));
    } finally {
      try {
        await reader.cancel();
      } catch (_) {}
      await outSink.close();
      for (var i = 0; i < key.length; i++) key[i] = 0;
      for (var i = 0; i < twistKey.length; i++) twistKey[i] = 0;
    }
  }

  // -------------------- File-based Decryption --------------------
  static Future<void> decryptFile({
    required File inputFile,
    required File outputFile,
    required String passphrase,
    void Function(double)? onProgress,
  }) async {
    final raf = await inputFile.open();
    try {
      final magicBytes = await raf.read(4);
      if (utf8.decode(magicBytes) != magic) throw Exception('Invalid file format');

      final salt = Uint8List.fromList(await raf.read(saltLen));
      final iv = Uint8List.fromList(await raf.read(ivLen));
      final twistFlag = (await raf.read(1))[0] == 1;
      final fpLen = (await raf.read(1))[0];
      Uint8List fingerprint = Uint8List(0);
      if (twistFlag) fingerprint = Uint8List.fromList(await raf.read(fpLen));

      final origLen = ByteData.sublistView(Uint8List.fromList(await raf.read(8))).getUint64(0);
      final storedChunkSize =
          ByteData.sublistView(Uint8List.fromList(await raf.read(4))).getUint32(0);

      final headerLen = 4 + saltLen + ivLen + 1 + 1 + (twistFlag ? fpLen : 0) + 8 + 4;
      await raf.close();

      final key = _deriveKeySha256(passphrase, salt);
      final twistKey = twistFlag ? _deriveTwistKey(key, fingerprint) : Uint8List(0);

      final totalFileLen = await inputFile.length();
      final ciphertextLen = totalFileLen - headerLen;
      int processedCipher = 0;

      final reader = ChunkedStreamReader(inputFile.openRead(headerLen));
      final outSink = outputFile.openWrite();

      final aead = GCMBlockCipher(AESEngine());
      aead.init(false, AEADParameters(KeyParameter(key), tagLen * 8, iv, Uint8List(0)));

      int chunkIndex = 0;
      final outBuffer = Uint8List(storedChunkSize + tagLen);

      try {
        while (true) {
          final Uint8List chunk = Uint8List.fromList(await reader.readChunk(storedChunkSize));
          
          if (chunk.isEmpty) break;
          processedCipher += chunk.length;

          // Decrypt
          final outLen = aead.processBytes(chunk, 0, chunk.length, outBuffer, 0);
          Uint8List original = outBuffer.sublist(0, outLen);

          // Apply twist if needed
          if (twistKey.isNotEmpty) {
            original = _xorBuffers(original, _keystreamForChunk(twistKey, chunkIndex, original.length));
          }

          outSink.add(original);
          chunkIndex++;
          onProgress?.call(ciphertextLen > 0 ? processedCipher / ciphertextLen : 0.0);
        }

        final finalLen = aead.doFinal(outBuffer, 0);
        if (finalLen > 0) {
          Uint8List tail = outBuffer.sublist(0, finalLen);
          if (twistKey.isNotEmpty) {
            tail = _xorBuffers(tail, _keystreamForChunk(twistKey, chunkIndex, tail.length));
          }
          outSink.add(tail);
        }
      } finally {
        try {
          await reader.cancel();
        } catch (_) {}
        await outSink.close();
        for (var i = 0; i < key.length; i++) key[i] = 0;
        for (var i = 0; i < twistKey.length; i++) twistKey[i] = 0;
      }
    } catch (e) {
      try {
        await raf.close();
      } catch (_) {}
      rethrow;
    }
  }

  // -------------------- In-memory Helpers --------------------
  static Future<Uint8List> encryptBytes({
    required Uint8List inputBytes,
    required String passphrase,
    void Function(double)? onProgress,
    int chunkSize = defaultChunkSize,
  }) async {
    final tempIn = await File('${Directory.systemTemp.path}/tmp_in').writeAsBytes(inputBytes);
    final tempOut = File('${Directory.systemTemp.path}/tmp_out');

    await encryptFile(
      inputFile: tempIn,
      outputFile: tempOut,
      passphrase: passphrase,
      onProgress: onProgress,
      chunkSize: chunkSize,
    );

    final result = await tempOut.readAsBytes();
    await tempIn.delete();
    await tempOut.delete();
    return result;
  }

  static Future<Uint8List> decryptBytes({
    required Uint8List inputBytes,
    required String passphrase,
    void Function(double)? onProgress,
    int chunkSize = defaultChunkSize,
  }) async {
    final tempIn = await File('${Directory.systemTemp.path}/tmp_in').writeAsBytes(inputBytes);
    final tempOut = File('${Directory.systemTemp.path}/tmp_out');

    await decryptFile(
      inputFile: tempIn,
      outputFile: tempOut,
      passphrase: passphrase,
      onProgress: onProgress,
    );

    final result = await tempOut.readAsBytes();
    await tempIn.delete();
    await tempOut.delete();
    return result;
  }
}
