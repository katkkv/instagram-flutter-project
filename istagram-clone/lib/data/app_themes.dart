import 'package:flutter/material.dart';

class AppThemes {
  static final lightTheme = ThemeData(
    primarySwatch: Colors.amber,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Color(0xFFF8F1F1),
    appBarTheme: AppBarTheme(
      backgroundColor: Color(0xFFFFE4E1),
      foregroundColor: Colors.black87,
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF2F4F4F)),
      bodyMedium: TextStyle(color: Color(0xFF2F4F4F)),
      titleLarge: TextStyle(color: Color(0xFF2F4F4F), fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: Color(0xFF2F4F4F)),
      titleSmall: TextStyle(color: Color(0xFF2F4F4F)),
    ),
    iconTheme: IconThemeData(color: Color(0xFFFF7F50)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFFFF7F50),
        foregroundColor: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Color(0xFFFF7F50),
    ),
  );

  // Оставляем darkTheme и pinkTheme без изменений
  static final darkTheme = ThemeData(
    primarySwatch: Colors.blueGrey,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey[850],
      foregroundColor: Colors.white,
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
    ),
    iconTheme: IconThemeData(color: Colors.white),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Colors.grey[800],
    ),
  );

  static final pinkTheme = ThemeData(
    primarySwatch: Colors.pink,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.pink[50],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.pink,
      foregroundColor: Colors.white,
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF4E3B31)),
      bodyMedium: TextStyle(color: Color(0xFF4E3B31)),
    ),
    iconTheme: IconThemeData(color: Colors.pink),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Colors.pink,
    ),
  );
}