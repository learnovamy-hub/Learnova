import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _apiBaseUrl = 'http://localhost:3000/api';
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  static Future<Map<String, dynamic>?> studentSignup({
    required String email,
    required String name,
    required String password,
    required String parentEmail,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/student/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'name': name,
          'password': password,
          'parent_email': parentEmail,
        }),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        await _saveAuth(data['token'], data['student']);
        return data;
      } else {
        return null;
      }
    } catch (e) {
      print('Signup error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> studentLogin({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/student/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveAuth(data['token'], data['student']);
        return data;
      } else {
        return null;
      }
    } catch (e) {
      print('Login error: $e');
      return null;
    }
  }

  static Future<bool> _saveAuth(String token, Map<String, dynamic> user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userKey, jsonEncode(user));
      return true;
    } catch (e) {
      print('Save auth error: $e');
      return false;
    }
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}

class StudentSignupScreen extends StatefulWidget {
  @override
  State<StudentSignupScreen> createState() => _StudentSignupScreenState();
}

class _StudentSignupScreenState extends State<StudentSignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _parentEmailController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.purple.shade700, Colors.purple.shade400],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '🎓 Learnova',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Student Signup',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white70,
                    ),
                  ),
                  SizedBox(height: 40),
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Your Name',
                            hintText: 'e.g., Ahmad',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        SizedBox(height: 15),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email Address',
                            hintText: 'student@gmail.com',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        SizedBox(height: 15),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Min 8 characters',
                            prefixIcon: Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(
                                  () => _showPassword = !_showPassword,
                                );
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        SizedBox(height: 15),
                        TextField(
                          controller: _parentEmailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Parent Email',
                            hintText: 'parent@gmail.com',
                            prefixIcon: Icon(Icons.family_restroom),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        SizedBox(height: 25),
                        if (_errorMessage.isNotEmpty)
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _errorMessage,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleSignup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple.shade700,
                              padding: EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              _isLoading ? 'Creating account...' : 'Create Account',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Already have an account? '),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StudentLoginScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                'Login',
                                style: TextStyle(
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignup() async {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _parentEmailController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await AuthService.studentSignup(
        email: _emailController.text.trim(),
        name: _nameController.text.trim(),
        password: _passwordController.text,
        parentEmail: _parentEmailController.text.trim(),
      );

      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account created! Welcome ${_nameController.text}!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushReplacementNamed('/dashboard');
      } else {
        setState(() {
          _errorMessage = 'Signup failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _parentEmailController.dispose();
    super.dispose();
  }
}

class StudentLoginScreen extends StatefulWidget {
  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.purple.shade700, Colors.purple.shade400],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '🎓 Learnova',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Student Login',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white70,
                    ),
                  ),
                  SizedBox(height: 50),
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email Address',
                            hintText: 'student@gmail.com',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        SizedBox(height: 15),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Your password',
                            prefixIcon: Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(
                                  () => _showPassword = !_showPassword,
                                );
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        SizedBox(height: 25),
                        if (_errorMessage.isNotEmpty)
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _errorMessage,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple.shade700,
                              padding: EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              _isLoading ? 'Logging in...' : 'Login',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Don't have an account? "),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StudentSignupScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                'Sign up',
                                style: TextStyle(
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await AuthService.studentLogin(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result != null) {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      } else {
        setState(() {
          _errorMessage = 'Invalid email or password';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class DashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Learnova Dashboard'),
        backgroundColor: Colors.purple.shade700,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '✅ Welcome to Learnova!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade700,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Signup Successful!',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: () async {
                await AuthService.logout();
                Navigator.of(context).pushReplacementNamed('/');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
              ),
              child: Text('Logout', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class LearnovaStudentApp extends StatelessWidget {
  const LearnovaStudentApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learnova Student',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        useMaterial3: true,
      ),
      home: StudentSignupScreen(),
      routes: {
        '/': (context) => StudentSignupScreen(),
        '/login': (context) => StudentLoginScreen(),
        '/dashboard': (context) => DashboardScreen(),
      },
    );
  }
}

void main() {
  runApp(const LearnovaStudentApp());
}
