import 'package:flutter/material.dart';
import 'package:newinstagramclone/instagram/profile_scree.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/comments_screen.dart';
import '../screens/user_profile_screen.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String videoId;
  final ValueNotifier<ThemeData> themeNotifier;

  const VideoPlayerScreen({
    Key? key,
    required this.videoUrl,
    required this.videoId,
    required this.themeNotifier,
  }) : super(key: key);

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isPlaying = false;
  bool _showControls = true;
  int likesCount = 0;
  int commentCount = 0;
  bool isLiked = false;
  bool _isLoading = true;
  bool _isReporting = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  String? username;
  String? videoOwnerId;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.8).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _initializeVideo();
    fetchLikes();
    fetchCommentCount();
    fetchVideoOwner();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {
          _isLoading = false;
          _controller.play();
          _isPlaying = true;
        });
      })
      ..addListener(() {
        if (_controller.value.isPlaying != _isPlaying) {
          setState(() {
            _isPlaying = _controller.value.isPlaying;
          });
        }
      });
  }

  Future<void> fetchLikes() async {
    try {
      final response = await Supabase.instance.client
          .from('video_likes')
          .select()
          .eq('video_id', widget.videoId);

      final user = Supabase.instance.client.auth.currentUser;
      setState(() {
        likesCount = response.length;
        isLiked = response.any((like) => like['user_id'] == user?.id);
      });
    } catch (error) {
      print('Ошибка при загрузке лайков: $error');
    }
  }

  Future<void> fetchCommentCount() async {
    try {
      final response = await Supabase.instance.client
          .from('video_comments')
          .select('id')
          .eq('video_id', widget.videoId);

      setState(() {
        commentCount = response.length;
      });
    } catch (e) {
      print('Ошибка при загрузке количества комментариев: $e');
    }
  }

  Future<void> fetchVideoOwner() async {
    try {
      final response = await Supabase.instance.client
          .from('videos')
          .select('user_id, user_name')
          .eq('id', widget.videoId)
          .single();

      setState(() {
        username = response['user_name'] as String? ?? 'Unknown User';
        videoOwnerId = response['user_id'] as String?;
        print('Fetched username: $username, videoOwnerId: $videoOwnerId');
      });
    } catch (e) {
      print('Ошибка при загрузке владельца видео: $e');
      setState(() {
        username = 'Unknown User';
        videoOwnerId = null;
      });
    }
  }

  Future<void> toggleLike() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('video_likes')
          .select()
          .eq('video_id', widget.videoId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null) {
        await Supabase.instance.client
            .from('video_likes')
            .delete()
            .eq('id', response['id']);
        setState(() {
          isLiked = false;
          likesCount--;
        });
      } else {
        await Supabase.instance.client.from('video_likes').insert({
          'video_id': widget.videoId,
          'user_id': user.id,
        });
        setState(() {
          isLiked = true;
          likesCount++;
        });
      }
      _animationController.forward().then((_) => _animationController.reverse());
    } catch (e) {
      print('Ошибка при переключении лайка: $e');
    }
  }

  Future<void> _submitReport(String reason) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isReporting = true;
    });

    try {
      await Supabase.instance.client.from('video_reports').insert({
        'video_id': widget.videoId,
        'reported_by': currentUser.id,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      }).timeout(const Duration(seconds: 10));
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
    } finally {
      setState(() {
        _isReporting = false;
      });
    }
  }

  void _showReportDialog() {
    final TextEditingController reasonController = TextEditingController();
    final theme = widget.themeNotifier.value;
    final textColor = theme.brightness == Brightness.light ? Colors.black87 : Colors.white;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.scaffoldBackgroundColor,
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
              onPressed: _isReporting
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
                _submitReport(reason);
              },
              child: Text(
                _isReporting ? 'Отправка...' : 'Отправить',
                style: TextStyle(color: _isReporting ? Colors.grey : Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showOptionsMenu() {
    final theme = widget.themeNotifier.value;
    final textColor = theme.brightness == Brightness.light ? Colors.black87 : Colors.white;

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
                  _showReportDialog();
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

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
      valueListenable: widget.themeNotifier,
      builder: (context, theme, child) {
        final isLightTheme = theme.brightness == Brightness.light;
        final textColor = isLightTheme ? Colors.black87 : Colors.white;
        final secondaryTextColor = isLightTheme ? Colors.black54 : Colors.white70;

        return Scaffold(
          backgroundColor: isLightTheme ? Colors.white : Colors.black,
          appBar: _showControls
              ? AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.more_vert, color: textColor),
                onPressed: _showOptionsMenu,
              ),
            ],
          )
              : null,
          body: GestureDetector(
            onTap: _toggleControls,
            onDoubleTap: toggleLike,
            child: Stack(
              children: [
                // Video Player
                Center(
                  child: _isLoading
                      ? CircularProgressIndicator(color: textColor)
                      : AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                ),

                // Username
                if (_showControls && username != null && videoOwnerId != null)
                  Positioned(
                    bottom: 100,
                    left: 16,
                    child: GestureDetector(
                      onTap: () {
                        print('Username tapped: $username');
                        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
                        print('Current user ID: $currentUserId, Video owner ID: $videoOwnerId');
                        if (currentUserId == null) {
                          print('No current user, navigation aborted');
                          return;
                        }
                        if (videoOwnerId == currentUserId) {
                          print('Navigating to ProfileScreen for user: $currentUserId');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileScreen(
                                userProfile: {
                                  'id': currentUserId,
                                  'username': username!,
                                },
                                themeNotifier: widget.themeNotifier,
                              ),
                            ),
                          );
                        } else {
                          print('Navigating to UserProfileScreen for user: $videoOwnerId');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                userId: videoOwnerId!,
                                themeNotifier: widget.themeNotifier,
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        username!,
                        style: TextStyle(
                          color: textColor,
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
                  ),

                // Video Controls
                if (_showControls)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(height: kToolbarHeight),
                          Center(
                            child: IconButton(
                              icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                color: textColor,
                                size: 50,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_controller.value.isPlaying) {
                                    _controller.pause();
                                  } else {
                                    _controller.play();
                                  }
                                  _isPlaying = !_isPlaying;
                                });
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: toggleLike,
                                      child: ScaleTransition(
                                        scale: _scaleAnimation,
                                        child: Icon(
                                          isLiked ? Icons.favorite : Icons.favorite_border,
                                          color: isLiked ? Colors.red : textColor,
                                          size: 30,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    IconButton(
                                      icon: Icon(Icons.comment, color: textColor, size: 30),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => CommentsScreen(
                                              videoId: widget.videoId,
                                              onCommentAdded: (count) {
                                                setState(() {
                                                  commentCount = count;
                                                  fetchCommentCount();
                                                });
                                              },
                                              themeNotifier: widget.themeNotifier,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 16),
                                    IconButton(
                                      icon: Icon(Icons.share, color: textColor, size: 30),
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                              content: Text('Функция поделиться скоро будет добавлена!')),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$likesCount',
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                if (commentCount > 0)
                                  Text(
                                    '$commentCount',
                                    style: TextStyle(
                                      color: secondaryTextColor,
                                      fontSize: 18,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}