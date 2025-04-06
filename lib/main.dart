import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:project_x/screen/AddCommentPage.dart';
import 'package:project_x/screen/ToiletProvider.dart';
import 'package:project_x/screen/welcome_screen.dart'; // Welcome screen import
import 'package:provider/provider.dart';
import 'screen/login_page.dart'; // Login page import
import 'screen/home_page.dart'; // HomePage import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: WelcomePage(), // ✅ Corrected Class Name
    );
  }
}
