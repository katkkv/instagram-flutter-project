import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/app_themes.dart';
import 'instagram/main_screen.dart';
import 'instagram/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://iymoexinovejjpmizdry.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml5bW9leGlub3ZlampwbWl6ZHJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE5NjUwNDksImV4cCI6MjA1NzU0MTA0OX0.xNZC0eTLRosBlbMG1RVyQUFq7K3KgxerS4nBn9NoH8U',
  );

  final prefs = await SharedPreferences.getInstance();
  final themeModeIndex = prefs.getInt('themeMode') ?? 0; // 0 - light, 1 - dark, 2 - pink

  final ValueNotifier<ThemeData> themeNotifier = ValueNotifier<ThemeData>(
    themeModeIndex == 1
        ? AppThemes.darkTheme
        : themeModeIndex == 2
        ? AppThemes.pinkTheme
        : AppThemes.lightTheme,
  );

  runApp(MyApp(themeNotifier: themeNotifier));
}

class MyApp extends StatefulWidget {
  final ValueNotifier<ThemeData> themeNotifier;

  const MyApp({Key? key, required this.themeNotifier}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isInitialized = false;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    final supabase = Supabase.instance.client;
    print('Setting up auth listener');
    supabase.auth.onAuthStateChange.listen((data) async {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      print('Auth event: $event, Session: ${session != null ? "present" : "null"}');

      if (event == AuthChangeEvent.signedIn && session != null && !_isInitialized) {
        _isInitialized = true; // Prevent multiple navigations
        final user = session.user;
        print('Signed in user: ${user?.id}, ${user?.email}');
        if (user != null) {
          try {
            // Check if profile exists
            print('Querying profiles table for user: ${user.id}');
            final userProfileResponse = await supabase
                .from('profiles')
                .select()
                .eq('id', user.id)
                .maybeSingle();

            print('Profile response: $userProfileResponse');

            if (userProfileResponse == null) {
              // New user: Create a profile
              final newProfile = {
                'id': user.id,
                'username': user.email?.split('@')[0] ?? 'user_${user.id}', // Generate username from email
                'email': user.email ?? '',
                'bio': '', // Optional field
                'avatar_url': '', // Optional field
                'total_posts': 0, // Default value
                'followers_count': 0, // Default value
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
              _navigateToMainScreen(context, newUserProfile);
            } else if (userProfileResponse['is_deleted'] == true) {
              print('Profile is deleted');
              _showDeletedProfileDialog(context);
            } else {
              print('Existing profile: $userProfileResponse');
              _navigateToMainScreen(context, userProfileResponse);
            }
          } catch (e) {
            print('Error in auth listener: $e');
            _scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(content: Text('Ошибка при обработке профиля: $e')),
            );
          }
        } else {
          print('No user in session');
        }
      } else if (event != AuthChangeEvent.signedIn) {
        print('Non-sign-in event: $event');
      }
    }, onError: (error) {
      print('Auth listener error: $error');
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Ошибка авторизации: $error')),
      );
    });
  }

  void _navigateToMainScreen(BuildContext context, Map<String, dynamic> userProfile) {
    print('Navigating to MainScreen with Profile tab');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => MainScreen(
            userProfile: userProfile,
            themeNotifier: widget.themeNotifier,
            initialIndex: 3, // Set to ProfileScreen tab
          ),
        ),
      );
    });
  }

  void _showDeletedProfileDialog(BuildContext context) {
    print('Showing deleted profile dialog');
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
      valueListenable: widget.themeNotifier,
      builder: (context, theme, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Flutter Demo',
          theme: theme,
          scaffoldMessengerKey: _scaffoldMessengerKey,
          home: LoginScreen(themeNotifier: widget.themeNotifier),
        );
      },
    );
  }
}