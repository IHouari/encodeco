import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:encdec_app/utils/encryptor.dart';

void main() {
  group('Encryptor Tests with cryptography package', () {
    final tempDir = Directory.systemTemp.createTempSync('encryptor_test');
    final originalFile = File('${tempDir.path}/original.txt');
    final encryptedFile = File('${tempDir.path}/encrypted.enc');
    final decryptedFile = File('${tempDir.path}/decrypted.txt');
    const passphrase = 'test_passphrase';

    setUp(() {
      if (originalFile.existsSync()) originalFile.deleteSync();
      if (encryptedFile.existsSync()) encryptedFile.deleteSync();
      if (decryptedFile.existsSync()) decryptedFile.deleteSync();
    });

    tearDownAll(() {
      tempDir.deleteSync(recursive: true);
    });

    test('Twist 2.0 Encryption and Decryption', () async {
      // 1. Create a dummy file
      final originalContent = Uint8List.fromList(List.generate(1024 * 256, (i) => i % 256));
      await originalFile.writeAsBytes(originalContent);

      // 2. Encrypt the file
      await Encryptor.encryptFile(
        inputFile: originalFile,
        outputFile: encryptedFile,
        passphrase: passphrase,
      );

      // 3. Decrypt the file
      await Encryptor.decryptFile(
        inputFile: encryptedFile,
        outputFile: decryptedFile,
        passphrase: passphrase,
      );

      // 4. Compare the decrypted file with the original file
      final decryptedContent = await decryptedFile.readAsBytes();
      expect(decryptedContent, equals(originalContent));
    });

    test('Empty File Encryption and Decryption', () async {
      // 1. Create an empty file
      await originalFile.create();

      // 2. Encrypt the file
      await Encryptor.encryptFile(
        inputFile: originalFile,
        outputFile: encryptedFile,
        passphrase: passphrase,
      );

      // 3. Decrypt the file
      await Encryptor.decryptFile(
        inputFile: encryptedFile,
        outputFile: decryptedFile,
        passphrase: passphrase,
      );

      // 4. Compare the decrypted file with the original file
      final decryptedContent = await decryptedFile.readAsBytes();
      expect(decryptedContent, isEmpty);
    });

    test('Decryption with Wrong Passphrase', () async {
      // 1. Create a dummy file
      final originalContent = Uint8List.fromList([1, 2, 3]);
      await originalFile.writeAsBytes(originalContent);

      // 2. Encrypt the file
      await Encryptor.encryptFile(
        inputFile: originalFile,
        outputFile: encryptedFile,
        passphrase: passphrase,
      );

      // 3. Decrypt the file with a wrong passphrase and expect an exception
      expect(
        () async => await Encryptor.decryptFile(
          inputFile: encryptedFile,
          outputFile: decryptedFile,
          passphrase: 'wrong_passphrase',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
