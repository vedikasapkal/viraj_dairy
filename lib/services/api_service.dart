import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use your local backend URL (e.g., localhost:5001 or IP for emulator)
  static const String baseUrl = 'https://localhost:5001/api';

  static Future<List<dynamic>> fetchAllUsers() async {
    final response = await http.get(Uri.parse('$baseUrl/users'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load users');
  }
}