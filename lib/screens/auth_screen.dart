import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/auth_service.dart';
import '../data/locale_country.dart';
import '../theme/app_theme.dart';
import '../widgets/community_safety_dialog.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  int _mode = 0; // 0 = Login, 1 = Sign Up, 2 = Forgot Password
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  
  // Registration location fields
  final _zipController = TextEditingController(text: '75001');
  final _cityController = TextEditingController(text: 'Tunis');
  final _stateController = TextEditingController(text: 'Tunis State');
  
  final _confirmPasswordController = TextEditingController();
  DeviceCountry _selectedCountry = const DeviceCountry(name: 'Tunisia', flag: '🇹🇳');
  bool _isLoading = false;
  bool _agreedToEula = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _zipController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_mode == 1 && _passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_mode == 1 && !_agreedToEula) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please read and agree to the Terms of Service & EULA to register.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final auth = AuthService.instance;

    try {
      if (_mode == 0) {
        // Sign In
        await auth.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Welcome back! 👋'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
          );
        }
      } else if (_mode == 1) {
        // Sign Up
        final username = _usernameController.text.trim().toLowerCase();
        final isTaken = await auth.isUsernameTaken(username);
        if (isTaken) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Username is already taken! ❌'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
            );
            setState(() => _isLoading = false);
          }
          return;
        }

        await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
          username: username,
          zip: _zipController.text.trim(),
          city: _cityController.text.trim(),
          state: _stateController.text.trim(),
          country: _selectedCountry.name,
          countryFlag: _selectedCountry.flag,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account successfully created! 🎉'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
          );
        }
      } else {
        // Reset Password
        await auth.sendPasswordReset(_emailController.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset link sent to your email! ✉️'), backgroundColor: Colors.purple, behavior: SnackBarBehavior.floating),
          );
          setState(() => _mode = 0);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.alertCircle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text('Error: ${e.toString().replaceAll(RegExp(r'\[.*\]'), '').trim()}')),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    final auth = AuthService.instance;

    try {
      await auth.signInWithGoogle();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome! 🎉'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.alertCircle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text('Error: ${e.toString().replaceAll(RegExp(r'\[.*\]'), '').trim()}')),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    final auth = AuthService.instance;

    try {
      await auth.signInWithApple();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome! 🎉'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.alertCircle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text('Error: ${e.toString().replaceAll(RegExp(r'\[.*\]'), '').trim()}')),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // Background soft HSL light points
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.15),
                boxShadow: [
                  BoxShadow(color: AppTheme.primary.withValues(alpha: 0.15), blurRadius: 100, spreadRadius: 50),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.purple.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(color: Colors.purple.withValues(alpha: 0.12), blurRadius: 80, spreadRadius: 40),
                ],
              ),
            ),
          ),

          // Core content scroll
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand Title
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: AppTheme.pinkPurpleGradient,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.flame, color: Colors.white, size: 36),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'MLIVECAST',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Card container
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 5),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _mode == 0
                                ? 'LOGIN TO YOUR ACCOUNT'
                                : _mode == 1
                                    ? 'CREATE NEW ACCOUNT'
                                    : 'RESET YOUR PASSWORD',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Name field (Sign up only)
                          if (_mode == 1) ...[
                            _buildLabel('DISPLAY NAME'),
                            _buildTextField(
                              controller: _nameController,
                              hint: 'Enter display name',
                              icon: LucideIcons.user,
                              validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a name' : null,
                            ),
                            const SizedBox(height: 16),
                            _buildLabel('UNIQUE USERNAME'),
                            _buildTextField(
                              controller: _usernameController,
                              hint: 'Choose a unique username',
                              icon: LucideIcons.atSign,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Please choose a username';
                                if (val.trim().length < 3) return 'Username must be at least 3 characters';
                                if (RegExp(r'[^a-zA-Z0-9_]').hasMatch(val.trim())) {
                                  return 'Letters, numbers, and underscores only';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Email field
                          _buildLabel('EMAIL ADDRESS'),
                          _buildTextField(
                            controller: _emailController,
                            hint: 'Enter email address',
                            icon: LucideIcons.mail,
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Please enter an email';
                              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(val.trim())) return 'Invalid email address';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password field (Login / Signup only)
                          if (_mode != 2) ...[
                            _buildLabel('PASSWORD'),
                            _buildTextField(
                              controller: _passwordController,
                              hint: 'Enter password (min 8 chars)',
                              icon: LucideIcons.lock,
                              obscure: true,
                              validator: (val) {
                                if (val == null || val.isEmpty) return 'Please enter a password';
                                if (val.length < 8) return 'Password must be at least 8 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Re-enter Password field (Sign up only)
                          if (_mode == 1) ...[
                            _buildLabel('CONFIRM PASSWORD'),
                            _buildTextField(
                              controller: _confirmPasswordController,
                              hint: 'Confirm your password',
                              icon: LucideIcons.lock,
                              obscure: true,
                              validator: (val) {
                                if (val == null || val.isEmpty) return 'Please confirm your password';
                                if (val != _passwordController.text) return 'Passwords do not match';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Location Fields (Sign up only)
                          if (_mode == 1) ...[
                            _buildLabel('LOCATION LIMITS (ZIP CODE)'),
                            _buildTextField(
                              controller: _zipController,
                              hint: 'Enter zip code',
                              icon: LucideIcons.mapPin,
                              validator: (val) => val == null || val.trim().isEmpty ? 'Zip code required' : null,
                            ),
                            const SizedBox(height: 16),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('CITY'),
                                      _buildTextField(
                                        controller: _cityController,
                                        hint: 'Enter city',
                                        icon: LucideIcons.map,
                                        validator: (val) => val == null || val.trim().isEmpty ? 'City required' : null,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('STATE'),
                                      _buildTextField(
                                        controller: _stateController,
                                        hint: 'Enter state',
                                        icon: LucideIcons.map,
                                        validator: (val) => val == null || val.trim().isEmpty ? 'State required' : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            _buildLabel('COUNTRY SELECT'),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<DeviceCountry>(
                                  dropdownColor: const Color(0xFF1E1E1E),
                                  value: LocaleCountry.pickableCountries.firstWhere(
                                    (c) => c.name == _selectedCountry.name,
                                    orElse: () => LocaleCountry.pickableCountries.first,
                                  ),
                                  icon: const Icon(LucideIcons.chevronDown, color: Colors.white54, size: 16),
                                  isExpanded: true,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  items: LocaleCountry.pickableCountries.map((c) {
                                    return DropdownMenuItem<DeviceCountry>(
                                      value: c,
                                      child: Text('${c.flag}  ${c.name}'),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedCountry = val);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Forgot password switch (Login only)
                          if (_mode == 0)
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: () => setState(() => _mode = 2),
                                child: Text(
                                  'Forgot Password?',
                                  style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          // EULA & Terms Checkbox (Register mode only)
                          if (_mode == 1) ...[
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _agreedToEula,
                                    activeColor: AppTheme.primary,
                                    checkColor: Colors.white,
                                    onChanged: (val) => setState(() => _agreedToEula = val ?? false),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => CommunitySafetyHelper.showEula(context),
                                    child: RichText(
                                      text: const TextSpan(
                                        style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.35),
                                        children: [
                                          TextSpan(text: 'I agree to the '),
                                          TextSpan(
                                            text: 'Terms of Service & EULA',
                                            style: TextStyle(
                                              color: AppTheme.primary,
                                              fontWeight: FontWeight.bold,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                          TextSpan(
                                            text: ' (Zero tolerance for objectionable content or abusive users).',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 4,
                              ),
                              onPressed: _isLoading ? null : _submit,
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      _mode == 0
                                          ? 'LOG IN'
                                          : _mode == 1
                                              ? 'REGISTER ACCOUNT'
                                              : 'SEND RESET EMAIL',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Apple Sign-In Button (iOS only, Login mode)
                          if (_mode == 0 && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _isLoading ? null : _signInWithApple,
                                icon: const Icon(Icons.apple, size: 22, color: Colors.black),
                                label: const Text('Sign in with Apple', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Google Sign-In Button (Login mode only)
                          if (_mode == 0) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : _signInWithGoogle,
                                icon: const Icon(Icons.g_mobiledata, size: 20),
                                label: const Text('Sign in with Google', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white24),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Mode selector toggles
                          Center(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (_mode == 0) {
                                    _mode = 1;
                                  } else {
                                    _mode = 0;
                                  }
                                });
                              },
                              child: Text(
                                _mode == 0
                                    ? 'Don\'t have an account? Sign Up'
                                    : 'Already have an account? Log In',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ),
                          ),
                          if (_mode == 2) ...[
                            const SizedBox(height: 12),
                            Center(
                              child: GestureDetector(
                                onTap: () => setState(() => _mode = 0),
                                child: const Text(
                                  'Back to Login',
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 16),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
        errorStyle: const TextStyle(fontSize: 10, color: Colors.redAccent),
      ),
    );
  }
}
