import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VideoComments extends StatefulWidget {
  final String videoId;
  final List<Map<String, dynamic>> comments;
  final int commentsCount;
  final Function(String) onAddComment;

  const VideoComments({
    Key? key,
    required this.videoId,
    required this.comments,
    required this.commentsCount,
    required this.onAddComment,
  }) : super(key: key);

  @override
  _VideoCommentsState createState() => _VideoCommentsState();
}

class _VideoCommentsState extends State<VideoComments> {
  final TextEditingController _commentController = TextEditingController();
  final _supabase = Supabase.instance.client;
  String? _currentUserId;
  List<Map<String, dynamic>> _comments = [];
  final ScrollController _scrollController = ScrollController();
  bool _isVideoOwner = false;
  bool _isDeletingComment = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = _supabase.auth.currentUser?.id;
    _comments = widget.comments.map((comment) {
      return {
        ...comment,
        'likes_count': comment['likesCount'] ?? 0,
        'is_liked': false,
      };
    }).toList();
    _checkVideoOwnership();
    _loadCommentLikes();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkVideoOwnership() async {
    if (_currentUserId == null) return;

    try {
      final response = await _supabase
          .from('user_videos')
          .select('user_id')
          .eq('id', widget.videoId)
          .single();
      setState(() {
        _isVideoOwner = response['user_id'] == _currentUserId;
      });
    } catch (e) {
      print('Error checking video ownership: $e');
    }
  }

  Future<void> _loadCommentLikes() async {
    if (_currentUserId == null) return;

    try {
      final commentIds = _comments.map((c) => c['id']).toList();
      if (commentIds.isEmpty) return;

      final response = await _supabase
          .from('comment_likes')
          .select('comment_id')
          .eq('user_id', _currentUserId!)
          .inFilter('comment_id', commentIds);

      final likedCommentIds = response.map((like) => like['comment_id'].toString()).toSet();

      setState(() {
        _comments = _comments.map((comment) {
          return {
            ...comment,
            'is_liked': likedCommentIds.contains(comment['id']),
          };
        }).toList();
      });
    } catch (e) {
      print('Error loading comment likes: $e');
    }
  }

  Future<void> _toggleCommentLike(String commentId) async {
    if (_currentUserId == null) return;

    try {
      final commentIndex = _comments.indexWhere((c) => c['id'] == commentId);
      if (commentIndex == -1) return;

      final isLiked = _comments[commentIndex]['is_liked'] ?? false;
      final currentLikesCount = _comments[commentIndex]['likes_count'] ?? 0;

      if (isLiked) {
        await _supabase
            .from('comment_likes')
            .delete()
            .eq('comment_id', commentId)
            .eq('user_id', _currentUserId!);

        setState(() {
          _comments[commentIndex] = {
            ..._comments[commentIndex],
            'is_liked': false,
            'likes_count': currentLikesCount - 1,
          };
        });
      } else {
        await _supabase.from('comment_likes').insert({
          'comment_id': commentId,
          'user_id': _currentUserId!,
          'created_at': DateTime.now().toIso8601String(),
        });

        setState(() {
          _comments[commentIndex] = {
            ..._comments[commentIndex],
            'is_liked': true,
            'likes_count': currentLikesCount + 1,
          };
        });
      }
    } catch (e) {
      print('Error toggling comment like: $e');
      _loadCommentLikes();
    }
  }

