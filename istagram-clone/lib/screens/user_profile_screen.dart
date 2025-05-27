import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../instagram/fillowers_following_screen.dart';
import '../screens/my_video_player_screen.dart';
import '../screens/photo_detail_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final ValueNotifier<ThemeData> themeNotifier;

  UserProfileScreen({Key? key, required this.userId, required this.themeNotifier}) : super(key: key);

  @override
  _UserProfileScreenState createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? userProfile;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> uploadedPhotos = [];
  List<Map<String, dynamic>> uploadedVideos = [];
  int totalPosts = 0;
  bool isSubscribed = false;
  String? userNote;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _refreshAllData();
  }

  Future<void> _refreshAllData() async {
    await Future.wait([
      fetchUserProfile(),
      fetchUserNote(),
      checkIfSubscribed(),
    ]);
  }

  Future<void> fetchUserProfile() async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
      userProfile = null; // Reset profile to show loading state
      uploadedPhotos = [];
      uploadedVideos = [];
      totalPosts = 0;
    });

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, username, bio, avatar_url, followers_count, subscriptions_count')
          .eq('id', widget.userId)
          .single()
          .timeout(const Duration(seconds: 30));

      if (response != null) {
        debugPrint('Fetched user profile: id=${response['id']}, username=${response['username']}, avatar_url=${response['avatar_url']}');
        setState(() {
          userProfile = response;
        });

        await Future.wait([fetchUserPhotos(), fetchUserVideos()]);
      }
    } catch (error) {
      debugPrint('Ошибка при загрузке профиля: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки профиля: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> fetchUserNote() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final response = await Supabase.instance.client
          .from('user_notes')
          .select('note_text')
          .eq('user_id', currentUserId)
          .eq('target_user_id', widget.userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          userNote = response?['note_text'];
        });
      }
    } catch (error) {
      debugPrint('Ошибка при загрузке заметки: $error');
    }
  }

  Future<void> checkIfSubscribed() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('subscriptions')
          .select()
          .eq('follower_id', currentUserId)
          .eq('following_id', widget.userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          isSubscribed = response != null;
        });
      }
    } catch (error) {
      debugPrint('Ошибка при проверке подписки: $error');
    }
  }

  Future<void> fetchUserPhotos() async {
    try {
      final response = await Supabase.instance.client
          .from('user_photos')
          .select('id, user_id, photo_url, created_at, description')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 30));

      debugPrint('User photos fetched: ${response.length} photos for user ${widget.userId}');
      final photos = List<Map<String, dynamic>>.from(response.map((photo) => {
        'url': photo['photo_url'] ?? '',
        'id': photo['id'] ?? '',
        'description': photo['description'] ?? '',
        'created_at': photo['created_at'] ?? '',
      }).where((photo) => photo['url'].isNotEmpty));

      debugPrint('Valid photos: ${photos.length}, URLs: ${photos.map((p) => p['url']).toList()}');

      if (mounted) {
        setState(() {
          uploadedPhotos = photos;
          totalPosts = uploadedPhotos.length + uploadedVideos.length;
        });
      }
    } catch (error) {
      debugPrint('Ошибка при загрузке фотографий: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки фотографий: $error')),
        );
      }
    }
  }

  Future<void> fetchUserVideos() async {
    try {
      final response = await Supabase.instance.client
          .from('user_videos')
          .select('id, user_id, video_url, created_at, description')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 30));

      debugPrint('User videos fetched: ${response.length}');
      for (var video in response) {
        debugPrint('Video ID: ${video['id']}, URL: ${video['video_url']}, Description: ${video['description']}');
      }

      if (mounted) {
        setState(() {
          uploadedVideos = List<Map<String, dynamic>>.from(response.map((video) => {
            'url': video['video_url'] ?? '',
            'id': video['id'],
            'description': video['description'] ?? 'Нет описания',
            'created_at': video['created_at'],
          }));
          totalPosts = uploadedPhotos.length + uploadedVideos.length;
        });
      }
    } catch (error) {
      debugPrint('Ошибка при загрузке видео: $error');
    }
  }

  Future<void> subscribe(String userId) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      debugPrint('Пользователь не аутентифицирован');
      return;
    }

    try {
      final existingSubscriptionResponse = await Supabase.instance.client
          .from('subscriptions')
          .select()
          .eq('follower_id', currentUser.id)
          .eq('following_id', userId)
          .maybeSingle();

      if (existingSubscriptionResponse != null) {
        debugPrint('Вы уже подписаны на этого пользователя.');
        return;
      }

      await Supabase.instance.client.from('subscriptions').insert({
        'follower_id': currentUser.id,
        'following_id': userId,
      });

      if (mounted) {
        setState(() {
          isSubscribed = true;
          userProfile!['followers_count'] = (userProfile!['followers_count'] ?? 0) + 1;
        });
      }
      debugPrint('Подписка успешна!');
    } catch (error) {
      debugPrint('Ошибка при подписке: $error');
    }
  }

  Future<void> unsubscribe(String userId) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      debugPrint('Пользователь не аутентифицирован');
      return;
    }

    try {
      await Supabase.instance.client
          .from('subscriptions')
          .delete()
          .eq('follower_id', currentUser.id)
          .eq('following_id', userId);

      if (mounted) {
        setState(() {
          isSubscribed = false;
          userProfile!['followers_count'] = (userProfile!['followers_count'] ?? 0) > 0
              ? (userProfile!['followers_count'] - 1)
              : 0;
        });
      }
      debugPrint('Отписка успешна!');
    } catch (error) {
      debugPrint('Ошибка при отписке: $error');
    }
  }

  Future<Uint8List?> generateThumbnail(String videoUrl) async {
    try {
      final thumbnail = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 128,
        quality: 75,
      );
      debugPrint('Thumbnail generated for $videoUrl');
      return thumbnail;
    } catch (e) {
      debugPrint('Ошибка при генерации миниатюры для $videoUrl: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;

    return DefaultTabController(
      initialIndex: 0,
      length: 2,
      child: Scaffold(
        backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
          title: Text(
            userProfile?['username'] ?? 'Профиль',
            style: TextStyle(
              color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: widget.themeNotifier.value.iconTheme.color),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _refreshAllData,
          color: widget.themeNotifier.value.primaryColor,
          child: userProfile == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (userNote != null) {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: widget.themeNotifier.value.cardColor,
                                title: Text(
                                  'Заметка',
                                  style: TextStyle(
                                    color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                                  ),
                                ),
                                content: Text(
                                  userNote!,
                                  style: TextStyle(
                                    color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: Text(
                                      'Закрыть',
                                      style: TextStyle(
                                        color: widget.themeNotifier.value.primaryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                gradient: userNote != null
                                    ? const LinearGradient(
                                  colors: [Colors.purple, Colors.orange, Colors.yellow],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                                    : null,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isLightTheme ? Colors.grey.shade300 : Colors.grey.shade700,
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                backgroundImage: userProfile?['avatar_url'] != null
                                    ? NetworkImage(
                                  '${userProfile!['avatar_url']}?timestamp=${DateTime.now().millisecondsSinceEpoch}',
                                )
                                    : null,
                                radius: 40,
                                child: userProfile?['avatar_url'] == null
                                    ? const Icon(Icons.person, size: 40)
                                    : null,
                              ),
                            ),
                            if (userNote != null)
                              Positioned(
                                top: -30,
                                child: Container(
                                  constraints: const BoxConstraints(maxWidth: 120),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    userNote!.length > 10 ? '${userNote!.substring(0, 10)}...' : userNote!,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            if (userNote != null)
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
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userProfile?['username'] ?? 'Имя не указано',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userProfile?['bio'] ?? 'Биография не указана',
                              style: TextStyle(
                                fontSize: 14,
                                color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            totalPosts.toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Посты',
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FollowersFollowingScreen(
                                userId: widget.userId,
                                isFollowers: true,
                                themeNotifier: widget.themeNotifier,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            _isUpdating
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : Text(
                              (userProfile?['followers_count'] ?? 0).toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Подписчики',
                              style: TextStyle(
                                fontSize: 14,
                                color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FollowersFollowingScreen(
                                userId: widget.userId,
                                isFollowers: false,
                                themeNotifier: widget.themeNotifier,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            _isUpdating
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : Text(
                              (userProfile?['subscriptions_count'] ?? 0).toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Подписки',
                              style: TextStyle(
                                fontSize: 14,
                                color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Внутри Column в методе build, где рендерится кнопка подписки
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Supabase.instance.client.auth.currentUser?.id == widget.userId
                      ? const SizedBox.shrink() // Скрываем кнопку для текущего пользователя
                      : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (isSubscribed) {
                          await unsubscribe(userProfile?['id']);
                        } else {
                          await subscribe(userProfile?['id']);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSubscribed
                            ? widget.themeNotifier.value.colorScheme.secondary
                            : widget.themeNotifier.value.primaryColor,
                        foregroundColor: widget.themeNotifier.value.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        isSubscribed ? 'Отписаться' : 'Подписаться',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: widget.themeNotifier.value.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TabBar(
                  labelColor: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                  unselectedLabelColor:
                  widget.themeNotifier.value.textTheme.bodyLarge?.color?.withOpacity(0.6),
                  indicatorColor: widget.themeNotifier.value.primaryColor,
                  tabs: const [
                    Tab(icon: Icon(Icons.grid_on)),
                    Tab(icon: Icon(Icons.video_library)),
                  ],
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: TabBarView(
                    children: [
                      uploadedPhotos.isEmpty
                          ? Center(
                        child: Text(
                          'Нет фотографий',
                          style: TextStyle(
                            color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                            fontSize: 16,
                          ),
                        ),
                      )
                          : // Inside the TabBarView for photos, replace the GridView.builder with:
                      GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 1,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                        itemCount: uploadedPhotos.length,
                        itemBuilder: (context, index) {
                          final photoUrl = uploadedPhotos[index]['url']; // Changed from 'photoUrl' to 'url'
                          return GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => PhotoDetailScreen(
                                    imageUrl: photoUrl,
                                    timePosted: uploadedPhotos[index]['created_at'] ?? DateTime.now().toString(),
                                    initialLikes: 0, // No 'likes' key available
                                    username: userProfile?['username'] ?? 'Имя не указано',
                                    photoId: uploadedPhotos[index]['id'] ?? '', // Changed from 'photoId' to 'id'
                                    description: uploadedPhotos[index]['description'] ?? 'Нет описания',
                                    themeNotifier: widget.themeNotifier,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              color: Colors.grey[200], // Match ProfileScreen
                              child: Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
                                          : null,
                                      color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  debugPrint('Photo load error: $error for URL: $photoUrl');
                                  return Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                                      size: 50,
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                      uploadedVideos.isEmpty
                          ? Center(
                        child: Text(
                          'Нет видео',
                          style: TextStyle(
                            color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                            fontSize: 16,
                          ),
                        ),
                      )
                          : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 1, // Это делает ячейки квадратными
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                        itemCount: uploadedVideos.length,
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () {
                              final videoUrl = uploadedVideos[index]['url'];
                              final videoId = uploadedVideos[index]['id'];
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => MyVideoPlayerScreen(
                                    videoUrl: videoUrl ?? '',
                                    videoId: videoId ?? '',
                                    username: userProfile?['username'] ?? 'Имя не указано',
                                    description: uploadedVideos[index]['description'] ?? 'Нет описания',
                                  ),
                                ),
                              );
                            },
                            child: FutureBuilder<Uint8List?>(
                              future: generateThumbnail(uploadedVideos[index]['url'] ?? ''),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return Container(
                                    color: isLightTheme ? Colors.grey[300] : Colors.grey[800],
                                    child: const Center(child: CircularProgressIndicator()),
                                  );
                                } else if (snapshot.hasError || !snapshot.hasData) {
                                  debugPrint('Thumbnail error for ${uploadedVideos[index]['url']}');
                                  return Container(
                                    color: isLightTheme ? Colors.grey[300] : Colors.grey[800],
                                    child: const Icon(Icons.broken_image, color: Colors.white),
                                  );
                                } else {
                                  return Stack(
                                    fit: StackFit.expand, // Добавлено для заполнения всей ячейки
                                    children: [
                                      Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.cover, // Заполняет всю ячейку, сохраняя пропорции
                                      ),
                                      const Center(
                                        child: Icon(
                                          Icons.play_circle_outline,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                    ],
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}