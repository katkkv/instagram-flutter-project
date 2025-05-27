import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../instagram/video_comments.dart'; // Ensure this points to your VideoComments widget

class MyVideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String videoId;
  final String description; // Added description parameter
  final String username; // Added username for display

  const MyVideoPlayerScreen({
    required this.videoUrl,
    required this.videoId,
    required this.description,
    required this.username,
    Key? key,
  }) : super(key: key);

  @override
  _MyVideoPlayerScreenState createState() => _MyVideoPlayerScreenState();
}

class _MyVideoPlayerScreenState extends State<MyVideoPlayerScreen> with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  int likesCount = 0;
  bool isLiked = false;
  List<Map<String, dynamic>> comments = [];
  int commentsCount = 0;
  final TextEditingController _commentController = TextEditingController();
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isReporting = false;

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
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() {});
      }).catchError((error) {
        print('Error initializing video: $error');
      });
    fetchLikes();
    fetchComments();
  }

  Future<void> fetchComments() async {
    try {
      final response = await Supabase.instance.client
          .from('video_comments')
          .select()
          .eq('video_id', widget.videoId);

      setState(() {
        comments = List<Map<String, dynamic>>.from(response);
        commentsCount = comments.length;
      });
    } catch (error) {
      print('Ошибка при загрузке комментариев: $error');
    }
  }

  Future<void> fetchLikes() async {
    try {
      final response = await Supabase.instance.client
          .from('video_likes')
          .select()
          .eq('video_id', widget.videoId);

      setState(() {
        likesCount = response.length;
        final user = Supabase.instance.client.auth.currentUser;
        isLiked = response.any((like) => like['user_id'] == user?.id);
      });
    } catch (error) {
      print('Ошибка при загрузке лайков: $error');
    }
  }

  Future<void> toggleLike() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      if (isLiked) {
        await Supabase.instance.client
            .from('video_likes')
            .delete()
            .eq('video_id', widget.videoId)
            .eq('user_id', user.id);
      } else {
        await Supabase.instance.client
            .from('video_likes')
            .insert({'video_id': widget.videoId, 'user_id': user.id});
      }

      setState(() {
        isLiked = !isLiked;
        likesCount += isLiked ? 1 : -1;
      });
      _animationController.forward().then((_) => _animationController.reverse());
    } catch (e) {
      print('Ошибка при переключении лайка: $e');
    }
  }

  Future<void> addComment(String comment) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || comment.isEmpty) return;

    try {
      final userProfile = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .single();

      await Supabase.instance.client.from('video_comments').insert({
        'video_id': widget.videoId,
        'user_id': userId,
        'username': userProfile['username'],
        'content': comment,
      });
      await fetchComments();
    } catch (e) {
      print('Ошибка при добавлении комментария: $e');
    }
  }

  Future<void> _submitVideoReport(String reason) async {
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
      });

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
        _isReporting = false;
      });
    }
  }

  void _showVideoReportDialog() {
    final TextEditingController reasonController = TextEditingController();
    final isLightTheme = Theme.of(context).brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                _submitVideoReport(reason);
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

  void _showVideoOptionsMenu() {
    final isLightTheme = Theme.of(context).brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                  _showVideoReportDialog();
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

  void _openComments() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoComments(
          videoId: widget.videoId,
          comments: comments,
          commentsCount: commentsCount,
          onAddComment: (comment) async {
            await addComment(comment);
            await fetchComments();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = Theme.of(context).brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;
    final secondaryTextColor = isLightTheme ? Colors.black54 : Colors.white70;

    return Scaffold(
      backgroundColor: isLightTheme ? Colors.white : Colors.black,
      appBar: AppBar(
        backgroundColor: isLightTheme ? Colors.white : Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.username,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.5,
            shadows: [
              Shadow(
                blurRadius: 2,
                color: isLightTheme ? Colors.grey.withOpacity(0.2) : Colors.black.withOpacity(0.3),
                offset: const Offset(1, 1),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: textColor),
            onPressed: _showVideoOptionsMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Видео с фиксированным прямоугольным соотношением сторон
                  Container(
                    color: Colors.black, // Фон для пустых областей
                    child: _controller.value.isInitialized
                        ? AspectRatio(
                      aspectRatio: 9 / 16, // Прямоугольное соотношение для вертикальных видео
                      child: ClipRRect(
                        child: VideoPlayer(_controller),
                      ),
                    )
                        : Center(
                      child: CircularProgressIndicator(color: textColor),
                    ),
                  ),
                  // Кнопки взаимодействия (Like, Comment, Share)
                  Positioned(
                    right: 16,
                    bottom: 60,
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: toggleLike,
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              color: isLiked ? Colors.red : Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$likesCount',
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
                          onPressed: _openComments,
                        ),
                        Text(
                          '$commentsCount',
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
                  // Описание
                  if (widget.description.isNotEmpty)
                    Positioned(
                      bottom: 60,
                      left: 16,
                      right: 60, // Оставляем место для кнопок
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
                                        backgroundColor: isLightTheme ? Colors.white : Colors.black,
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
        ],
      ),
    );
  }

}