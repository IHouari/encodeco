import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Hash a string using SHA-256 for secure storage.
String hashPassword(String password) {
  final bytes = utf8.encode(password);
  final digest = sha256.convert(bytes);
  return digest.toString();
}
