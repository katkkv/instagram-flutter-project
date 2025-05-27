import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class AdminUserProfileScreen extends StatefulWidget {
  final String userId;
  final ValueNotifier<ThemeData> themeNotifier;

  const AdminUserProfileScreen({
    Key? key,
    required this.userId,
    required this.themeNotifier,
  }) : super(key: key);

  @override
  _AdminUserProfileScreenState createState() => _AdminUserProfileScreenState();
}

class _AdminUserProfileScreenState extends State<AdminUserProfileScreen> {
  Map<String, dynamic>? userProfile;
  List<Map<String, dynamic>> uploadedPhotos = [];
  List<Map<String, dynamic>> uploadedVideos = [];
  List<Map<String, dynamic>> userComments = [];
  bool _isLoading = true;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', widget.userId)
          .single();

      final photos = await Supabase.instance.client
          .from('user_photos')
          .select()
          .eq('user_id', widget.userId);

      final videos = await Supabase.instance.client
          .from('user_videos')
          .select()
          .eq('user_id', widget.userId);

      final comments = await Supabase.instance.client
          .from('video_comments')
          .select()
          .eq('user_id', widget.userId);

      setState(() {
        userProfile = profile;
        uploadedPhotos = List<Map<String, dynamic>>.from(photos);
        uploadedVideos = List<Map<String, dynamic>>.from(videos);
        userComments = List<Map<String, dynamic>>.from(comments);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(userProfile?['username'] ?? 'Профиль'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Фото (${uploadedPhotos.length})'),
              Tab(text: 'Видео (${uploadedVideos.length})'),
              Tab(text: 'Комментарии (${userComments.length})'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadUserData,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
          children: [
            _buildPhotosGrid(),
            _buildVideosGrid(),
            _buildCommentsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosGrid() {
    if (uploadedPhotos.isEmpty) {
      return Center(
        child: Text(
          'Нет фотографий',
          style: TextStyle(
            color: widget.themeNotifier.value.textTheme.bodyMedium?.color,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: uploadedPhotos.length,
      itemBuilder: (context, index) {
        final photo = uploadedPhotos[index];
        return GestureDetector(
          onLongPress: () => _confirmDeletePhoto(photo['id']),
          child: CachedNetworkImage(
            imageUrl: photo['photo_url'],
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.grey[200]),
          ),
        );
      },
    );
  }

  Widget _buildVideosGrid() {
    if (uploadedVideos.isEmpty) {
      return Center(
        child: Text(
          'Нет видео',
          style: TextStyle(
            color: widget.themeNotifier.value.textTheme.bodyMedium?.color,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: uploadedVideos.length,
      itemBuilder: (context, index) {
        final video = uploadedVideos[index];
        return GestureDetector(
          onLongPress: () => _confirmDeleteVideo(video['id']),
          child: FutureBuilder<Uint8List?>(
            future: generateThumbnail(video['video_url']),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(color: Colors.grey[200]);
              } else if (snapshot.hasError || !snapshot.hasData) {
                return const Icon(Icons.error);
              } else {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(snapshot.data!, fit: BoxFit.cover),
                    const Center(
                      child: Icon(Icons.play_arrow, color: Colors.white),
                    ),
                  ],
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildCommentsList() {
    if (userComments.isEmpty) {
      return Center(
        child: Text(
          'Нет комментариев',
          style: TextStyle(
            color: widget.themeNotifier.value.textTheme.bodyMedium?.color,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: userComments.length,
      itemBuilder: (context, index) {
        final comment = userComments[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            title: Text(comment['content']),
            subtitle: Text(
              'Видео ID: ${comment['video_id']}',
              style: TextStyle(
                color: widget.themeNotifier.value.textTheme.bodyMedium?.color,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDeleteComment(comment['id']),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeletePhoto(String photoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client
            .from('user_photos')
            .delete()
            .eq('id', photoId);

        setState(() {
          uploadedPhotos.removeWhere((photo) => photo['id'] == photoId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото удалено')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteVideo(String videoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить видео?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client
            .from('user_videos')
            .delete()
            .eq('id', videoId);

        setState(() {
          uploadedVideos.removeWhere((video) => video['id'] == videoId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Видео удалено')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteComment(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить комментарий?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client
            .from('video_comments')
            .delete()
            .eq('id', commentId);

        setState(() {
          userComments.removeWhere((comment) => comment['id'] == commentId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Комментарий удалён')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<Uint8List?> generateThumbnail(String videoUrl) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200,
        quality: 75,
      );
    } catch (e) {
      print("Error generating thumbnail: $e");
      return null;
    }
  }
}