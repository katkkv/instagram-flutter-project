import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordScreen extends StatefulWidget {
  final ValueNotifier<ThemeData> themeNotifier;

  const ResetPasswordScreen({Key? key, required this.themeNotifier}) : super(key: key);

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
      valueListenable: widget.themeNotifier,
      builder: (context, theme, _) {
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      kToolbarHeight,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    SizedBox(
                      height: 80,
                      child: Image.asset('assets/img/logo.png', fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 40),

                    if (!_emailSent) ...[
                      // Title
                      Text(
                        'Сброс пароля',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Description
                      Text(
                        'Введите email, связанный с вашим аккаунтом, и мы отправим вам ссылку для сброса пароля.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Email Form (без рамки)
                      Form(
                        key: _formKey,
                        child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            // Убираем все границы
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            // Стиль подчеркивания как в Instagram
                            contentPadding: const EdgeInsets.only(bottom: 8),
                            // Цвет подчеркивания
                            enabled: true,
                            labelStyle: TextStyle(
                              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                            ),
                          ),
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                            fontSize: 16,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Введите email';
                            }
                            if (!value.contains('@')) {
                              return 'Введите корректный email';
                            }
                            return null;
                          },
                        ),
                      ),
                      // Подчеркивание поля ввода
                      Container(
                        height: 1,
                        color: theme.dividerColor,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _resetPassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                              : const Text(
                            'Отправить ссылку',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Back to Login
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Вернуться к входу',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ] else ...[
                      // Success Message
                      const Icon(Icons.check_circle, color: Colors.green, size: 80),
                      const SizedBox(height: 24),
                      Text(
                        'Письмо отправлено',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Проверьте ${_emailController.text} и следуйте инструкциям',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Вернуться к входу',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _supabase.auth.resetPasswordForEmail(
        _emailController.text.trim(),
        redirectTo: 'com.example.newinstagramclone://reset-password',
      );
      setState(() => _emailSent = true);
    } on AuthException catch (e) {
      setState(() => _errorMessage = _getErrorMessage(e.message));
    } catch (e) {
      setState(() => _errorMessage = 'Произошла ошибка. Попробуйте снова.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getErrorMessage(String message) {
    if (message.contains('email')) return 'Пользователь с таким email не найден';
    if (message.contains('rate limited')) return 'Слишком много запросов. Попробуйте позже.';
    return 'Ошибка при отправке письма';
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}