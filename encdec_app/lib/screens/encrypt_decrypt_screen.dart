import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/encryptor.dart';
import 'package:encdec_app/screens/settings_screen.dart';

class EncryptDecryptScreen extends StatefulWidget {
  const EncryptDecryptScreen({super.key});

  @override
  State<EncryptDecryptScreen> createState() => _EncryptDecryptScreenState();
}

class _EncryptDecryptScreenState extends State<EncryptDecryptScreen> {
  File? _inputFile;
  double _progress = 0.0;
  String _status = '';
  final TextEditingController _passController = TextEditingController();

  Future<void> _pickInputFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => _inputFile = File(result.files.single.path!));
    }
  }

  Future<String?> _pickOutputFile({required bool isEncryption}) async {
    final prefs = await SharedPreferences.getInstance();
    final String? outputDirectory = prefs.getString('output_directory');

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return await FilePicker.platform.saveFile(
        dialogTitle: isEncryption
            ? 'Choose output location for encrypted file'
            : 'Choose output location for decrypted file',
        initialDirectory: outputDirectory,
        fileName: isEncryption
            ? '${_inputFile!.path.split(Platform.pathSeparator).last}.enc'
            : _inputFile!.path
                .split(Platform.pathSeparator)
                .last
                .replaceAll('.enc', ''),
      );
    } else {
      final fileName = isEncryption
          ? '${_inputFile!.path.split(Platform.pathSeparator).last}.enc'
          : _inputFile!.path
              .split(Platform.pathSeparator)
              .last
              .replaceAll('.enc', '');
      return '$outputDirectory/$fileName';
    }
  }

  Future<void> _encryptOrDecryptFile() async {
    if (_inputFile == null || _passController.text.isEmpty) {
      setState(() => _status = 'Please select a file and enter a passphrase.');
      return;
    }

    final isEncrypted = _inputFile!.path.endsWith('.enc');
    final savePath = await _pickOutputFile(isEncryption: !isEncrypted);

    if (savePath == null) {
      setState(() => _status = 'No output file selected.');
      return;
    }

    setState(() {
      _progress = 0;
      _status = isEncrypted ? 'Decrypting...' : 'Encrypting...';
    });

    try {
      if (isEncrypted) {
        await Encryptor.decryptFile(
          inputFile: _inputFile!,
          outputFile: File(savePath),
          passphrase: _passController.text,
          onProgress: (p) => setState(() => _progress = p),
        );
        setState(() => _status = 'Decryption completed!');
      } else {
        await Encryptor.encryptFile(
          inputFile: _inputFile!,
          outputFile: File(savePath),
          passphrase: _passController.text,
          onProgress: (p) => setState(() => _progress = p),
        );
        setState(() => _status = 'Encryption completed!');
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  void dispose() {
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encrypt / Decrypt File'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _passController,
              decoration: const InputDecoration(
                labelText: 'Passphrase',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _pickInputFile,
              child: const Text('Select Input File'),
            ),
            if (_inputFile != null) Text('Selected: ${_inputFile!.path}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _encryptOrDecryptFile,
              child: const Text('Start'),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
