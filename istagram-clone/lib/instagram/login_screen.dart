import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_themes.dart';
import '../screens/admin_screen.dart';
import '../screens/reset_password_screen.dart';
import 'main_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key, required this.themeNotifier}) : super(key: key);
  final ValueNotifier<ThemeData> themeNotifier;

  @override
  Widget build(BuildContext context) {
    final _emailController = TextEditingController();
    final _passwordController = TextEditingController();

    return ValueListenableBuilder<ThemeData>(
      valueListenable: themeNotifier,
      builder: (context, theme, child) {
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                children: [
                  const SizedBox(height: 100),
                  Image.asset('assets/img/logo.png', height: 60, width: 180),
                  const SizedBox(height: 20),

                  // Email Field
                  _buildTextField(
                    controller: _emailController,
                    hintText: 'Email',
                    theme: theme,
                  ),
                  const SizedBox(height: 15),

                  // Password Field
                  _buildTextField(
                    controller: _passwordController,
                    hintText: 'Пароль',
                    isPassword: true,
                    theme: theme,
                  ),
                  const SizedBox(height: 15),

                  // Login Button
                  _buildLoginButton(context, _emailController, _passwordController, theme),
                  const SizedBox(height: 10),

                  // Google Sign-In Button
                  _buildGoogleSignInButton(context, theme),
                  const SizedBox(height: 10),

                  // Reset Password Link
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ResetPasswordScreen(themeNotifier: themeNotifier),
                        ),
                      );
                    },
                    child: Text(
                      'Забыли пароль?',
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color?.withOpacity(0.8),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  // Registration Link
                  _buildRegistrationLink(context, theme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool isPassword = false,
    required ThemeData theme,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.grey),
        ),
        hintStyle: TextStyle(color: Colors.grey),
        hintText: hintText,
        filled: true,
        fillColor: Colors.transparent,
      ),
      obscureText: isPassword,
    );
  }

  Widget _buildLoginButton(BuildContext context, TextEditingController emailController, TextEditingController passwordController, ThemeData theme) {
    // Determine the button color based on the theme
    Color buttonColor = theme == AppThemes.pinkTheme ? Colors.pink : theme.primaryColor;
    return InkWell(
      onTap: () async {
        final email = emailController.text.trim();
        final password = passwordController.text.trim();

        if (email.isEmpty || password.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Поля не введены. Пожалуйста, заполните все поля.'),
            ),
          );
          return;
        }

        final supabase = Supabase.instance.client;
        try {
          // Сначала проверяем существование пользователя
          final authResponse = await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );

          if (authResponse.user != null) {
            print('Email/Password sign-in successful, user ID: ${authResponse.user?.id}');
            await _handleSignIn(context, authResponse.user!.id);
          }
        } on AuthException catch (e) {
          if (e.message.contains('Invalid login credentials')) {
            // Проверяем, существует ли email в базе
            final userExists = await supabase
                .from('profiles')
                .select()
                .eq('email', email)
                .maybeSingle();

            if (userExists == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Пользователь с таким email не зарегистрирован'),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Неверный пароль'),
                ),
              );
            }
          } else if (e.message.contains('is_deleted')) {
            _showDeletedProfileDialog(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка аутентификации: ${e.message}'),
              ),
            );
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Произошла ошибка: ${e.toString()}'),
            ),
          );
        }
      },
      child: Container(
        width: 327,
        height: 50,
        decoration: BoxDecoration(
          color: buttonColor, // Use the determined button color
          borderRadius: BorderRadius.circular(15),
        ),
        child: Center(
          child: Text(
            'Войти',
            style: TextStyle(
              color: Colors.white, // Always white for contrast
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSignInButton(BuildContext context, ThemeData theme) {
    return ElevatedButton(
      onPressed: () async {
        try {
          final supabase = Supabase.instance.client;
          print('Starting Google Sign-In');

          // Sign in with Google
          await supabase.auth.signInWithOAuth(
            OAuthProvider.google,
            redirectTo: 'com.example.newinstagramclone://login-callback/',
          );

          print('signInWithOAuth called');

          // Since signInWithOAuth opens a browser, we rely on the redirect to handle the sign-in
          // The onAuthStateChange listener in main.dart will handle the navigation
          // However, we can add a local check to ensure the user is signed in after redirect
          final user = supabase.auth.currentUser;
          if (user != null) {
            print('Google Sign-In successful, user ID: ${user.id}');
            await _handleSignIn(context, user.id);
          } else {
            // Wait for the redirect to complete (handled by onAuthStateChange in main.dart)
            print('Waiting for Google Sign-In redirect to complete');
          }
        } catch (e) {
          print('Google Sign-In error: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка аутентификации: $e'),
            ),
          );
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size(327, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      child: const Text('Войти через Google'),
    );
  }

  Future<void> _handleSignIn(BuildContext context, String userId) async {
    final supabase = Supabase.instance.client;
    try {
      // Check if profile exists
      print('Querying profiles table for user: $userId');
      final userProfileResponse = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      print('Profile response: $userProfileResponse');

      if (userProfileResponse == null) {
        // New user: Create a profile
        final user = supabase.auth.currentUser;
        if (user != null) {
          final newProfile = {
            'id': user.id,
            'username': user.email?.split('@')[0] ?? 'user_${user.id}',
            'email': user.email ?? '',
            'full_name': user.userMetadata?['full_name'] ?? user.email?.split('@')[0] ?? 'Пользователь',
            'created_at': DateTime.now().toIso8601String(),
            'bio': '',
            'avatar_url': '',
            'total_posts': 0,
            'followers_count': 0,
            'subscriptions_count': 0,
            'role': 'user',
            'is_deleted': false,
          };
          print('Creating new profile: $newProfile');
          await supabase.from('profiles').insert(newProfile);
          // Fetch the new profile
          final newUserProfile = await supabase
              .from('profiles')
              .select()
              .eq('id', user.id)
              .single();

          print('New profile fetched: $newUserProfile');
          _navigateBasedOnRole(context, newUserProfile);
        }
      } else if (userProfileResponse['is_deleted'] == true) {
        print('Profile is deleted');
        _showDeletedProfileDialog(context);
      } else {
        print('Existing profile: $userProfileResponse');
        _navigateBasedOnRole(context, userProfileResponse);
      }
    } catch (e) {
      print('Error in handleSignIn: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при обработке профиля: $e')),
      );
    }
  }

  void _navigateBasedOnRole(BuildContext context, Map<String, dynamic> userProfile) {
    print('Navigating to MainScreen with Profile tab');
    if (userProfile['role'] == 'admin') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => AdminScreen(themeNotifier: themeNotifier),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => MainScreen(
            userProfile: userProfile,
            themeNotifier: themeNotifier,
            initialIndex: 3, // Set to ProfileScreen tab
          ),
        ),
      );
    }
  }

  Widget _buildRegistrationLink(BuildContext context, ThemeData theme) {
    final bool isPinkTheme = theme == AppThemes.pinkTheme;
    final bool isDarkTheme = theme.brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Нет аккаунта? ",
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => RegisterScreen(themeNotifier: themeNotifier),
              ),
            );
          },
          child: Text(
            "Зарегистрируйтесь",
            style: TextStyle(
              color: isPinkTheme
                  ? Colors.pink
                  : (isDarkTheme ? Colors.white : theme.primaryColor),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }


  void _showDeletedProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ошибка'),
          content: const Text('Ваш профиль был удален.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('ОК'),
            ),
          ],
        );
      },
    );
  }
}