import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_chat_page.dart';

class TutorHomePage extends StatefulWidget {
  const TutorHomePage({super.key});

  @override
  State<TutorHomePage> createState() => _TutorHomePageState();
}

class _TutorHomePageState extends State<TutorHomePage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudents();
    _subscribeToMessages();
  }

Future<void> _loadStudents() async {
  try {
    final tutorId = supabase.auth.currentUser!.id;
    print('DEBUG tutor id: $tutorId');

    final assignments = await supabase
        .from('tutor_students')
        .select('student_id')
        .eq('tutor_id', tutorId);

    print('DEBUG assignments: $assignments');

    final studentIds = assignments
        .map((a) => a['student_id'] as String)
        .toList();

    print('DEBUG studentIds: $studentIds');

    if (studentIds.isEmpty) {
      setState(() {
        _students = [];
        _isLoading = false;
      });
      return;
    }

    final profiles = await supabase
        .from('profiles')
        .select('id, full_name')
        .inFilter('id', studentIds)
        .order('full_name', ascending: true);

    print('DEBUG profiles: $profiles');

    List<Map<String, dynamic>> students = [];
    for (final profile in profiles) {
      final messages = await supabase
          .from('messages')
          .select()
          .eq('student_id', profile['id'])
          .order('created_at', ascending: false)
          .limit(1);

      students.add({
        'id': profile['id'],
        'full_name': profile['full_name'],
        'last_message': messages.isNotEmpty ? messages[0] : null,
      });
    }

    students.sort((a, b) {
      if (a['last_message'] == null && b['last_message'] == null) return 0;
      if (a['last_message'] == null) return 1;
      if (b['last_message'] == null) return -1;
      return (b['last_message']['created_at'] as String)
          .compareTo(a['last_message']['created_at'] as String);
    });

    setState(() {
      _students = students;
      _isLoading = false;
    });
  } catch (e) {
    print('Load students error: $e');
    setState(() => _isLoading = false);
  }
}

  void _subscribeToMessages() {
    supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen((data) {
          _loadStudents();
        });
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.parse(isoString).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);

    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour < 12 ? 'AM' : 'PM';
    final timeStr = '$hour:$min $amPm';

    if (msgDay == today) {
      return timeStr;
    } else if (msgDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $timeStr';
    } else {
      final months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.year == now.year ? "" : "${dt.year} "}${months[dt.month - 1]} ${dt.day}';
    }
  }

  String _lastMessagePreview(Map<String, dynamic>? message) {
    if (message == null) return 'No messages yet';
    if (message['text_content'] != null) return message['text_content'];
    if (message['file_type'] == 'image') return '📷 Image';
    return '📎 File';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excellence Tutoring'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? const Center(
                  child: Text(
                    'No students assigned yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  itemCount: _students.length,
                  separatorBuilder: (context, index) => const Divider(
                    height: 1,
                    indent: 72,
                  ),
                  itemBuilder: (context, index) {
                    final student = _students[index];
                    final lastMessage = student['last_message'];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text(
                          student['full_name'][0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        student['full_name'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _lastMessagePreview(lastMessage),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      trailing: Text(
                        _formatTime(lastMessage?['created_at']),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminChatPage(
                              studentId: student['id'],
                              studentName: student['full_name'],
                              viewerRole: 'tutor',
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}