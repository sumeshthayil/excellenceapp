import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AdminChatPage extends StatefulWidget {
  final String studentId;
  final String studentName;
  // 'admin' or 'tutor' — who is viewing this chat page right now.
  // Drives which side bubbles land on and whether a sender name is shown.
  final String viewerRole;

  const AdminChatPage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.viewerRole,
  });

  @override
  State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final supabase = Supabase.instance.client;
  final _imagePicker = ImagePicker();
  bool _isSending = false;
  List<Map<String, dynamic>> _messages = [];

  // Cache of tutor_id -> full_name, so we don't re-fetch on every rebuild.
  final Map<String, String> _tutorNameCache = {};

  @override
  void initState() {
    super.initState();
    _subscribeToMessages();
  }

  Future<void> _downloadAndOpenFile(String filePath, String fileName) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloading file...')),
        );
      }

      final bytes = await supabase.storage
          .from('channel-files')
          .download(filePath);

      final cacheDir = Directory(
        '${(await getTemporaryDirectory()).path}/ExcellenceTutoring',
      );
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final safeFileName = filePath.replaceAll('/', '_');
      final localFile = File('${cacheDir.path}/$safeFileName');
      await localFile.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening $fileName...')),
        );
      }

      await OpenFilex.open(localFile.path);
    } catch (e) {
      print('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _shareFile(String filePath, String fileName) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing file to share...')),
        );
      }

      final bytes = await supabase.storage
          .from('channel-files')
          .download(filePath);

      final cacheDir = Directory(
        '${(await getTemporaryDirectory()).path}/ExcellenceTutoring',
      );
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final safeFileName = filePath.replaceAll('/', '_');
      final localFile = File('${cacheDir.path}/$safeFileName');
      await localFile.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(localFile.path, name: fileName)],
        subject: fileName,
      );
    } catch (e) {
      print('Share error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _subscribeToMessages() {
    supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('student_id', widget.studentId)
        .order('created_at', ascending: false)
        .listen((data) {
          setState(() => _messages = List<Map<String, dynamic>>.from(data));
        });
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.parse(isoString).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);

    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    final time = '$hour:$minute $period';

    if (msgDay == today) {
      return 'Today $time';
    } else if (msgDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $time';
    } else {
      final months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.year == now.year ? "" : "${dt.year} "}${months[dt.month - 1]} ${dt.day}, $time';
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final senderId = supabase.auth.currentUser!.id;
      await supabase.from('messages').insert({
        'student_id': widget.studentId,
        'sent_by': senderId,
        'sender_role': widget.viewerRole, // 'admin' or 'tutor'
        'text_content': text,
      });
    } catch (e) {
      print('Send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked == null) return;

    setState(() => _isSending = true);

    try {
      final senderId = supabase.auth.currentUser!.id;
      final file = File(picked.path);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      final filePath = '$senderId/$fileName';

      await supabase.storage.from('channel-files').upload(filePath, file);

      await supabase.from('messages').insert({
        'student_id': widget.studentId,
        'sent_by': senderId,
        'sender_role': widget.viewerRole,
        'file_name': picked.name,
        'file_path': filePath,
        'file_type': 'image',
      });
    } catch (e) {
      print('Image send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendFile() async {
    const typeGroup = XTypeGroup(
      label: 'files',
      extensions: ['pdf', 'doc', 'docx', 'txt'],
    );

    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    setState(() => _isSending = true);

    try {
      final senderId = supabase.auth.currentUser!.id;
      final bytes = await file.readAsBytes();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final filePath = '$senderId/$fileName';

      await supabase.storage.from('channel-files').uploadBinary(filePath, bytes);

      await supabase.from('messages').insert({
        'student_id': widget.studentId,
        'sent_by': senderId,
        'sender_role': widget.viewerRole,
        'file_name': file.name,
        'file_path': filePath,
        'file_type': 'file',
      });
    } catch (e) {
      print('File send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<String> _getSignedUrl(String filePath) async {
    final response = await supabase.storage
        .from('channel-files')
        .createSignedUrl(filePath, 60 * 60);
    return response;
  }

  // Looks up (and caches) a tutor's display name from the profiles table.
  Future<String> _getTutorName(String tutorId) async {
    if (_tutorNameCache.containsKey(tutorId)) {
      return _tutorNameCache[tutorId]!;
    }
    try {
      final data = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', tutorId)
          .single();
      final name = (data['full_name'] as String?) ?? 'Tutor';
      _tutorNameCache[tutorId] = name;
      return name;
    } catch (e) {
      return 'Tutor';
    }
  }

  // Decides bubble side + whether to show a sender name, based on:
  // - who is viewing (widget.viewerRole)
  // - who sent the message (sender_role, sent_by)
  ({bool isRight, bool showName}) _bubblePlacement(Map<String, dynamic> message) {
    final senderRole = message['sender_role'];
    final sentBy = message['sent_by'];
    final currentUserId = supabase.auth.currentUser?.id;

    if (widget.viewerRole == 'tutor') {
      // Student -> left. All staff (self, other tutors, admin) -> right, no name.
      return (isRight: senderRole != 'student', showName: false);
    }

    // Admin viewer.
    if (senderRole == 'student') {
      return (isRight: false, showName: false);
    }
    if (sentBy == currentUserId) {
      // Own message -> right, no name.
      return (isRight: true, showName: false);
    }
    if (senderRole == 'tutor') {
      // Another tutor's message -> right, with name shown.
      return (isRight: true, showName: true);
    }
    // Fallback (e.g. another admin account) -> right, no name.
    return (isRight: true, showName: false);
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final placement = _bubblePlacement(message);
    final isRight = placement.isRight;
    final showName = placement.showName;
    final sentBy = message['sent_by'];

    final hasText = message['text_content'] != null;
    final hasImage = message['file_type'] == 'image' && message['file_path'] != null;
    final hasFile = message['file_type'] == 'file' && message['file_path'] != null;

    return Align(
      alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 2),
              child: FutureBuilder<String>(
                future: _getTutorName(sentBy),
                builder: (context, snapshot) {
                  return Text(
                    snapshot.data ?? '...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  );
                },
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isRight ? Colors.blue : Colors.grey[200],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isRight ? 16 : 4),
                bottomRight: Radius.circular(isRight ? 4 : 16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasImage)
                    FutureBuilder<String>(
                      future: _getSignedUrl(message['file_path']),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const SizedBox(
                            height: 150,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image),
                          ),
                        );
                      },
                    ),
                  if (hasFile)
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _downloadAndOpenFile(
                            message['file_path'],
                            message['file_name'] ?? 'file',
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.insert_drive_file_outlined,
                                color: isRight ? Colors.white : Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  message['file_name'] ?? 'File',
                                  style: TextStyle(
                                    color: isRight ? Colors.white : Colors.black87,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _shareFile(
                            message['file_path'],
                            message['file_name'] ?? 'file',
                          ),
                          child: Icon(
                            Icons.share,
                            size: 18,
                            color: isRight ? Colors.white70 : Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  if (hasText)
                    Text(
                      message['text_content'],
                      style: TextStyle(
                        color: isRight ? Colors.white : Colors.black87,
                        fontSize: 15,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      _formatDateTime(message['created_at']),
                      style: TextStyle(
                        fontSize: 11,
                        color: isRight ? Colors.white70 : Colors.black45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.studentName),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) =>
                          _buildMessage(_messages[index]),
                    ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_outlined, color: Colors.blue),
                    onPressed: _isSending ? null : _sendImage,
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Colors.blue),
                    onPressed: _isSending ? null : _sendFile,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: null,
                      onSubmitted: (_) => _sendTextMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blue),
                    onPressed: _isSending ? null : _sendTextMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}