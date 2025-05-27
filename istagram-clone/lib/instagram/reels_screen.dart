import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:newinstagramclone/instagram/profile_scree.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/user_profile_screen.dart';

class ReelsScreen extends StatefulWidget {
  final ValueNotifier<ThemeData> themeNotifier;

  const ReelsScreen({Key? key, required this.themeNotifier}) : super(key: key);

  @override
  _ReelsScreenState createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  Future<List<Map<String, dynamic>>> videos = Future.value([]);
  final Map<String, bool> _likedVideos = {};
  final Map<String, int> _likesCount = {};
  final Map<String, bool> _likedComments = {};
  final Map<String, int> _commentLikesCount = {};
  bool _isReportingVideo = false;

  @override
  void initState() {
    super.initState();
    videos = fetchVideos();
    loadLikedVideos();
    fetchLikesStatus();
    fetchCommentLikesStatus();
  }

  Future<List<Map<String, dynamic>>> fetchVideos() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];

      final subscriptionsResponse = await Supabase.instance.client
          .from('subscriptions')
          .select('following_id')
          .eq('follower_id', user.id)
          .timeout(const Duration(seconds: 10));

      if (subscriptionsResponse.isEmpty) return [];

      final subscribedUserIds = subscriptionsResponse
          .map((sub) => sub['following_id'] as String)
          .toList();

      final videosResponse = await Supabase.instance.client
          .from('user_videos')
          .select('id, video_url, user_id, description, profiles!user_videos_user_id_fkey(username)')
          .inFilter('user_id', subscribedUserIds)
          .order('created_at', ascending: false)
          .limit(3)
          .timeout(const Duration(seconds: 10));

      final videoList = videosResponse.map<Map<String, dynamic>>((video) {
        return {
          'id': video['id'] as String,
          'video_url': video['video_url'] as String? ?? '',
          'user_id': video['user_id'] as String,
          'user_name': (video['profiles'] as Map<String, dynamic>?)?['username'] as String? ?? 'Unknown User',
          'description': video['description'] as String? ?? '',
          'comments': [],
        };
      }).toList();

      for (var video in videoList) {
        final commentsResponse = await Supabase.instance.client
            .from('video_comments')
            .select('id, content, username, user_id, created_at, comment_likes!inner(count)')
            .eq('video_id', video['id'])
            .limit(5)
            .timeout(const Duration(seconds: 10));

        video['comments'] = commentsResponse.map((comment) {
          return {
            'id': comment['id'] as String,
            'content': comment['content'] as String? ?? '',
            'username': comment['username'] as String? ?? 'Unknown',
            'user_id': comment['user_id'] as String,
            'likesCount': ((comment['comment_likes'] as List<dynamic>?)?[0] as Map<String, dynamic>?)?['count'] as int? ?? 0,
          };
        }).toList();
      }

      return videoList;
    } catch (e) {
      debugPrint('Error fetching videos: $e');
      return [];
    }
  }

  Future<void> loadLikedVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final likedVideosJson = prefs.getString('likedVideos');
    final likesCountJson = prefs.getString('likesCount');

    if (likedVideosJson != null) {
      final Map<String, bool> loadedLikes = {};
      final parsed = Map<String, String>.from(json.decode(likedVideosJson));
      parsed.forEach((key, value) {
        loadedLikes[key] = value == 'true';
      });
      setState(() {
        _likedVideos.addAll(loadedLikes);
      });
    }

    if (likesCountJson != null) {
      final Map<String, int> loadedLikesCount = {};
      final parsedCount = Map<String, dynamic>.from(json.decode(likesCountJson));
      parsedCount.forEach((key, value) {
        loadedLikesCount[key] = value as int;
      });
      setState(() {
        _likesCount.addAll(loadedLikesCount);
      });
    }
  }

  Future<void> fetchLikesStatus() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final videosList = await fetchVideos();

    for (var video in videosList) {
      final videoId = video['id'];

      final response = await Supabase.instance.client
          .from('video_likes')
          .select('video_id')
          .eq('user_id', userId)
          .eq('video_id', videoId)
          .timeout(const Duration(seconds: 10));

      setState(() {
        _likedVideos[videoId] = response.isNotEmpty;
      });

      final likesResponse = await Supabase.instance.client
          .from('video_likes')
          .select('video_id')
          .eq('video_id', videoId)
          .timeout(const Duration(seconds: 10));

      final likeCount = likesResponse.length;

      setState(() {
        _likesCount[videoId] = likeCount;
      });
    }
  }

  Future<void> fetchCommentLikesStatus() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final myLikes = await Supabase.instance.client
          .from('comment_likes')
          .select('comment_id')
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 10));

      final commentsWithLikes = await Supabase.instance.client
          .from('video_comments')
          .select('id, comment_likes(count)')
          .timeout(const Duration(seconds: 10));

      setState(() {
        _likedComments.clear();
        _commentLikesCount.clear();

        for (final like in myLikes) {
          _likedComments[like['comment_id'] as String] = true;
        }

        for (final comment in commentsWithLikes) {
          _commentLikesCount[comment['id'] as String] =
          (comment['comment_likes'] as List).isEmpty ? 0 : (comment['comment_likes'][0] as Map)['count'] as int;
        }
      });
    } catch (e) {
      debugPrint('Error fetching comment likes status: $e');
    }
  }

  Future<void> toggleLike(String videoId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('video_likes')
          .select('video_id')
          .eq('video_id', videoId)
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      final videoResponse = await Supabase.instance.client
          .from('user_videos')
          .select('likes_count')
          .eq('id', videoId)
          .single()
          .timeout(const Duration(seconds: 10));

      final currentLikesCount = videoResponse['likes_count'] ?? 0;

      if (response == null) {
        await Supabase.instance.client
            .from('video_likes')
            .insert({'video_id': videoId, 'user_id': userId})
            .timeout(const Duration(seconds: 10));

        await Supabase.instance.client
            .from('user_videos')
            .update({'likes_count': currentLikesCount + 1})
            .eq('id', videoId)
            .timeout(const Duration(seconds: 10));

        setState(() {
          _likedVideos[videoId] = true;
          _likesCount[videoId] = currentLikesCount + 1;
        });
      } else {
        await Supabase.instance.client
            .from('video_likes')
            .delete()
            .eq('video_id', videoId)
            .eq('user_id', userId)
            .timeout(const Duration(seconds: 10));

        await Supabase.instance.client
            .from('user_videos')
            .update({'likes_count': currentLikesCount - 1})
            .eq('id', videoId)
            .timeout(const Duration(seconds: 10));

        setState(() {
          _likedVideos[videoId] = false;
          _likesCount[videoId] = currentLikesCount - 1;
        });
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }

    saveLikedVideos();
  }

  Future<void> toggleCommentLike(String commentId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final isLiked = _likedComments[commentId] ?? false;
      final currentLikesCount = _commentLikesCount[commentId] ?? 0;

      if (isLiked) {
        await Supabase.instance.client
            .from('comment_likes')
            .delete()
            .eq('comment_id', commentId)
            .eq('user_id', userId)
            .timeout(const Duration(seconds: 10));

        setState(() {
          _likedComments.remove(commentId);
          _commentLikesCount[commentId] = currentLikesCount - 1;
        });
      } else {
        await Supabase.instance.client
            .from('comment_likes')
            .insert({
          'comment_id': commentId,
          'user_id': userId,
          'created_at': DateTime.now().toIso8601String(),
        })
            .timeout(const Duration(seconds: 10));

        setState(() {
          _likedComments[commentId] = true;
          _commentLikesCount[commentId] = currentLikesCount + 1;
        });
      }
    } catch (e) {
      debugPrint('Error toggling comment like: $e');
      fetchCommentLikesStatus();
    }
  }

  Future<void> saveLikedVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final likedVideosJson = _likedVideos.map((key, value) => MapEntry(key, value.toString()));
    prefs.setString('likedVideos', json.encode(likedVideosJson));
    prefs.setString('likesCount', json.encode(_likesCount));
  }

  Future<void> _submitVideoReport(String videoId, String reason) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isReportingVideo = true;
    });

    try {
      await Supabase.instance.client.from('video_reports').insert({
        'video_id': videoId,
        'reported_by': currentUser.id,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      }).timeout(const Duration(seconds: 10));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Жалоба на видео отправлена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при отправке жалобы: $e')),
        );
      }
    } finally {
      setState(() {
        _isReportingVideo = false;
      });
    }
  }

  void _showVideoReportDialog(String videoId) {
    final TextEditingController reasonController = TextEditingController();
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
          title: Text(
            'Пожаловаться на видео',
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
              onPressed: _isReportingVideo
                  ? null
                  : () {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Укажите причину жалобы')),
                  );
                  return;
                }
                Navigator.pop(context);
                _submitVideoReport(videoId, reason);
              },
              child: Text(
                _isReportingVideo ? 'Отправка...' : 'Отправить',
                style: TextStyle(color: _isReportingVideo ? Colors.grey : Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showVideoOptionsMenu(String videoId) {
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
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
                  _showVideoReportDialog(videoId);
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
  }

  Future<void> _refreshVideos() async {
    setState(() {
      videos = fetchVideos();
    });
    await videos; // Wait for videos to load
    await fetchLikesStatus();
    await fetchCommentLikesStatus();
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;

    return Scaffold(
      backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: videos,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshVideos,
              child: PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  var video = snapshot.data![index];
                  String videoId = video['id'];
                  bool isLiked = _likedVideos[videoId] ?? false;
                  int likesCount = _likesCount[videoId] ?? 0;

                  return ReelVideoPlayer(
                    videoUrl: video['video_url'],
                    userName: video['user_name'],
                    videoId: videoId,
                    comments: video['comments'],
                    onLikeToggle: () => toggleLike(videoId),
                    isLiked: isLiked,
                    likesCount: likesCount,
                    onCommentLikeToggle: toggleCommentLike,
                    likedComments: _likedComments,
                    commentLikesCount: _commentLikesCount,
                    isLightTheme: isLightTheme,
                    onShowOptions: () => _showVideoOptionsMenu(videoId),
                    onCommentAdded: (newComment) {
                      setState(() {
                        final videoIndex = snapshot.data!.indexWhere((v) => v['id'] == videoId);
                        if (videoIndex != -1 && !snapshot.data![videoIndex]['comments'].contains(newComment)) {
                          snapshot.data![videoIndex]['comments'].insert(0, newComment);
                        }
                      });
                    },
                    onCommentRemoved: (commentId) {
                      setState(() {
                        final videoIndex = snapshot.data!.indexWhere((v) => v['id'] == videoId);
                        if (videoIndex != -1) {
                          snapshot.data![videoIndex]['comments'].removeWhere((comment) => comment['id'] == commentId);
                        }
                      });
                    },
                    videoOwnerId: video['user_id'],
                    description: video['description'],
                    themeNotifier: widget.themeNotifier,
                  );
                },
              ),
            );
          } else {
            return RefreshIndicator(
              onRefresh: _refreshVideos,
              child: const SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: Center(child: Text('Нет доступных видео')),
              ),
            );
          }
        },
      ),
    );
  }
}

