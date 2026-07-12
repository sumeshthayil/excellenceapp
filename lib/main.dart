import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';
import 'student_chat_page.dart';
import 'admin_home_page.dart';
import 'tutor_home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://fmimqkqmyirwmfozmnlw.supabase.co',
    publishableKey: 'sb_publishable_hi9F7nAg3-nrbDT-F4qXxg_LIROHqhJ',
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
      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/student': (context) => const StudentChatPage(),
        '/admin': (context) => const AdminHomePage(),
        '/tutor': (context) => const TutorHomePage(),
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    // Give Supabase a moment to restore the session from secure storage
    await Future.delayed(Duration.zero);

    final session = Supabase.instance.client.auth.currentSession;

    if (!mounted) return;

    if (session == null) {
      // No active session — go to login
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    // Session exists — check the user's role
    final userId = session.user.id;
    final response = await Supabase.instance.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .single();

    if (!mounted) return;

    final role = response['role'] as String?;

    if (role == 'admin') {
      Navigator.of(context).pushReplacementNamed('/admin');
    } else if (role == 'tutor') {
      Navigator.of(context).pushReplacementNamed('/tutor');
    } else {
      Navigator.of(context).pushReplacementNamed('/student');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a splash/loading screen while checking auth
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}