  Future<void> _addComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty || _currentUserId == null) return;

    try {
      final userProfile = await _supabase
          .from('profiles')
          .select('username, avatar_url')
          .eq('id', _currentUserId!)
          .single();

      final newComment = {
         // Генерация UUID
        'video_id': widget.videoId, // Исправлено: добавлена точка перед videoId
        'user_id': _currentUserId,
        'content': commentText,
        'username': userProfile['username'] ?? 'Anonymous',
        'avatar_url': userProfile['avatar_url'] ?? 'https://example.com/default_avatar.png',
        'created_at': DateTime.now().toIso8601String(), // Стандартизированный формат даты
        'likes_count': 0,
        'is_liked': false,
      };

      widget.onAddComment(commentText);

      final response = await _supabase.from('video_comments').insert({
        'video_id': widget.videoId,
        'user_id': _currentUserId,
        'username': userProfile['username'],
        'content': commentText,
      }).select('id').single();

      setState(() {
        newComment['id'] = response['id'].toString();
        _comments.insert(0, newComment);
      });

      _commentController.clear();
      FocusScope.of(context).unfocus();

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      print('Error adding comment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding comment: $e')),
      );
    }
  }

  Future<void> deleteComment(String commentId) async {
    if (_isDeletingComment) {
      print('Delete comment skipped due to ongoing operation');
      return;
    }

    setState(() {
      _isDeletingComment = true;
    });

    try {
      final commentIndex = _comments.indexWhere((c) => c['id'] == commentId);
      if (commentIndex == -1) {
        print('Comment not found: $commentId');
        return;
      }

      final isOwnComment = _comments[commentIndex]['user_id'] == _currentUserId;
      if (!isOwnComment && !_isVideoOwner) {
        print('User not authorized to delete comment: $commentId');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are not authorized to delete this comment')),
        );
        return;
      }

      // Delete associated likes
      await _supabase
          .from('comment_likes')
          .delete()
          .eq('comment_id', commentId);

      // Delete the comment
      await _supabase
          .from('video_comments')
          .delete()
          .eq('id', commentId);

      setState(() {
        _comments.removeAt(commentIndex);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment deleted')),
      );
    } catch (e) {
      print('Error deleting comment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting comment: $e')),
      );
    } finally {
      setState(() {
        _isDeletingComment = false;
      });
    }
  }

  Future<bool?> _showDeleteConfirmationDialog(String commentId) async {
    final isLightTheme = Theme.of(context).brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isLightTheme ? Colors.white : Colors.grey[850],
          title: Text(
            'Confirm Deletion',
            style: TextStyle(color: textColor),
          ),
          content: Text(
            'Are you sure you want to delete this comment?',
            style: TextStyle(color: textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: textColor)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLightTheme ? Colors.white : Colors.black,
      appBar: AppBar(
        backgroundColor: isLightTheme ? Colors.blue : Colors.black,
        elevation: 0,
        title: Text(
          'Comments (${_comments.length})',
          style: TextStyle(color: isLightTheme ? Colors.black : Colors.white),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isLightTheme ? Colors.black : Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              itemCount: _comments.length,
              itemBuilder: (context, index) {
                final comment = _comments[index];
                final avatarUrl = comment['avatar_url']?.toString() ?? 'https://example.com/default_avatar.png';
                final username = comment['username']?.toString() ?? 'Anonymous';
                final content = comment['content']?.toString() ?? '';
                final createdAt = comment['created_at']?.toString() ?? DateTime.now().toString();
                final likesCount = comment['likes_count'] ?? 0;
                final isLiked = comment['is_liked'] ?? false;
                final isOwnComment = comment['user_id'] == _currentUserId;
                final canDelete = isOwnComment || _isVideoOwner;

                return Dismissible(
                  key: Key(comment['id']),
                  direction: canDelete ? DismissDirection.endToStart : DismissDirection.none,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await _showDeleteConfirmationDialog(comment['id']);
                  },
                  onDismissed: (direction) {
                    deleteComment(comment['id']);
                  },
                  child: GestureDetector(
                    onLongPress: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: isLightTheme ? Colors.white : Colors.grey[850],
                        builder: (context) {
                          return SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canDelete)
                                  ListTile(
                                    leading: const Icon(Icons.delete, color: Colors.red),
                                    title: Text(
                                      'Delete',
                                      style: TextStyle(color: isLightTheme ? Colors.black : Colors.white),
                                    ),
                                    onTap: () async {
                                      Navigator.pop(context);
                                      final confirmed = await _showDeleteConfirmationDialog(comment['id']);
                                      if (confirmed == true) {
                                        deleteComment(comment['id']);
                                      }
                                    },
                                  ),
                                ListTile(
                                  leading: Icon(Icons.cancel, color: isLightTheme ? Colors.black : Colors.white),
                                  title: Text(
                                    'Cancel',
                                    style: TextStyle(color: isLightTheme ? Colors.black : Colors.white),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: NetworkImage(avatarUrl),
                            backgroundColor: Colors.grey[800],
                            child: avatarUrl.contains('default_avatar')
                                ? Text(username[0].toUpperCase(), style: TextStyle(color: Colors.white))
                                : null,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  username,
                                  style: TextStyle(
                                    color: isLightTheme ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  content,
                                  style: TextStyle(color: isLightTheme ? Colors.black : Colors.white),
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      _formatDate(DateTime.parse(createdAt)),
                                      style: TextStyle(color: Colors.grey, fontSize: 12),
                                    ),
                                    SizedBox(width: 16),
                                    IconButton(
                                      icon: Icon(
                                        isLiked ? Icons.favorite : Icons.favorite_border,
                                        color: isLiked ? Colors.red : Colors.grey,
                                        size: 20,
                                      ),
                                      onPressed: () => _toggleCommentLike(comment['id']),
                                    ),
                                    Text(
                                      '$likesCount',
                                      style: TextStyle(
                                        color: isLightTheme ? Colors.black : Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (canDelete)
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                        onPressed: () async {
                                          final confirmed = await _showDeleteConfirmationDialog(comment['id']);
                                          if (confirmed == true) {
                                            deleteComment(comment['id']);
                                          }
                                        },
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
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isLightTheme ? Colors.grey[300] : Colors.grey[900],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _commentController,
                      style: TextStyle(color: isLightTheme ? Colors.black : Colors.white),
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                        border: InputBorder.none,
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                      ),
                      onSubmitted: (value) => _addComment(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.blue),
                  onPressed: _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')} · ${date.day}/${date.month}/${date.year}';
  }
}