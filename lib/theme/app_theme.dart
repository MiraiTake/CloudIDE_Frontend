import 'package:flutter/material.dart';

class AppTheme {
  // Светлая тема
  static const lightBg = Color(0xFFF5F5F5);
  static const lightRailBg = Color(0xFFFFFFFF);
  static const lightContentBg = Color(0xFFFFFFFF);
  static const lightCardBg = Color(0xFFFFFFFF);
  static const lightDivider = Color(0xFFE0E0E0);
  static const lightAccent = Color(0xFF2196F3);
  static const lightTextColor = Color(0xFF212121);
  static const lightInputBg = Color(0xFFF5F5F5);

  // Темная тема
  static const darkBg = Color(0xFF1E1E1E);
  static const darkRailBg = Color(0xFF2A2A2A);
  static const darkContentBg = Color(0xFF2E2E2E);
  static const darkCardBg = Color(0xFF2A2A2A);
  static const darkDivider = Color(0xFF3C3F41);
  static const darkAccent = Color(0xFF9FBACD);
  static const darkTextColor = Color(0xFFCCCCCC);
  static const darkInputBg = Color(0xFF232323);

  // Геттеры для текущей темы
  static Color getBg(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light ? lightBg : darkBg;
  }

  static Color getRailBg(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light ? lightRailBg : darkRailBg;
  }

  static Color getContentBg(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light ? lightContentBg : darkContentBg;
  }

  static Color getCardBg(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light ? lightCardBg : darkCardBg;
  }

  static Color getDivider(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light ? lightDivider : darkDivider;
  }

  static Color getAccent(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light ? lightAccent : darkAccent;
  }

  static Color getTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light ? lightTextColor : darkTextColor;
  }

  static Color getInputBg(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light ? lightInputBg : darkInputBg;
  }

  // ThemeData для MaterialApp
  static ThemeData lightTheme() {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: lightBg,
      primaryColor: lightAccent,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: lightTextColor,
        displayColor: lightTextColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightRailBg,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: lightTextColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: lightTextColor),
      ),
      cardTheme: CardThemeData(
        color: lightCardBg,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerColor: lightDivider,
    );
  }

  static ThemeData darkTheme() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: darkBg,
      primaryColor: darkAccent,
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: darkTextColor,
        displayColor: darkTextColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkAccent,
          foregroundColor: Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkRailBg,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: darkTextColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: darkTextColor),
      ),
      cardTheme: CardThemeData(
        color: darkCardBg,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerColor: darkDivider,
    );
  }
}