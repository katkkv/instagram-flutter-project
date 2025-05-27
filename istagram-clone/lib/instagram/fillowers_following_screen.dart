import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/user_profile_screen.dart';

class FollowersFollowingScreen extends StatefulWidget {
  final String userId;
  final bool isFollowers;
  final ValueNotifier<ThemeData> themeNotifier;

  const FollowersFollowingScreen({
    Key? key,
    required this.userId,
    required this.isFollowers,
    required this.themeNotifier,
  }) : super(key: key);

  @override
  _FollowersFollowingScreenState createState() => _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen> {
  List<dynamic> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _userNotes = {};
  bool _isNoteSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _loadUserNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final response = widget.isFollowers
          ? await Supabase.instance.client
          .from('subscriptions')
          .select('follower_id')
          .eq('following_id', widget.userId)
          : await Supabase.instance.client
          .from('subscriptions')
          .select('following_id')
          .eq('follower_id', widget.userId);

      if (response is List) {
        final userIds = response
            .map((e) => e[widget.isFollowers ? 'follower_id' : 'following_id'])
            .toList();

        // Исключаем текущего пользователя из списка
        if (currentUserId != null) {
          userIds.remove(currentUserId);
        }

        if (userIds.isNotEmpty) {
          final usersResponse = await Supabase.instance.client
              .from('profiles')
              .select()
              .inFilter('id', userIds);

          setState(() {
            _users = usersResponse;
            _isLoading = false;
          });
        } else {
          setState(() {
            _users = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: ${e.toString()}')),
      );
    }
  }

  Future<void> _loadUserNotes() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('user_notes')
          .select('target_user_id, note_text')
          .eq('user_id', currentUserId);

      if (mounted) {
        setState(() {
          _userNotes.clear();
          for (var note in response) {
            if (note['note_text'] != null && note['note_text'].isNotEmpty) {
              _userNotes[note['target_user_id']] = note['note_text'];
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading notes: $e');
    }
  }

  Future<void> _showUserNoteDialog(String userId, String username) async {
    final currentNote = _userNotes[userId] ?? '';
    final TextEditingController noteController = TextEditingController(text: currentNote);
    final FocusNode focusNode = FocusNode();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: widget.themeNotifier.value.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: widget.themeNotifier.value.dividerColor,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Заметка о $username',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: noteController,
                  focusNode: focusNode,
                  maxLines: 5,
                  minLines: 1,
                  maxLength: 100,
                  decoration: InputDecoration(
                    hintText: 'Напишите заметку...',
                    hintStyle: TextStyle(color: widget.themeNotifier.value.hintColor),
                    border: InputBorder.none,
                  ),
                  style: TextStyle(color: widget.themeNotifier.value.textTheme.bodyLarge?.color),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    if (currentNote.isNotEmpty)
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            await _deleteNote(userId);
                            if (mounted) Navigator.pop(context);
                          },
                          child: const Text('Удалить'),
                        ),
                      ),
                    if (currentNote.isNotEmpty) const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          if (noteController.text.trim().isNotEmpty) {
                            await _saveNote(userId, noteController.text.trim());
                            if (mounted) Navigator.pop(context);
                          } else {
                            await _deleteNote(userId);
                            if (mounted) Navigator.pop(context);
                          }
                        },
                        child: const Text('Сохранить'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );

    focusNode.requestFocus();
  }

  Future<void> _saveNote(String targetUserId, String noteText) async {
    if (!mounted || _isNoteSaving) return;

    setState(() => _isNoteSaving = true);

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final existingNote = await Supabase.instance.client
          .from('user_notes')
          .select()
          .eq('user_id', currentUserId)
          .eq('target_user_id', targetUserId)
          .maybeSingle();

      if (existingNote != null) {
        await Supabase.instance.client.from('user_notes').update({
          'note_text': noteText,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existingNote['id']);
      } else {
        await Supabase.instance.client.from('user_notes').insert({
          'user_id': currentUserId,
          'target_user_id': targetUserId,
          'note_text': noteText,
        });
      }

      setState(() {
        _userNotes[targetUserId] = noteText;
      });
    } catch (e) {
      debugPrint('Save note error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isNoteSaving = false);
      }
    }
  }

  Future<void> _deleteNote(String targetUserId) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      await Supabase.instance.client
          .from('user_notes')
          .delete()
          .eq('user_id', currentUserId)
          .eq('target_user_id', targetUserId);

      if (mounted) {
        setState(() {
          _userNotes.remove(targetUserId);
        });
      }
    } catch (e) {
      debugPrint('Delete note error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _users.where((user) {
      final username = user['username']?.toLowerCase() ?? '';
      return username.contains(_searchQuery.toLowerCase());
    }).toList();

    return Theme(
      data: widget.themeNotifier.value,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: widget.themeNotifier.value.appBarTheme.backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back,
                color: widget.themeNotifier.value.iconTheme.color ??
                    (widget.themeNotifier.value.brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            widget.isFollowers ? 'Подписчики' : 'Подписки',
            style: TextStyle(
              color: widget.themeNotifier.value.textTheme.titleLarge?.color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  hintStyle: TextStyle(
                    color: widget.themeNotifier.value.hintColor,
                  ),
                  prefixIcon: Icon(Icons.search, color: widget.themeNotifier.value.iconTheme.color),
                  filled: true,
                  fillColor: widget.themeNotifier.value.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredUsers.isEmpty
                  ? Center(
                child: Text(
                  widget.isFollowers ? 'Нет подписчиков' : 'Нет подписок',
                  style: TextStyle(
                    color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                  ),
                ),
              )
                  : ListView.separated(
                itemCount: filteredUsers.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: widget.themeNotifier.value.dividerColor,
                ),
                itemBuilder: (context, index) {
                  final user = filteredUsers[index];
                  return ListTile(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfileScreen(
                            userId: user['id'],
                            themeNotifier: widget.themeNotifier,
                          ),
                        ),
                      );
                      await _fetchUsers();
                    },
                    leading: GestureDetector(
                      onLongPress: () => _showUserNoteDialog(user['id'], user['username'] ?? 'Без имени'),
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              gradient: _userNotes.containsKey(user['id'])
                                  ? const LinearGradient(
                                colors: [Colors.purple, Colors.orange, Colors.yellow],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                                  : null,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.themeNotifier.value.brightness == Brightness.light
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade700,
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              backgroundImage: NetworkImage(
                                user['avatar_url'] ?? '',
                                headers: {'Cache-Control': 'max-age=0'},
                              ),
                              radius: 24,
                            ),
                          ),
                          if (_userNotes.containsKey(user['id']))
                            const Positioned(
                              bottom: 0,
                              right: 0,
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: Colors.black,
                                child: Icon(Icons.note, color: Colors.white, size: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                    title: Text(
                      user['username'] ?? 'Без имени',
                      style: TextStyle(
                        color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      user['bio'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.themeNotifier.value.textTheme.bodyMedium?.color,
                      ),
                    ),
                    trailing: _buildFollowButton(user['id']),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowButton(String userId) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    // Не показываем кнопку подписки для текущего пользователя
    if (currentUserId == null || currentUserId == userId) {
      return const SizedBox.shrink();
    }

    // Здесь можно добавить логику проверки подписки
    return OutlinedButton(
      onPressed: () {
        // Логика подписки/отписки
      },
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: widget.themeNotifier.value.primaryColor,
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        'Подписаться',
        style: TextStyle(
          color: widget.themeNotifier.value.primaryColor,
          fontSize: 14,
        ),
      ),
    );
  }
}