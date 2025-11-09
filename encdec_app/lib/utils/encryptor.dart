import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';

class Encryptor {
  static const magicV2 = 'ENC2';
  static const saltLen = 16;
  static const ivLen = 12;
  static const defaultChunkSize = 64 * 1024;
  static const pbkdf2Iterations = 100000;

  static Future<void> encryptFile({
    required File inputFile,
    required File outputFile,
    required String passphrase,
    void Function(double)? onProgress,
  }) async {
    await _runInIsolate(
      inputFile: inputFile,
      outputFile: outputFile,
      passphrase: passphrase,
      onProgress: onProgress,
      isEncrypting: true,
    );
  }

  static Future<void> decryptFile({
    required File inputFile,
    required File outputFile,
    required String passphrase,
    void Function(double)? onProgress,
  }) async {
    await _runInIsolate(
      inputFile: inputFile,
      outputFile: outputFile,
      passphrase: passphrase,
      onProgress: onProgress,
      isEncrypting: false,
    );
  }

  static Future<void> _runInIsolate({
    required File inputFile,
    required File outputFile,
    required String passphrase,
    void Function(double)? onProgress,
    required bool isEncrypting,
  }) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _isolateEntryPoint,
      {
        'sendPort': receivePort.sendPort,
        'inputFile': inputFile.path,
        'outputFile': outputFile.path,
        'passphrase': passphrase,
        'isEncrypting': isEncrypting,
      },
      onError: receivePort.sendPort,
    );

    await for (final message in receivePort) {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is String && message.startsWith('Error:')) {
        isolate.kill(priority: Isolate.immediate);
        throw Exception(message.substring(6));
      } else if (message == 'Done') {
        isolate.kill(priority: Isolate.immediate);
        break;
      }
    }
  }

  static void _isolateEntryPoint(Map<String, dynamic> args) async {
    final sendPort = args['sendPort'] as SendPort;
    try {
      if (args['isEncrypting']) {
        await _encryptFileInternalV2(
          inputFile: File(args['inputFile']),
          outputFile: File(args['outputFile']),
          passphrase: args['passphrase'],
          sendPort: sendPort,
        );
      } else {
        await _decryptFileInternal(
          inputFile: File(args['inputFile']),
          outputFile: File(args['outputFile']),
          passphrase: args['passphrase'],
          sendPort: sendPort,
        );
      }
      sendPort.send('Done');
    } catch (e, s) {
      sendPort.send('Error: $e\n$s');
    }
  }

  static Future<SecretKey> _deriveKeyPbkdf2(
      String passphrase, List<int> salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return await pbkdf2.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
  }

  static Future<SecretKey> _deriveTwistKey(
      SecretKey masterKey, String filename, int fileSize) async {
    final hmac = Hmac.sha256();
    final filenameBytes = utf8.encode(filename);
    final sizeBytes = ByteData(8)..setUint64(0, fileSize);
    final message = <int>[...filenameBytes, ...sizeBytes.buffer.asUint8List()];
    final signature = await hmac.calculateMac(
      message,
      secretKey: masterKey,
    );
    return SecretKey(signature.bytes);
  }

  static Future<Uint8List> _xorWithKeystream(
      Uint8List data, SecretKey twistKey, int chunkIndex) async {
    final chacha = Cryptography.instance.chacha20(macAlgorithm: MacAlgorithm.empty);
    final nonce = List.filled(12, 0);
    ByteData.view(Uint8List.fromList(nonce).buffer).setUint32(0, chunkIndex);
    final secretBox = await chacha.encrypt(
      data,
      secretKey: twistKey,
      nonce: nonce,
    );
    return Uint8List.fromList(secretBox.cipherText);
  }

  static Future<void> _encryptFileInternalV2({
    required File inputFile,
    required File outputFile,
    required String passphrase,
    required SendPort sendPort,
  }) async {
    final salt = SecretKeyData.random(length: saltLen).bytes;
    final iv = SecretKeyData.random(length: ivLen).bytes;
    final key = await _deriveKeyPbkdf2(passphrase, salt, pbkdf2Iterations);

    final filename = inputFile.path.split(Platform.pathSeparator).last;
    final fileSize = await inputFile.length();

    final outSink = outputFile.openWrite();

    final algorithm = AesGcm.with256bits();

    try {
      outSink.add(utf8.encode(magicV2));
      outSink.add(salt);
      outSink.add(iv);
      final iterBytes = ByteData(4)..setUint32(0, pbkdf2Iterations);
      outSink.add(iterBytes.buffer.asUint8List());
      final fnLenBytes = ByteData(2)..setUint16(0, filename.length);
      outSink.add(fnLenBytes.buffer.asUint8List());
      outSink.add(utf8.encode(filename));
      final sizeBytes = ByteData(8)..setUint64(0, fileSize);
      outSink.add(sizeBytes.buffer.asUint8List());

      final twistKey = await _deriveTwistKey(key, filename, fileSize);

      final reader = inputFile.openRead();
      int chunkIndex = 0;
      int processed = 0;

      await for (final chunk in reader) {
        final twisted = await _xorWithKeystream(Uint8List.fromList(chunk), twistKey, chunkIndex);
        final secretBox = await algorithm.encrypt(
          twisted,
          secretKey: key,
          nonce: iv,
        );
        outSink.add(secretBox.cipherText);
        outSink.add(secretBox.mac.bytes);

        chunkIndex++;
        processed += chunk.length;
        sendPort.send(fileSize > 0 ? processed / fileSize : 0.0);
      }
    } finally {
      await outSink.close();
    }
  }

  static Future<void> _decryptFileInternal(
    {
    required File inputFile,
    required File outputFile,
    required String passphrase,
    required SendPort sendPort,
  }) async {
    final raf = await inputFile.open();
    IOSink? outSink;
    try {
      final magicBytes = await raf.read(4);
      final magic = utf8.decode(magicBytes);

      if (magic != magicV2) {
        throw Exception('Invalid or unsupported file format');
      }

      final salt = await raf.read(saltLen);
      final iv = await raf.read(ivLen);
      final iterations = (await raf.read(4)).buffer.asByteData().getUint32(0);
      final fnLen = (await raf.read(2)).buffer.asByteData().getUint16(0);
      final filename = utf8.decode(await raf.read(fnLen));
      final fileSize = (await raf.read(8)).buffer.asByteData().getUint64(0);

      final headerLen = 4 + saltLen + ivLen + 4 + 2 + fnLen + 8;
      await raf.close();

      final key = await _deriveKeyPbkdf2(passphrase, salt, iterations);
      final twistKey = await _deriveTwistKey(key, filename, fileSize);

      final algorithm = AesGcm.with256bits();

      final reader = inputFile.openRead(headerLen);
      outSink = outputFile.openWrite();

      int chunkIndex = 0;
      int processed = 0;
      final macSize = 16;

      var buffer = <int>[];
      await for (final chunk in reader) {
        buffer.addAll(chunk);

        while (buffer.length >= defaultChunkSize + macSize) {
          final chunkToProcess = buffer.sublist(0, defaultChunkSize + macSize);
          buffer = buffer.sublist(defaultChunkSize + macSize);

          final secretBox = SecretBox(
            chunkToProcess.sublist(0, defaultChunkSize),
            nonce: iv,
            mac: Mac(chunkToProcess.sublist(defaultChunkSize)),
          );
          final decrypted = await algorithm.decrypt(secretBox, secretKey: key);
          final original = await _xorWithKeystream(Uint8List.fromList(decrypted), twistKey, chunkIndex);
          outSink?.add(original);

          chunkIndex++;
          processed += original.length;
          sendPort.send(fileSize > 0 ? processed / fileSize : 0.0);
        }
      }

      if (buffer.isNotEmpty) {
        final secretBox = SecretBox(
          buffer.sublist(0, buffer.length - macSize),
          nonce: iv,
          mac: Mac(buffer.sublist(buffer.length - macSize)),
        );
        final decrypted = await algorithm.decrypt(secretBox, secretKey: key);
        final original = await _xorWithKeystream(Uint8List.fromList(decrypted), twistKey, chunkIndex);
        outSink?.add(original);
      }
    } finally {
      await outSink?.close();
    }
  }
}