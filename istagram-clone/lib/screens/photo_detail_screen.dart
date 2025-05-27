import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../instagram/profile_scree.dart';
import 'comments_screen.dart';
import 'likes_list_screen.dart';
import 'user_profile_screen.dart'; // Add this import

class PhotoDetailScreen extends StatefulWidget {
  final String imageUrl;
  final String timePosted;
  final int initialLikes;
  final String username;
  final String photoId;
  final String description;
  final ValueNotifier<ThemeData> themeNotifier;
  final Function(String, int, bool)? onLikeChanged;
  final Function(String, int)? onCommentChanged;

  const PhotoDetailScreen({
    Key? key,
    required this.imageUrl,
    required this.timePosted,
    required this.initialLikes,
    required this.username,
    required this.photoId,
    required this.description,
    required this.themeNotifier,
    this.onLikeChanged,
    this.onCommentChanged,
  }) : super(key: key);

  @override
  _PhotoDetailScreenState createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> with SingleTickerProviderStateMixin {
  late int likes;
  late int commentCount;
  bool isLiked = false;
  List<String> likedUsers = [];
  List<String> usersWhoLiked = [];
  bool _isReporting = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  StreamSubscription<List<Map<String, dynamic>>>? _likesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _commentsSubscription;
  String? photoOwnerId; // Add for owner ID

  @override
  void initState() {
    super.initState();
    likes = widget.initialLikes;
    commentCount = 0;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    fetchLikesCount();
    fetchCommentCount();
    checkIfLiked();
    fetchPhotoOwner(); // Add to fetch owner ID
    _subscribeToLikes();
    _subscribeToComments();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _likesSubscription?.cancel();
    _commentsSubscription?.cancel();
    super.dispose();
  }

  Future<void> fetchPhotoOwner() async {
    try {
      final response = await Supabase.instance.client
          .from('photos')
          .select('user_id')
          .eq('id', widget.photoId)
          .single();

      setState(() {
        photoOwnerId = response['user_id'] as String?;
        print('Fetched photoOwnerId: $photoOwnerId');
      });
    } catch (e) {
      print('Ошибка при загрузке владельца фото: $e');
      setState(() {
        photoOwnerId = null;
      });
    }
  }

  void _subscribeToLikes() {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      print('No authenticated user for likes subscription');
      return;
    }

    print('Subscribing to likes stream for photoId: ${widget.photoId}');
    _likesSubscription?.cancel();
    _likesSubscription = Supabase.instance.client
        .from('likes')
        .stream(primaryKey: ['id'])
        .eq('photo_id', widget.photoId)
        .listen((List<Map<String, dynamic>> likesData) async {
      print('Received likes stream update for photoId: ${widget.photoId}, count: ${likesData.length}');

      final likesCountResponse = await Supabase.instance.client
          .from('likes')
          .select('user_id')
          .eq('photo_id', widget.photoId);

      final isLikedResponse = await Supabase.instance.client
          .from('likes')
          .select()
          .eq('photo_id', widget.photoId)
          .eq('user_id', currentUser.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          likes = likesCountResponse.length;
          isLiked = isLikedResponse != null;
          likedUsers = likesCountResponse.map<String>((e) => e['user_id'] as String).toList();
        });
        fetchUsersWhoLiked();
        widget.onLikeChanged?.call(widget.photoId, likes, isLiked);
      }
    }, onError: (error) {
      print('Likes stream error: $error');
    });
  }

  void _subscribeToComments() {
    print('Subscribing to comments stream for photoId: ${widget.photoId}');
    _commentsSubscription = Supabase.instance.client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('photo_id', widget.photoId)
        .listen((List<Map<String, dynamic>> comments) async {
      print('Received comments stream update for photoId: ${widget.photoId}, count: ${comments.length}');
      if (mounted) {
        setState(() {
          commentCount = comments.length;
        });
        widget.onCommentChanged?.call(widget.photoId, commentCount);
        print('Comments updated: photoId=${widget.photoId}, commentCount=$commentCount');
      }
    }, onError: (error) {
      print('Comments stream error: $error');
    });
  }

  Future<void> fetchLikesCount() async {
    try {
      final response = await Supabase.instance.client
          .from('likes')
          .select('user_id')
          .eq('photo_id', widget.photoId);

      if (mounted) {
        setState(() {
          likes = response.length;
          likedUsers = response.map<String>((e) => e['user_id'] as String).toList();
        });
        fetchUsersWhoLiked();
        widget.onLikeChanged?.call(widget.photoId, likes, isLiked);
        print('Fetched likes: photoId=${widget.photoId}, likes=$likes');
      }
    } catch (e) {
      print('Ошибка при загрузке лайков: $e');
    }
  }

  Future<void> fetchCommentCount() async {
    try {
      final response = await Supabase.instance.client
          .from('comments')
          .select('id')
          .eq('photo_id', widget.photoId);

      if (mounted) {
        setState(() {
          commentCount = response.length;
        });
        widget.onCommentChanged?.call(widget.photoId, commentCount);
        print('Fetched comments: photoId=${widget.photoId}, commentCount=$commentCount');
      }
    } catch (e) {
      print('Ошибка при загрузке количества комментариев: $e');
    }
  }

  Future<void> fetchUsersWhoLiked() async {
    try {
      List<String> usernames = [];
      for (var userId in likedUsers) {
        final response = await Supabase.instance.client
            .from('profiles')
            .select('username')
            .eq('id', userId)
            .single();
        if (response['username'] != null) {
          usernames.add(response['username']);
        }
      }
      if (mounted) {
        setState(() {
          usersWhoLiked = usernames;
        });
      }
    } catch (e) {
      print('Ошибка загрузки пользователей, которые лайкнули: $e');
    }
  }

  Future<void> checkIfLiked() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null || widget.photoId.isEmpty) {
      print('Пользователь не найден или photoId пуст.');
      return;
    }
    try {
      final response = await Supabase.instance.client
          .from('likes')
          .select()
          .eq('photo_id', widget.photoId)
          .eq('user_id', currentUser.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          isLiked = response != null;
        });
        widget.onLikeChanged?.call(widget.photoId, likes, isLiked);
        print('Checked like status: photoId=${widget.photoId}, isLiked=$isLiked');
      }
    } catch (e) {
      print('Ошибка проверки состояния лайка: $e');
    }
  }

  Future<void> toggleLike() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      print('toggleLike: Пользователь не аутентифицирован');
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('likes')
          .select()
          .eq('photo_id', widget.photoId)
          .eq('user_id', currentUser.id)
          .maybeSingle();

      if (response != null) {
        await Supabase.instance.client
            .from('likes')
            .delete()
            .eq('id', response['id']);
        if (mounted) {
          setState(() {
            likes--;
            isLiked = false;
            likedUsers.remove(currentUser.id);
          });
          widget.onLikeChanged?.call(widget.photoId, likes, isLiked);
          print('toggleLike: Unliked, photoId=${widget.photoId}, likes=$likes');
        }
      } else {
        await Supabase.instance.client.from('likes').insert({
          'user_id': currentUser.id,
          'photo_id': widget.photoId,
        });
        if (mounted) {
          setState(() {
            likes++;
            isLiked = true;
            likedUsers.add(currentUser.id);
          });
          widget.onLikeChanged?.call(widget.photoId, likes, isLiked);
          print('toggleLike: Liked, photoId=${widget.photoId}, likes=$likes');
        }
      }
      _animationController.forward().then((_) => _animationController.reverse());
      fetchUsersWhoLiked();
    } catch (e) {
      print('Ошибка при переключении лайка: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при лайке: $e')),
      );
    }
  }

  Future<void> _submitReport(String reason) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isReporting = true;
    });

    try {
      await Supabase.instance.client.from('photo_reports').insert({
        'photo_id': widget.photoId,
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
            'Пожаловаться на фото',
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

  void _navigateToProfile() {
    if (photoOwnerId == null) {
      print('photoOwnerId is null, navigation aborted');
      return;
    }
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    print('Username tapped: ${widget.username}, photoOwnerId: $photoOwnerId, currentUserId: $currentUserId');
    if (currentUserId == null) {
      print('No current user, navigation aborted');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы просмотреть профиль')),
      );
      return;
    }
    if (photoOwnerId == currentUserId) {
      print('Navigating to ProfileScreen for user: $currentUserId');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfileScreen(
            userProfile: {
              'id': currentUserId,
              'username': widget.username,
            },
            themeNotifier: widget.themeNotifier,
          ),
        ),
      );
    } else {
      print('Navigating to UserProfileScreen for user: $photoOwnerId');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            userId: photoOwnerId!,
            themeNotifier: widget.themeNotifier,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeNotifier.value;
    final isLightTheme = theme.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;
    final secondaryTextColor = isLightTheme ? Colors.black54 : Colors.white70;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: NetworkImage(widget.imageUrl),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _navigateToProfile,
              child: Text(
                widget.username,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: textColor),
            onPressed: _showOptionsMenu,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onDoubleTap: toggleLike,
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: toggleLike,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : textColor,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: Icon(Icons.chat_bubble_outline, color: textColor, size: 28),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CommentsScreen(
                            photoId: widget.photoId,
                            onCommentAdded: (count) {
                              setState(() => commentCount = count);
                              widget.onCommentChanged?.call(widget.photoId, count);
                            },
                            themeNotifier: widget.themeNotifier,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: Icon(Icons.share, color: textColor, size: 28),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Функция поделиться скоро будет добавлена!')),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
              child: GestureDetector(
                onTap: () {
                  fetchUsersWhoLiked();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LikesListScreen(likedUsers: usersWhoLiked),
                    ),
                  );
                },
                child: Text(
                  likes == 1 ? '$likes отметка "Нравится"' : '$likes отметок "Нравится"',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (widget.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(color: textColor, fontSize: 14),
                    children: [
                      TextSpan(
                        text: widget.username,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        recognizer: TapGestureRecognizer()..onTap = _navigateToProfile,
                      ),
                      TextSpan(text: ' ${widget.description}'),
                    ],
                  ),
                ),
              ),
            if (commentCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CommentsScreen(
                          photoId: widget.photoId,
                          onCommentAdded: (count) {
                            setState(() => commentCount = count);
                            widget.onCommentChanged?.call(widget.photoId, count);
                          },
                          themeNotifier: widget.themeNotifier,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    commentCount == 1
                        ? 'Посмотреть $commentCount комментарий'
                        : 'Посмотреть все $commentCount комментариев',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Text(
                widget.timePosted.toUpperCase(),
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}