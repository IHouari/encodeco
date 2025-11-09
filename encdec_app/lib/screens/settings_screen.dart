import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _outputDirectory;

  @override
  void initState() {
    super.initState();
    _loadOutputDirectory();
  }

  Future<void> _loadOutputDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _outputDirectory = prefs.getString('output_directory');
    });
  }

  Future<void> _pickOutputDirectory() async {
    final String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('output_directory', directoryPath);
      setState(() {
        _outputDirectory = directoryPath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Output Directory'),
            subtitle: Text(_outputDirectory ?? 'Not set'),
            onTap: _pickOutputDirectory,
          ),
        ],
      ),
    );
  }
}
