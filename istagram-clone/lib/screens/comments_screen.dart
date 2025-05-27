import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_profile_screen.dart';

class CommentsScreen extends StatefulWidget {
  final String? photoId;
  final String? videoId;
  final Function(int) onCommentAdded;
  final ValueNotifier<ThemeData> themeNotifier;

  const CommentsScreen({
    required this.onCommentAdded,
    required this.themeNotifier,
    this.photoId,
    this.videoId,
    Key? key,
  }) : super(key: key);

  @override
  _CommentsScreenState createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> comments = [];
  final _supabase = Supabase.instance.client;
  String? _currentUserId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentUserId = _supabase.auth.currentUser?.id;
    fetchComments();
  }

  Future<void> fetchComments() async {
    setState(() => _isLoading = true);
    try {
      final table = widget.photoId != null ? 'comments' : 'video_comments';
      final column = widget.photoId != null ? 'photo_id' : 'video_id';
      final id = widget.photoId ?? widget.videoId;

      final response = await _supabase
          .from(table)
          .select('id, content, created_at, user_id, username, avatar_url, likes_count')
          .eq(column, id!)
          .order('created_at', ascending: false);

      final commentsWithLikes = await Future.wait(
        (response as List).map((comment) async {
          final isLiked = _currentUserId != null
              ? await checkIfCommentIsLiked(comment['id'], _currentUserId!)
              : false;

          return {
            'id': comment['id']?.toString() ?? '',
            'username': comment['username']?.toString() ?? 'Аноним',
            'content': comment['content']?.toString() ?? '',
            'created_at': comment['created_at']?.toString() ?? DateTime.now().toString(),
            'user_id': comment['user_id']?.toString() ?? '',
            'avatar_url': comment['avatar_url']?.toString() ?? 'https://example.com/default_avatar.png',
            'likes_count': (comment['likes_count'] as int?) ?? 0,
            'is_liked': isLiked,
          };
        }),
      );

      setState(() {
        comments = commentsWithLikes;
        _isLoading = false;
      });

      widget.onCommentAdded(comments.length);
    } catch (e) {
      print('Ошибка при загрузке комментариев: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<bool> checkIfCommentIsLiked(String commentId, String userId) async {
    final table = widget.photoId != null ? 'photo_comment_likes' : 'video_comment_likes';
    final response = await _supabase
        .from(table)
        .select()
        .eq('comment_id', commentId)
        .eq('user_id', userId);
    return response.isNotEmpty;
  }

  Future<void> _addComment() async {
    if (_commentController.text.isEmpty || _currentUserId == null) return;

    try {
      final profile = await _supabase
          .from('profiles')
          .select('username, avatar_url')
          .eq('id', _currentUserId!)
          .single();

      final table = widget.photoId != null ? 'comments' : 'video_comments';
      final column = widget.photoId != null ? 'photo_id' : 'video_id';
      final id = widget.photoId ?? widget.videoId;

      // Отправляем комментарий на сервер
      final response = await _supabase.from(table).insert({
        column: id,
        'user_id': _currentUserId,
        'content': _commentController.text,
        'username': profile['username'] ?? 'Аноним',
        'avatar_url': profile['avatar_url'] ?? 'https://example.com/default_avatar.png',
        'likes_count': 0,
      }).select('id, content, created_at, user_id, username, avatar_url, likes_count').single();

      // Создаем новый комментарий для локального отображения
      final newComment = {
        'id': response['id'].toString(),
        'username': response['username'] ?? 'Аноним',
        'content': response['content'] ?? '',
        'created_at': response['created_at'] ?? DateTime.now().toString(),
        'user_id': response['user_id'] ?? '',
        'avatar_url': response['avatar_url'] ?? 'https://example.com/default_avatar.png',
        'likes_count': response['likes_count'] ?? 0,
        'is_liked': false,
      };

      // Добавляем комментарий в начало списка
      setState(() {
        comments = [newComment, ...comments];
        _commentController.clear();
      });

      // Запрашиваем актуальное количество комментариев
      final commentsCountResponse = await _supabase
          .from(table)
          .select('id')
          .eq(column, id!);

      widget.onCommentAdded(commentsCountResponse.length);
    } catch (e) {
      print('Ошибка при добавлении комментария: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при добавлении комментария: $e')),
      );
    }
  }

  Future<void> deleteComment(String commentId) async {
    try {
      final table = widget.photoId != null ? 'comments' : 'video_comments';
      await _supabase.from(table).delete().eq('id', commentId);

      // Получаем новое количество комментариев
      final column = widget.photoId != null ? 'photo_id' : 'video_id';
      final id = widget.photoId ?? widget.videoId;
      final response = await _supabase
          .from(table)
          .select('id')
          .eq(column, id!);

      setState(() {
        comments = comments.where((comment) => comment['id'] != commentId).toList();
      });
      widget.onCommentAdded(response.length);
    } catch (e) {
      print('Ошибка при удалении комментария: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при удалении комментария: $e')),
      );
    }
  }

  Future<void> _submitReport(String commentId, String reason) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      await _supabase.from('comment_reports').insert({
        'comment_id': commentId,
        'comment_type': widget.photoId != null ? 'photo_comment' : 'video_comment',
        'reported_by': currentUser.id,
        'reason': reason,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Жалоба отправлена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при отправке жалобы: $e')),
        );
      }
    }
  }

  void _showReportDialog(String commentId) {
    final TextEditingController reasonController = TextEditingController();
    final theme = widget.themeNotifier.value;
    final textColor = theme.brightness == Brightness.light ? Colors.black87 : Colors.white;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.scaffoldBackgroundColor,
          title: Text(
            'Пожаловаться на комментарий',
            style: TextStyle(color: textColor),
          ),
          content: TextField(
            controller: reasonController,
            decoration: InputDecoration(
              hintText: 'Причина жалобы',
              hintStyle: TextStyle(color: textColor.withOpacity(0.6)),
            ),
            style: TextStyle(color: textColor),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена', style: TextStyle(color: textColor)),
            ),
            TextButton(
              onPressed: () {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Укажите причину жалобы')),
                  );
                  return;
                }
                Navigator.pop(context);
                _submitReport(commentId, reason);
              },
              child: Text(
                'Отправить',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleLike(Map<String, dynamic> comment) async {
    if (_currentUserId == null) return;

    try {
      final table = widget.photoId != null ? 'photo_comment_likes' : 'video_comment_likes';
      final commentsTable = widget.photoId != null ? 'comments' : 'video_comments';

      // Копируем список комментариев
      final updatedComments = List<Map<String, dynamic>>.from(comments);
      final commentIndex = updatedComments.indexWhere((c) => c['id'] == comment['id']);

      if (commentIndex == -1) return;

      if (comment['is_liked']) {
        // Удаляем лайк
        await _supabase
            .from(table)
            .delete()
            .eq('comment_id', comment['id'])
            .eq('user_id', _currentUserId!);
        await _supabase
            .from(commentsTable)
            .update({'likes_count': comment['likes_count'] - 1})
            .eq('id', comment['id']);

        // Обновляем локальное состояние
        updatedComments[commentIndex] = {
          ...updatedComments[commentIndex],
          'is_liked': false,
          'likes_count': comment['likes_count'] - 1,
        };
      } else {
        // Добавляем лайк
        await _supabase.from(table).insert({
          'comment_id': comment['id'],
          'user_id': _currentUserId!,
        });
        await _supabase
            .from(commentsTable)
            .update({'likes_count': comment['likes_count'] + 1})
            .eq('id', comment['id']);

        // Обновляем локальное состояние
        updatedComments[commentIndex] = {
          ...updatedComments[commentIndex],
          'is_liked': true,
          'likes_count': comment['likes_count'] + 1,
        };
      }

      // Обновляем состояние с новым списком
      setState(() {
        comments = updatedComments;
      });
    } catch (e) {
      print('Ошибка при изменении лайка: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при изменении лайка: $e')),
      );
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Удалить комментарий?"),
        content: const Text("Вы уверены, что хотите удалить этот комментарий?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Отмена"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Удалить", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${date.day}.${date.month}.${date.year}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}ч назад';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}м назад';
    } else {
      return 'только что';
    }
  }

  void _openUserProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: userId,
          themeNotifier: widget.themeNotifier,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeNotifier.value;
    final isLightTheme = theme.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;
    final secondaryTextColor = isLightTheme ? Colors.black54 : Colors.white70;

    return Scaffold(
      appBar: AppBar(
        title: Text('Комментарии', style: TextStyle(color: textColor)),
        backgroundColor: theme.appBarTheme.backgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : comments.isEmpty
                ? Center(
              child: Text(
                'Нет комментариев',
                style: TextStyle(color: textColor),
              ),
            )
                : ListView.builder(
              itemCount: comments.length,
              itemBuilder: (context, index) {
                final comment = comments[index];
                final isCurrentUserComment = comment['user_id'] == _currentUserId;

                return Dismissible(
                  key: Key(comment['id']),
                  direction: isCurrentUserComment
                      ? DismissDirection.endToStart
                      : DismissDirection.none,
                  background: isCurrentUserComment
                      ? Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  )
                      : null,
                  confirmDismiss: isCurrentUserComment
                      ? (direction) => _confirmDelete(context)
                      : null,
                  onDismissed: isCurrentUserComment
                      ? (direction) => deleteComment(comment['id'])
                      : null,
                  child: GestureDetector(
                    onLongPress: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: theme.scaffoldBackgroundColor,
                        builder: (context) {
                          return SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.report, color: Colors.red),
                                  title: Text(
                                    'Пожаловаться',
                                    style: TextStyle(color: textColor),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showReportDialog(comment['id']);
                                  },
                                ),
                                ListTile(
                                  leading: Icon(Icons.cancel, color: textColor),
                                  title: Text(
                                    'Отмена',
                                    style: TextStyle(color: textColor),
                                  ),
                                  onTap: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _openUserProfile(comment['user_id']),
                            child: CircleAvatar(
                              backgroundImage: NetworkImage(comment['avatar_url']),
                              radius: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      comment['username'],
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatDate(DateTime.parse(comment['created_at'])),
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  comment['content'],
                                  style: TextStyle(color: textColor, fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        comment['is_liked']
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: comment['is_liked']
                                            ? Colors.red
                                            : secondaryTextColor,
                                        size: 20,
                                      ),
                                      onPressed: () => _toggleLike(comment),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${comment['likes_count']}',
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Добавьте комментарий...',
                      hintStyle: TextStyle(color: textColor.withOpacity(0.6)),
                      filled: true,
                      fillColor: isLightTheme ? Colors.grey[200] : Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    style: TextStyle(color: textColor),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: theme.colorScheme.primary),
                  onPressed: _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
    );
  }
}