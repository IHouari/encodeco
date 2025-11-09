import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _storedPassword;
  bool _isSetting = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _loadPassword();
  }

  Future<void> _loadPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('master_password');
    setState(() {
      _storedPassword = saved;
      _isSetting = saved == null;
    });
  }

  Future<void> _savePassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('master_password', password);
  }

  void _verifyPassword() async {
    final input = _controller.text;
    if (_isSetting) {
      if (input.isNotEmpty) {
        await _savePassword(input);
        widget.onUnlocked();
      } else {
        setState(() => _message = 'Please enter a valid password.');
      }
    } else {
      if (input == _storedPassword) {
        widget.onUnlocked();
      } else {
        setState(() => _message = 'Incorrect password.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isSetting ? 'Set Master Password' : 'Enter Master Password',
                style: const TextStyle(fontSize: 20, color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                obscureText: true,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(),
                  hintText: 'Password',
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _verifyPassword,
                child: Text(_isSetting ? 'Set Password' : 'Unlock'),
              ),
              const SizedBox(height: 12),
              Text(_message, style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ),
    );
  }
}
