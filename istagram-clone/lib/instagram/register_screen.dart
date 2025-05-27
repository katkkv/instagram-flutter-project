import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_themes.dart';
import '../user_profile.dart';
import 'login_screen.dart';
import 'main_screen.dart';

class RegisterScreen extends StatefulWidget {
  final ValueNotifier<ThemeData> themeNotifier;

  const RegisterScreen({Key? key, required this.themeNotifier}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _supabase = Supabase.instance.client;

  String _passwordStrength = '';
  double _strength = 0;
  bool _passwordsMatch = true;
  bool _showPasswordRequirements = false;
  String? _emailError;
  String? _usernameError;
  bool _isCheckingUsername = false;

  @override
  void initState() {
    super.initState();
    // Добавляем слушатели для автоматического скрытия ошибок
    _usernameController.addListener(_clearUsernameError);
    _emailController.addListener(_clearEmailError);
    _passwordController.addListener(_clearPasswordError);
    _confirmPasswordController.addListener(_clearPasswordMatchError);
  }

  void _clearUsernameError() {
    if (_usernameError != null) {
      setState(() => _usernameError = null);
    }
  }

  void _clearEmailError() {
    if (_emailError != null) {
      setState(() => _emailError = null);
    }
  }

  void _clearPasswordError() {
    if (_strength < 0.7 && _passwordController.text.isNotEmpty) {
      setState(() => _strength = 0.7);
    }
  }

  void _clearPasswordMatchError() {
    if (!_passwordsMatch && _confirmPasswordController.text == _passwordController.text) {
      setState(() => _passwordsMatch = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
      valueListenable: widget.themeNotifier,
      builder: (context, theme, child) {
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  Image.asset('assets/img/logo.png', height: 60, width: 180),
                  const SizedBox(height: 20),
                  Text(
                    "Зарегистрируйтесь, чтобы видеть фотографии и видео от ваших друзей.",
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Username Field
                  _buildUsernameField(),
                  const SizedBox(height: 15),

                  // Email Field
                  _buildEmailField(),
                  const SizedBox(height: 15),

                  // Password Field
                  _buildPasswordField(),
                  const SizedBox(height: 5),

                  // Password Strength Indicator
                  _buildPasswordStrengthIndicator(),
                  const SizedBox(height: 5),

                  // Password Requirements
                  _buildPasswordRequirements(),
                  const SizedBox(height: 10),

                  // Confirm Password Field
                  _buildConfirmPasswordField(),
                  if (_confirmPasswordController.text.isNotEmpty && !_passwordsMatch)
                    _buildErrorText('Пароли не совпадают'),
                  const SizedBox(height: 15),

                  // Register Button
                  _buildRegisterButton(theme),
                  const SizedBox(height: 20),

                  // Agreement Text
                  Text(
                    "Подписываясь, вы соглашаетесь с нашими Условиями и Политикой конфиденциальности",
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Login Link
                  _buildLoginLink(theme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsernameField() {
    return Stack(
      children: [
        _buildStripTextField(
          controller: _usernameController,
          hintText: 'Имя пользователя',
          maxLength: 30,
          errorText: _usernameError,
          onChanged: (value) => _checkUsernameAvailability(value),
        ),
        if (_isCheckingUsername)
          Positioned(
            right: 0,
            top: 0,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmailField() {
    return _buildStripTextField(
      controller: _emailController,
      hintText: 'Email',
      keyboardType: TextInputType.emailAddress,
      emailError: _emailError,
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      maxLength: 35,
      decoration: InputDecoration(
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.grey),
        ),
        hintText: 'Пароль',
        hintStyle: TextStyle(color: Colors.grey),
        suffixIcon: IconButton(
          icon: Icon(
            _showPasswordRequirements ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey,
          ),
          onPressed: () {
            setState(() {
              _showPasswordRequirements = !_showPasswordRequirements;
            });
          },
        ),
      ),
      obscureText: !_showPasswordRequirements,
      onChanged: (value) {
        _checkPassword(value);
        _checkPasswordsMatch();
      },
    );
  }

  Widget _buildPasswordStrengthIndicator() {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: _strength),
          duration: const Duration(milliseconds: 300),
          builder: (context, value, child) {
            return LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.grey[300],
              color: value <= 0.3
                  ? Colors.red
                  : value <= 0.6
                  ? Colors.yellow
                  : Colors.green,
            );
          },
        ),
        Text(
          _passwordStrength,
          style: TextStyle(
            color: _strength <= 0.3
                ? Colors.red
                : _strength <= 0.6
                ? Colors.orange
                : Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordRequirements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequirement('Минимум 8 символов', _passwordController.text.length >= 8),
        _buildRequirement('Хотя бы 1 цифра', _passwordController.text.contains(RegExp(r'[0-9]'))),
        _buildRequirement('Хотя бы 1 заглавная буква', _passwordController.text.contains(RegExp(r'[A-Z]'))),
        _buildRequirement('Хотя бы 1 спецсимвол', _passwordController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))),
      ],
    );
  }

  Widget _buildConfirmPasswordField() {
    return _buildStripTextField(
      controller: _confirmPasswordController,
      hintText: 'Повторите пароль',
      isPassword: true,
      onChanged: (value) => _checkPasswordsMatch(),
    );
  }

  Widget _buildErrorText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.red,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildStripTextField({
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    int? maxLength,
    String? emailError,
    String? errorText,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: isPassword,
          maxLength: maxLength,
          decoration: InputDecoration(
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey),
            errorText: emailError ?? errorText,
          ),
          onChanged: onChanged,
        ),
        if (maxLength != null)
          Text(
            '${controller.text.length}/$maxLength',
            style: TextStyle(color: Colors.grey),
          ),
      ],
    );
  }

  Widget _buildRegisterButton(ThemeData theme) {
    return InkWell(
      onTap: _registerUser,
      child: Container(
        width: 327,
        height: 50,
        decoration: BoxDecoration(
          color: theme.primaryColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Center(
          child: Text(
            'Регистрация',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginLink(ThemeData theme) {
    final bool isPinkTheme = theme == AppThemes.pinkTheme;
    final bool isDarkTheme = theme.brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Есть аккаунт? ",
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => LoginScreen(themeNotifier: widget.themeNotifier),
            ),
          ),
          child: Text(
            " Войти",
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

  Widget _buildRequirement(String text, bool isMet) {
    return Row(
      children: [
        Icon(
          isMet ? Icons.check_circle : Icons.circle,
          color: isMet ? Colors.green : Colors.grey,
          size: 16,
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: isMet ? Colors.green : Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Future<void> _checkUsernameAvailability(String username) async {
    if (username.isEmpty) {
      setState(() {
        _usernameError = null;
        _isCheckingUsername = false;
      });
      return;
    }

    setState(() => _isCheckingUsername = true);

    try {
      final response = await _supabase
          .from('profiles')
          .select('username')
          .eq('username', username)
          .maybeSingle();

      setState(() {
        _usernameError = response != null ? 'Это имя пользователя уже занято' : null;
        _isCheckingUsername = false;
      });
    } catch (e) {
      setState(() {
        _usernameError = 'Ошибка проверки имени';
        _isCheckingUsername = false;
      });
    }
  }

  void _checkPassword(String password) {
    double strength = 0;
    String strengthText = '';

    if (password.isNotEmpty) {
      if (password.length >= 8) strength += 0.2;
      if (password.length >= 12) strength += 0.1;
      if (password.contains(RegExp(r'[0-9]'))) strength += 0.2;
      if (password.contains(RegExp(r'[A-Z]'))) strength += 0.2;
      if (password.contains(RegExp(r'[a-z]'))) strength += 0.1;
      if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.3;

      strengthText = strength < 0.4 ? 'Слабый' :
      strength < 0.7 ? 'Средний' : 'Надежный';
    }

    setState(() {
      _strength = strength.clamp(0.0, 1.0);
      _passwordStrength = strengthText;
    });
  }

  void _checkPasswordsMatch() {
    setState(() {
      _passwordsMatch = _passwordController.text == _confirmPasswordController.text;
    });
  }

  Future<void> _registerUser() async {
    // Проверка валидации
    if (!_passwordsMatch) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Пароли не совпадают')),
      );
      return;
    }

    if (_strength < 0.6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Пароль слишком слабый')),
      );
      return;
    }

    try {
      // Показываем индикатор загрузки
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()),
      );

      // 1. Проверка уникальности username
      final usernameCheck = await _supabase
          .from('profiles')
          .select()
          .eq('username', _usernameController.text.trim())
          .maybeSingle();

      if (usernameCheck != null) {
        Navigator.pop(context); // Закрываем индикатор загрузки
        setState(() => _usernameError = 'Это имя пользователя уже занято');
        return;
      }

      // 2. Регистрация в Supabase Auth
      final authResponse = await _supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {'username': _usernameController.text.trim()},
      );

      if (authResponse.user == null) {
        Navigator.pop(context); // Закрываем индикатор загрузки
        throw Exception('Не удалось создать пользователя');
      }

      // 3. Создание профиля (если триггер не сработал)
      try {
        await _supabase.from('profiles').upsert({
          'id': authResponse.user!.id,
          'username': _usernameController.text.trim(),
          'email': _emailController.text.trim(),
        });
      } catch (e) {
        print('Ошибка при создании профиля: $e');
      }

      // 4. Закрываем индикатор и переходим на главный экран
      Navigator.pop(context); // Закрываем индикатор загрузки

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MainScreen(
            userProfile: {
              'id': authResponse.user!.id,
              'username': _usernameController.text.trim(),
              'email': _emailController.text.trim(),
            },
            themeNotifier: widget.themeNotifier,
          ),
        ),
            (route) => false,
      );

    } on AuthException catch (e) {
      Navigator.pop(context); // Закрываем индикатор при ошибке
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка регистрации: ${e.message}')),
      );
    } catch (e) {
      Navigator.pop(context); // Закрываем индикатор при ошибке
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${e.toString()}')),
      );
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+').hasMatch(email);
  }

  @override
  void dispose() {
    _emailController.removeListener(_clearEmailError);
    _usernameController.removeListener(_clearUsernameError);
    _passwordController.removeListener(_clearPasswordError);
    _confirmPasswordController.removeListener(_clearPasswordMatchError);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}