// ReelVideoPlayer class remains unchanged
class ReelVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String userName;
  final String videoId;
  final bool isLiked;
  final VoidCallback onLikeToggle;
  final int likesCount;
  final List comments;
  final Function(String) onCommentLikeToggle;
  final Map<String, bool> likedComments;
  final Map<String, int> commentLikesCount;
  final bool isLightTheme;
  final VoidCallback onShowOptions;
  final Function(Map<String, dynamic>) onCommentAdded;
  final Function(String) onCommentRemoved;
  final String videoOwnerId;
  final String description;
  final ValueNotifier<ThemeData> themeNotifier;

  const ReelVideoPlayer({
    Key? key,
    required this.videoUrl,
    required this.userName,
    required this.isLiked,
    required this.onLikeToggle,
    required this.videoId,
    required this.likesCount,
    required this.comments,
    required this.onCommentLikeToggle,
    required this.likedComments,
    required this.commentLikesCount,
    required this.isLightTheme,
    required this.onShowOptions,
    required this.onCommentAdded,
    required this.onCommentRemoved,
    required this.videoOwnerId,
    required this.description,
    required this.themeNotifier,
  }) : super(key: key);

  @override
  _ReelVideoPlayerState createState() => _ReelVideoPlayerState();
}

class _ReelVideoPlayerState extends State<ReelVideoPlayer> with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isPlaying = false;
  final TextEditingController _commentController = TextEditingController();
  bool _commentsVisible = false;
  bool _isDisposed = false;
  bool _isAddingComment = false;
  bool _isDeletingComment = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        safeSetState(() {});
      }).catchError((error) {
        debugPrint('Error initializing video player: $error');
      });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _animationController.dispose();
    _controller.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  void _triggerLikeAnimation() {
    _animationController.forward().then((_) => _animationController.reverse());
    widget.onLikeToggle();
  }

  Future<void> addComment(String videoId, String comment) async {
    if (_isAddingComment) {
      debugPrint('addComment skipped due to ongoing operation');
      return;
    }

    debugPrint('addComment called with videoId: $videoId, comment: $comment');
    setState(() {
      _isAddingComment = true;
    });

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || comment.isEmpty) {
      setState(() {
        _isAddingComment = false;
      });
      return;
    }

    try {
      final userProfile = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .single()
          .timeout(const Duration(seconds: 10));

      final username = userProfile['username'] as String? ?? 'Unknown';

      final response = await Supabase.instance.client
          .from('video_comments')
          .insert({
        'video_id': videoId,
        'user_id': userId,
        'username': username,
        'content': comment,
      })
          .select('id, username, content, user_id')
          .single()
          .timeout(const Duration(seconds: 10));

      debugPrint('Insert response: $response');

      if (response is Map<String, dynamic>) {
        final commentId = response['id'] as String;
        final newComment = {
          'id': commentId,
          'username': response['username'] as String,
          'content': response['content'] as String,
          'user_id': userId,
          'likesCount': 0,
        };
        safeSetState(() {
          if (!widget.comments.any((c) => c['id'] == commentId)) {
            widget.comments.insert(0, newComment);
            widget.commentLikesCount[commentId] = 0;
          }
        });
        widget.onCommentAdded(newComment);
      } else {
        debugPrint('Unexpected response format: $response');
      }
    } catch (e) {
      debugPrint('Error adding comment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при добавлении комментария: $e')),
      );
    } finally {
      setState(() {
        _isAddingComment = false;
      });
    }
  }

  Future<void> deleteComment(String commentId) async {
    if (_isDeletingComment) {
      debugPrint('deleteComment skipped due to ongoing operation');
      return;
    }

    setState(() {
      _isDeletingComment = true;
    });

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isDeletingComment = false;
      });
      return;
    }

    try {
      final comment = widget.comments.firstWhere(
            (c) => c['id'] == commentId,
        orElse: () => <String, Object>{},
      );

      if (comment.isEmpty) {
        debugPrint('Comment not found with id: $commentId');
        setState(() {
          _isDeletingComment = false;
        });
        return;
      }

      final isOwnComment = comment['user_id'] == userId;
      final isVideoOwner = widget.videoOwnerId == userId;

      if (!isOwnComment && !isVideoOwner) {
        debugPrint('User not authorized to delete this comment');
        setState(() {
          _isDeletingComment = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы не можете удалить этот комментарий')),
        );
        return;
      }

      debugPrint('Deleting likes for comment: $commentId');
      await Supabase.instance.client
          .from('comment_likes')
          .delete()
          .eq('comment_id', commentId)
          .timeout(const Duration(seconds: 10));

      debugPrint('Deleting comment: $commentId');
      await Supabase.instance.client
          .from('video_comments')
          .delete()
          .eq('id', commentId)
          .timeout(const Duration(seconds: 10));

      safeSetState(() {
        widget.comments.removeWhere((c) => c['id'] == commentId);
        widget.commentLikesCount.remove(commentId);
        widget.likedComments.remove(commentId);
      });

      widget.onCommentRemoved(commentId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Комментарий удален')),
      );
    } catch (e) {
      debugPrint('Error deleting comment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при удалении комментария: $e')),
      );
    } finally {
      setState(() {
        _isDeletingComment = false;
      });
    }
  }

  Future<bool?> _showDeleteConfirmationDialog(String commentId) async {
    final isLightTheme = widget.isLightTheme;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: widget.isLightTheme ? Colors.white : Colors.grey[850],
          title: Text(
            'Подтверждение удаления',
            style: TextStyle(color: textColor),
          ),
          content: Text(
            'Вы точно хотите удалить комментарий?',
            style: TextStyle(color: textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Отмена', style: TextStyle(color: textColor)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Удалить', style: const TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isLightTheme ? Colors.black87 : Colors.white;
    final secondaryTextColor = widget.isLightTheme ? Colors.black54 : Colors.white70;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (_controller.value.isInitialized) {
                safeSetState(() {
                  _isPlaying ? _controller.pause() : _controller.play();
                  _isPlaying = !_isPlaying;
                });
              }
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  color: Colors.black,
                  child: _controller.value.isInitialized
                      ? AspectRatio(
                    aspectRatio: 9 / 16,
                    child: ClipRRect(
                      child: VideoPlayer(_controller),
                    ),
                  )
                      : CircularProgressIndicator(color: textColor),
                ),
                Positioned(
                  top: 40,
                  left: 16,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: widget.isLightTheme ? Colors.grey[300] : Colors.grey[800],
                        backgroundImage: NetworkImage(
                          'https://picsum.photos/200?random=${widget.videoOwnerId}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (currentUserId == null) return;
                          if (widget.videoOwnerId == currentUserId) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfileScreen(
                                  userProfile: {
                                    'id': currentUserId,
                                    'username': widget.userName,
                                  },
                                  themeNotifier: widget.themeNotifier,
                                ),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserProfileScreen(
                                  userId: widget.videoOwnerId,
                                  themeNotifier: widget.themeNotifier,
                                ),
                              ),
                            );
                          }
                        },
                        child: Text(
                          widget.userName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                blurRadius: 4,
                                color: Colors.black.withOpacity(0.6),
                                offset: const Offset(1, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 60,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _triggerLikeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Icon(
                            widget.isLiked ? Icons.favorite : Icons.favorite_border,
                            color: widget.isLiked ? Colors.red : Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.likesCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              blurRadius: 2,
                              color: Colors.black54,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      IconButton(
                        icon: const Icon(Icons.comment, color: Colors.white, size: 32),
                        onPressed: () {
                          safeSetState(() {
                            _commentsVisible = !_commentsVisible;
                          });
                        },
                      ),
                      Text(
                        '${widget.comments.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              blurRadius: 2,
                              color: Colors.black54,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.white, size: 32),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Функция поделиться скоро будет доступна')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white, size: 28),
                    onPressed: widget.onShowOptions,
                  ),
                ),
                if (widget.description.isNotEmpty)
                  Positioned(
                    bottom: 60,
                    left: 16,
                    right: 60,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const maxLines = 2;
                          final textSpan = TextSpan(
                            text: widget.description,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1.4,
                              fontWeight: FontWeight.w400,
                            ),
                          );
                          final textPainter = TextPainter(
                            text: textSpan,
                            textDirection: TextDirection.ltr,
                            maxLines: maxLines,
                          )..layout(maxWidth: constraints.maxWidth);

                          final isOverflowing = textPainter.didExceedMaxLines;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.description,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  height: 1.4,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: isOverflowing ? maxLines : null,
                                overflow: isOverflowing ? TextOverflow.ellipsis : null,
                              ),
                              if (isOverflowing)
                                GestureDetector(
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: widget.isLightTheme ? Colors.white : Colors.black,
                                      builder: (context) => Container(
                                        padding: const EdgeInsets.all(16),
                                        child: SingleChildScrollView(
                                          child: Text(
                                            widget.description,
                                            style: TextStyle(
                                              color: textColor,
                                              fontSize: 14,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    'ещё',
                                    style: TextStyle(
                                      color: Colors.blue[300],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_commentsVisible)
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: widget.isLightTheme ? Colors.grey[100] : Colors.grey[900],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Комментарии (${widget.comments.length})',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: textColor, size: 24),
                        onPressed: () {
                          safeSetState(() {
                            _commentsVisible = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.comments.length,
                    itemBuilder: (context, index) {
                      final comment = widget.comments[index];
                      final isLiked = widget.likedComments[comment['id']] ?? false;
                      final likesCount = widget.commentLikesCount[comment['id']] ?? 0;
                      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
                      final isOwnComment = currentUserId != null && comment['user_id'] == currentUserId;
                      final isVideoOwner = currentUserId != null && widget.videoOwnerId == currentUserId;
                      final canDelete = isOwnComment || isVideoOwner;

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
                          return _showDeleteConfirmationDialog(comment['id']);
                        },
                        onDismissed: (direction) {
                          deleteComment(comment['id']);
                        },
                        child: GestureDetector(
                          onLongPress: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: widget.isLightTheme ? Colors.white : Colors.grey[850],
                              builder: (context) {
                                return SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (canDelete)
                                        ListTile(
                                          leading: const Icon(Icons.delete, color: Colors.red),
                                          title: Text(
                                            'Удалить',
                                            style: TextStyle(color: textColor),
                                          ),
                                          onTap: () {
                                            Navigator.pop(context);
                                            _showDeleteConfirmationDialog(comment['id']);
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
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: widget.isLightTheme ? Colors.grey[300] : Colors.grey[800],
                                  backgroundImage: NetworkImage(
                                    'https://picsum.photos/200?random=${comment['user_id']}',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        comment['username'],
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        comment['content'],
                                        style: TextStyle(
                                          color: secondaryTextColor,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        isLiked ? Icons.favorite : Icons.favorite_border,
                                        color: isLiked ? Colors.red : secondaryTextColor,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        widget.onCommentLikeToggle(comment['id']);
                                      },
                                    ),
                                    Text(
                                      '$likesCount',
                                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                                    ),
                                    if (canDelete)
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                        onPressed: () {
                                          _showDeleteConfirmationDialog(comment['id']);
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.isLightTheme ? Colors.white : Colors.grey[850],
                    border: Border(top: BorderSide(color: widget.isLightTheme ? Colors.grey[300]! : Colors.grey[800]!)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: widget.isLightTheme ? Colors.grey[300] : Colors.grey[800],
                        backgroundImage: NetworkImage(
                          'https://picsum.photos/200?random=${Supabase.instance.client.auth.currentUser?.id ?? ''}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: 'Добавить комментарий...',
                            hintStyle: TextStyle(color: secondaryTextColor),
                            filled: true,
                            fillColor: widget.isLightTheme ? Colors.grey[200] : Colors.grey[800],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          style: TextStyle(color: textColor, fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.send,
                          color: _isAddingComment ? Colors.grey : Colors.blue[300],
                          size: 24,
                        ),
                        onPressed: _isAddingComment
                            ? null
                            : () {
                          final commentText = _commentController.text.trim();
                          if (commentText.isNotEmpty) {
                            addComment(widget.videoId, commentText);
                            _commentController.clear();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}