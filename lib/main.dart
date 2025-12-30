import 'package:flutter/material.dart';
import 'pages/jsessionid_login_page.dart';

void main() {
  runApp(const JWCApp());
}

class JWCApp extends StatelessWidget {
  const JWCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '教务处登录系统',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const JSessionIdLoginPage(),
    );
  }
}
