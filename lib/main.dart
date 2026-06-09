import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';
import 'student_chat_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

await Supabase.initialize(
    url: 'https://fmimqkqmyirwmfozmnlw.supabase.co',
    publishableKey : 'sb_publishable_hi9F7nAg3-nrbDT-F4qXxg_LIROHqhJ',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Excellence Tutoring',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginPage(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/student': (context) => const StudentChatPage(),
        '/admin': (context) => const Scaffold(
              body: Center(child: Text('Admin home coming soon!')),
            ),
      },
    );
  }
}