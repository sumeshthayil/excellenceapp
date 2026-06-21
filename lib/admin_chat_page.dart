import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

class AdminChatPage extends StatefulWidget {
  final String studentId;
  final String studentName;

  const AdminChatPage({
    super.key,
    required this.studentId,
    required this.studentName,
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

  @override
  void initState() {
    super.initState();
    _subscribeToMessages();
  }

  Future<void> _downloadAndOpenFile(String filePath, String fileName) async {
  try {
    // Only request permission on Android 12 and below
    final androidVersion = await _getAndroidVersion();
    if (androidVersion <= 32) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission denied')),
          );
        }
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloading file...')),
      );
    }

    final bytes = await supabase.storage
        .from('channel-files')
        .download(filePath);

    final downloadsDir = Directory('/storage/emulated/0/Download/ExcellenceTutoring');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }

    final localFile = File('${downloadsDir.path}/$fileName');
    await localFile.writeAsBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to Downloads: $fileName')),
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

Future<int> _getAndroidVersion() async {
  try {
    final version = await const MethodChannel('flutter/platform')
        .invokeMethod<String>('getAndroidVersion');
    return int.tryParse(version ?? '33') ?? 33;
  } catch (_) {
    return 33; // assume modern Android if unknown
  }
}
  Future<void> _loadMessages() async {
    final data = await supabase
        .from('messages')
        .select()
        .eq('student_id', widget.studentId)
        .order('created_at', ascending: true);

    setState(() => _messages = List<Map<String, dynamic>>.from(data));
    _scrollToBottom();
  }

  void _subscribeToMessages() {
    supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('student_id', widget.studentId)
        .order('created_at', ascending: true)
        .listen((data) {
          setState(() => _messages = List<Map<String, dynamic>>.from(data));
          _scrollToBottom();
        });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final adminId = supabase.auth.currentUser!.id;
      final newMessage = {
        'student_id': widget.studentId,
        'sent_by': adminId,
        'sender_role': 'admin',
        'text_content': text,
        'created_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('messages').insert(newMessage);
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
      final adminId = supabase.auth.currentUser!.id;
      final file = File(picked.path);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      final filePath = '$adminId/$fileName';

      await supabase.storage
          .from('channel-files')
          .upload(filePath, file);

      final newMessage = {
        'student_id': widget.studentId,  // was adminId, now correct
        'sent_by': adminId,
        'sender_role': 'admin',
        'file_name': picked.name,
        'file_path': filePath,
        'file_type': 'image',
        'created_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('messages').insert(newMessage);
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
    final adminId = supabase.auth.currentUser!.id;
    final bytes = await file.readAsBytes();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final filePath = '$adminId/$fileName';

    await supabase.storage
        .from('channel-files')
        .uploadBinary(filePath, bytes);

    final newMessage = {
      'student_id': widget.studentId,  // was adminId, now correct
      'sent_by': adminId,
      'sender_role': 'admin',
      'file_name': file.name,
      'file_path': filePath,
      'file_type': 'file',
      'created_at': DateTime.now().toIso8601String(),
    };

    await supabase.from('messages').insert(newMessage);
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

  Widget _buildMessage(Map<String, dynamic> message) {
    final isAdmin = message['sender_role'] == 'admin';
    final hasText = message['text_content'] != null;
    final hasImage =
        message['file_type'] == 'image' && message['file_path'] != null;
    final hasFile = message['file_type'] == 'file' && message['file_path'] != null;


    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isAdmin ? Colors.blue : Colors.grey[200],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isAdmin ? 16 : 4),
            bottomRight: Radius.circular(isAdmin ? 4 : 16),
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
                        color: isAdmin ? Colors.white : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message['file_name'] ?? 'File',
                          style: TextStyle(
                            color: isAdmin ? Colors.white : Colors.black87,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (hasText)
                Text(
                  message['text_content'],
                  style: TextStyle(
                    color: isAdmin ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                ),
            ],
          ),
        ),
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
                  // Attach file button
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