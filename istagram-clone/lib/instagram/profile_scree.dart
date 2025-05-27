import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_themes.dart';
import '../instagram/login_screen.dart';
import 'package:video_player/video_player.dart';
import '../screens/my_video_player_screen.dart';
import '../screens/photo_detail_screen.dart';
import '../screens/statistics_screen.dart';
import '../screens/user_profile_screen.dart';
import 'fillowers_following_screen.dart';
import 'note_editor_dialog.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? userProfile;
  final ValueNotifier<ThemeData> themeNotifier;

  ProfileScreen({Key? key, required this.userProfile, required this.themeNotifier}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Map<String, dynamic>? userProfile;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> uploadedPhotos = [];
  List<Map<String, dynamic>> uploadedVideos = [];
  int totalPosts = 0;
  final Map<String, String> _userNotes = {};
  bool _isNoteSaving = false;
  bool _isLoading = false;
  StreamSubscription? _subscriptionStream;
  bool _isUpdating = false;
  final ScrollController _photoScrollController = ScrollController();
  final ScrollController _videoScrollController = ScrollController();

  bool get isCurrentUserProfile {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return currentUserId != null && currentUserId == userProfile?['id'];
  }

  @override
  void initState() {
    super.initState();
    userProfile = widget.userProfile;
    fetchUserData();
    _loadUserNotes();
    _subscribeToSubscriptionsChanges();
  }

  @override
  void dispose() {
    _subscriptionStream?.cancel();
    _photoScrollController.dispose();
    _videoScrollController.dispose();
    super.dispose();
  }



  void _subscribeToSubscriptionsChanges() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _subscriptionStream = Supabase.instance.client
        .from('subscriptions')
        .stream(primaryKey: ['id'])
        .listen((List<Map<String, dynamic>> data) {
      bool isRelevant = data.any((record) =>
      record['follower_id'] == userId || record['following_id'] == userId);

      if (isRelevant) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            fetchUserData();
          }
        });
      }
    }, onError: (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка потока: $error')),
        );
      }
    });
  }

  Future<void> _showChangeAvatarDialog() async {
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final textColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black87 : Colors.white;
        return Container(
          decoration: BoxDecoration(
            color: widget.themeNotifier.value.cardColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: widget.themeNotifier.value.dividerColor,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Изменить фото профиля',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.photo_library, color: textColor),
                  title: Text('Галерея', style: TextStyle(color: textColor)),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickAndUploadImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.camera_alt, color: textColor),
                  title: Text('Камера', style: TextStyle(color: textColor)),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickAndUploadImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  title: Center(
                    child: Text(
                      'Отмена',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                    ),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          final tempFile = File('${Directory.systemTemp.path}/temp_avatar.jpg');
          await tempFile.writeAsBytes(bytes);
          await _uploadAvatar(XFile(tempFile.path));
        } else {
          await _uploadAvatar(pickedFile);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e')),
        );
      }
    }
  }

  Future<void> _uploadAvatar(XFile imageFile) async {
    if (!mounted) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final filePath = imageFile.path;
      if (filePath.isEmpty) throw Exception('Invalid file path');

      final file = File(filePath);
      if (!await file.exists()) throw Exception('File does not exist');

      final fileExt = filePath.split('.').last;
      final fileName = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      debugPrint('Uploading avatar: $fileName');
      final uploadResponse = await Supabase.instance.client.storage
          .from('avatars')
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      if (uploadResponse.isEmpty) throw Exception('Upload failed');

      final publicUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(fileName);
      debugPrint('Avatar uploaded: $publicUrl');

      final updateResponse = await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', user.id)
          .select();

      if (updateResponse.isEmpty) throw Exception('Profile update failed');

      if (mounted) {
        setState(() {
          userProfile?['avatar_url'] = publicUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Avatar upload error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
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

  void _toggleTheme(ThemeData newTheme) async {
    widget.themeNotifier.value = newTheme;

    final prefs = await SharedPreferences.getInstance();
    if (newTheme == AppThemes.lightTheme) {
      await prefs.setInt('themeMode', 0);
    } else if (newTheme == AppThemes.darkTheme) {
      await prefs.setInt('themeMode', 1);
    } else if (newTheme == AppThemes.pinkTheme) {
      await prefs.setInt('themeMode', 2);
    }
    if (mounted) setState(() {});
  }

  Future<void> fetchUserData() async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isUpdating = false);
      return;
    }

    try {
      final profileId = isCurrentUserProfile ? user.id : widget.userProfile?['id'];
      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, username, bio, avatar_url')
          .eq('id', profileId)
          .single();

      final results = await Future.wait([
        Supabase.instance.client
            .from('subscriptions')
            .select('id')
            .eq('following_id', profileId)
            .count(),
        Supabase.instance.client
            .from('subscriptions')
            .select('id')
            .eq('follower_id', profileId)
            .count(),
      ]);

      final followersCount = results[0].count;
      final subscriptionsCount = results[1].count;

      if (mounted) {
        setState(() {
          userProfile = {
            ...profileResponse,
            'followers_count': followersCount,
            'subscriptions_count': subscriptionsCount,
          };
        });
      }

      await Future.wait([fetchUserPhotos(), fetchUserVideos()]);
    } catch (error) {
      debugPrint('Fetch user data error: $error');
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

  Future<void> deletePhoto(String photoId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('Delete photo failed: No authenticated user');
      return;
    }

    debugPrint('Deleting photo: $photoId for user: ${user.id}');
    try {
      await Supabase.instance.client
          .from('user_photos')
          .delete()
          .eq('id', photoId)
          .eq('user_id', user.id);

      if (mounted) {
        setState(() {
          uploadedPhotos.removeWhere((photo) => photo['id'] == photoId);
          totalPosts = uploadedPhotos.length + uploadedVideos.length;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото успешно удалено')),
        );
      }
    } catch (error) {
      debugPrint('Photo deletion error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при удалении фото: $error')),
        );
      }
    }
  }

  Future<void> deleteVideo(String videoId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('Delete video failed: No authenticated user');
      return;
    }

    debugPrint('Deleting video: $videoId for user: ${user.id}');
    try {
      // Step 1: Fetch comments for the video
      final comments = await Supabase.instance.client
          .from('video_comments')
          .select('id')
          .eq('video_id', videoId);

      debugPrint('Found ${comments.length} comments for video: $videoId');

      // Step 2: Delete comment likes for each comment
      for (var comment in comments) {
        final commentId = comment['id'];
        debugPrint('Deleting comment likes for comment: $commentId');
        await Supabase.instance.client
            .from('comment_likes')
            .delete()
            .eq('comment_id', commentId);
      }

      // Step 3: Delete comments
      debugPrint('Deleting comments for video: $videoId');
      await Supabase.instance.client
          .from('video_comments')
          .delete()
          .eq('video_id', videoId);

      // Step 4: Delete the video
      debugPrint('Deleting video from user_videos: $videoId');
      final response = await Supabase.instance.client
          .from('user_videos')
          .delete()
          .eq('id', videoId)
          .eq('user_id', user.id);

      debugPrint('Delete video response: $response');
      if (mounted) {
        setState(() {
          uploadedVideos.removeWhere((video) => video['id'] == videoId);
          totalPosts = uploadedPhotos.length + uploadedVideos.length;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Видео успешно удалено')),
        );
      }
    } catch (error) {
      debugPrint('Video deletion error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при удалении видео: $error')),
        );
      }
    }
  }

  void _showDeletePhotoDialog(String photoId) {
    final textColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black87 : Colors.white;
    debugPrint('Showing delete photo dialog for photo: $photoId');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: widget.themeNotifier.value.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('Удалить фото', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          content: Text('Вы уверены, что хотите удалить это фото?', style: TextStyle(color: textColor)),
          actions: [
            TextButton(
              onPressed: () {
                debugPrint('Delete photo dialog cancelled');
                Navigator.of(context).pop();
              },
              child: Text('Отмена', style: TextStyle(color: textColor)),
            ),
            TextButton(
              onPressed: () async {
                debugPrint('Delete photo confirmed for photo: $photoId');
                await deletePhoto(photoId);
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text('Удалить', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteVideoDialog(String videoId) {
    final textColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black87 : Colors.white;
    debugPrint('Showing delete video dialog for video: $videoId');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: widget.themeNotifier.value.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('Удалить видео', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          content: Text('Вы уверены, что хотите удалить это видео?', style: TextStyle(color: textColor)),
          actions: [
            TextButton(
              onPressed: () {
                debugPrint('Delete video dialog cancelled');
                Navigator.of(context).pop();
              },
              child: Text('Отмена', style: TextStyle(color: textColor)),
            ),
            TextButton(
              onPressed: () async {
                debugPrint('Delete video confirmed for video: $videoId');
                await deleteVideo(videoId);
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text('Удалить', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> fetchUserPhotos() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('Fetch photos failed: No authenticated user');
      return;
    }

    debugPrint('Fetching photos for user: ${user.id}');
    try {
      final response = await Supabase.instance.client
          .from('user_photos')
          .select('id, photo_url, description, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final photos = List<Map<String, dynamic>>.from(response.map((photo) => {
        'url': photo['photo_url'] ?? '',
        'id': photo['id'] ?? '',
        'description': photo['description'] ?? '',
        'created_at': photo['created_at'] ?? '',
      }).where((photo) => photo['url'].isNotEmpty));

      debugPrint('Fetched ${photos.length} photos: ${photos.map((p) => p['url']).toList()}');
      if (mounted) {
        setState(() {
          uploadedPhotos = photos;
          totalPosts = uploadedPhotos.length + uploadedVideos.length;
        });
      }
    } catch (error) {
      debugPrint('Fetch photos error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при загрузке фотографий: $error')),
        );
      }
    }
  }

  Future<void> fetchUserVideos() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('Fetch videos failed: No authenticated user');
      return;
    }

    debugPrint('Fetching videos for user: ${user.id}');
    try {
      final response = await Supabase.instance.client
          .from('user_videos')
          .select('id, video_url, created_at, description') // Added description
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final videos = List<Map<String, dynamic>>.from(response.map((video) => {
        'url': video['video_url'] ?? '',
        'id': video['id'] ?? '',
        'created_at': video['created_at'] ?? '',
        'description': video['description'] ?? '', // Include description
      }).where((video) => video['url'].isNotEmpty));

      debugPrint('Fetched ${videos.length} videos: ${videos.map((v) => v['url']).toList()}');
      if (mounted) {
        setState(() {
          uploadedVideos = videos;
          totalPosts = uploadedPhotos.length + uploadedVideos.length;
        });
      }
    } catch (error) {
      debugPrint('Fetch videos error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при загрузке видео: $error')),
        );
      }
    }
  }

  Future<Uint8List?> generateThumbnail(String videoUrl) async {
    debugPrint('Generating thumbnail for video: $videoUrl');
    try {
      final thumbnail = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 128,
        maxHeight: 128,
        quality: 75,
      );
      debugPrint('Thumbnail generated: ${thumbnail?.lengthInBytes} bytes');
      return thumbnail;
    } catch (e) {
      debugPrint('Thumbnail generation error: $e');
      return null;
    }
  }

  Future<void> updateProfile(String? username, String? bio) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('Update profile failed: No authenticated user');
      return;
    }

    final updates = {
      'username': username ?? '',
      'bio': bio ?? '',
    };

    debugPrint('Updating profile for user: ${user.id} with $updates');
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .update(updates)
          .eq('id', user.id)
          .select();

      if (response.isNotEmpty && mounted) {
        setState(() {
          userProfile!['username'] = username ?? '';
          userProfile!['bio'] = bio ?? '';
        });
        debugPrint('Profile updated successfully');
      }
    } catch (e) {
      debugPrint('Profile update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось обновить профиль: $e')),
        );
      }
    }
  }

  Future<String?> uploadPhoto(XFile imageFile, String description) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('Upload photo failed: No authenticated user');
      return null;
    }

    final fileExt = imageFile.path.split('.').last;
    final filePath = 'avatars/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    debugPrint('Uploading photo: $filePath');
    try {
      final file = File(imageFile.path);

      await Supabase.instance.client.storage
          .from('avatars')
          .upload(filePath, file, fileOptions: const FileOptions(upsert: true));

      final publicUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(filePath);
      debugPrint('Photo uploaded: $publicUrl');

      await Supabase.instance.client.from('user_photos').insert({
        'user_id': user.id,
        'photo_url': publicUrl,
        'description': description,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      await fetchUserPhotos();
      return publicUrl;
    } catch (e) {
      debugPrint('Photo upload error: $e');
      return null;
    }
  }

  Future<String?> uploadVideo(XFile videoFile, String description) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('Upload video failed: No authenticated user');
      return null;
    }

    final fileExt = videoFile.path.split('.').last;
    final filePath = 'videos/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    debugPrint('Uploading video: $filePath');
    try {
      final file = File(videoFile.path);

      await Supabase.instance.client.storage
          .from('videos')
          .upload(filePath, file, fileOptions: const FileOptions(upsert: true));

      final publicUrl = Supabase.instance.client.storage.from('videos').getPublicUrl(filePath);
      debugPrint('Video uploaded: $publicUrl');

      await Supabase.instance.client.from('user_videos').insert({
        'user_id': user.id,
        'video_url': publicUrl,
        'description': description,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      await fetchUserVideos();
      return publicUrl;
    } catch (e) {
      debugPrint('Video upload error: $e');
      return null;
    }
  }

  void _showEditProfileDialog(BuildContext context) {
    final textColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black87 : Colors.white;
    final secondaryTextColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black54 : Colors.white70;
    final TextEditingController usernameController = TextEditingController(text: userProfile?['username'] ?? '');
    final TextEditingController bioController = TextEditingController(text: userProfile?['bio'] ?? '');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: widget.themeNotifier.value.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: widget.themeNotifier.value.dividerColor, width: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Редактировать профиль',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: textColor),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: 'Имя пользователя',
                        labelStyle: TextStyle(color: secondaryTextColor),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: widget.themeNotifier.value.dividerColor),
                        ),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                      ),
                      style: TextStyle(color: textColor),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: bioController,
                      maxLength: 150,
                      decoration: InputDecoration(
                        labelText: 'Биография',
                        labelStyle: TextStyle(color: secondaryTextColor),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: widget.themeNotifier.value.dividerColor),
                        ),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                      ),
                      style: TextStyle(color: textColor),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    await updateProfile(usernameController.text.trim(), bioController.text.trim());
                    if (mounted) Navigator.pop(context);
                  },
                  child: Text('Сохранить изменения', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showUploadPhotoDialog(BuildContext context) {
    final textColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black87 : Colors.white;
    final secondaryTextColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black54 : Colors.white70;
    final TextEditingController descriptionController = TextEditingController();
    XFile? selectedImage;
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              decoration: BoxDecoration(
                color: widget.themeNotifier.value.cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: widget.themeNotifier.value.dividerColor, width: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Отмена', style: TextStyle(color: textColor)),
                        ),
                        Text('Новое фото', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                        TextButton(
                          onPressed: selectedImage == null || isUploading
                              ? null
                              : () async {
                            setState(() => isUploading = true);
                            Navigator.pop(context); // Close modal immediately
                            if (selectedImage == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ошибка: фото не выбрано')),
                              );
                              return;
                            }

                            try {
                              String? photoUrl = await uploadPhoto(selectedImage!, descriptionController.text);
                              if (photoUrl != null && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Фото успешно загружено')),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ошибка: не удалось загрузить фото')),
                                );
                              }
                            } catch (error) {
                              debugPrint('Upload photo dialog error: $error');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка: $error')),
                                );
                              }
                            }
                          },
                          child: isUploading
                              ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: textColor),
                          )
                              : Text(
                            'Поделиться',
                            style: TextStyle(color: selectedImage == null ? Colors.grey : Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
                      if (pickedFile != null) {
                        setState(() => selectedImage = pickedFile);
                      }
                    },
                    child: Container(
                      height: 300,
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                        image: selectedImage != null
                            ? DecorationImage(image: FileImage(File(selectedImage!.path)), fit: BoxFit.cover)
                            : null,
                      ),
                      child: selectedImage == null
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 150,
                              height: 150,
                              alignment: Alignment.center,
                              child: Icon(Icons.add_photo_alternate, size: 50, color: textColor),
                            ),
                            const SizedBox(height: 8),
                            Text('Выберите фото', style: TextStyle(color: textColor)),
                          ],
                        ),
                      )
                          : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        hintText: 'Добавьте описание...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: secondaryTextColor),
                      ),
                      maxLines: 3,
                      style: TextStyle(color: textColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showUploadVideoDialog(BuildContext context) async {
    final textColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black87 : Colors.white;
    final secondaryTextColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black54 : Colors.white70;
    XFile? videoFile;
    Uint8List? videoThumbnail;
    final TextEditingController descriptionController = TextEditingController();
    bool isUploading = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              decoration: BoxDecoration(
                color: widget.themeNotifier.value.cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: widget.themeNotifier.value.dividerColor, width: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Отмена', style: TextStyle(color: textColor)),
                        ),
                        Text('Новое видео', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                        TextButton(
                          onPressed: videoFile == null || isUploading
                              ? null
                              : () async {
                            setState(() => isUploading = true);
                            Navigator.pop(context); // Close modal immediately
                            if (videoFile == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ошибка: видео не выбрано')),
                              );
                              return;
                            }

                            try {
                              final videoUrl = await uploadVideo(videoFile!, descriptionController.text);
                              if (videoUrl != null && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Видео успешно загружено')),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ошибка: не удалось загрузить видео')),
                                );
                              }
                            } catch (error) {
                              debugPrint('Upload video dialog error: $error');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка: $error')),
                                );
                              }
                            }
                          },
                          child: isUploading
                              ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: textColor),
                          )
                              : Text(
                            'Опубликовать',
                            style: TextStyle(color: videoFile == null ? Colors.grey : Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final pickedFile = await _picker.pickVideo(source: ImageSource.gallery);
                      if (pickedFile != null) {
                        final thumbnail = await generateThumbnail(pickedFile.path);
                        setState(() {
                          videoFile = pickedFile;
                          videoThumbnail = thumbnail;
                        });
                      }
                    },
                    child: Container(
                      height: 300,
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                        image: videoThumbnail != null
                            ? DecorationImage(image: MemoryImage(videoThumbnail!), fit: BoxFit.cover)
                            : null,
                      ),
                      child: videoFile == null
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              alignment: Alignment.center,
                              child: Icon(Icons.video_library, size: 50, color: textColor),
                            ),
                            const SizedBox(height: 8),
                            Text('Выберите видео', style: TextStyle(color: textColor)),
                          ],
                        ),
                      )
                          : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        hintText: 'Добавьте описание...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: secondaryTextColor),
                      ),
                      maxLines: 3,
                      style: TextStyle(color: textColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showUserNoteDialog(String userId, String username) async {
    final textColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black87 : Colors.white;
    final secondaryTextColor = widget.themeNotifier.value.brightness == Brightness.light ? Colors.black54 : Colors.white70;
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
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: widget.themeNotifier.value.dividerColor, width: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Заметка о $username',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: textColor),
                      onPressed: () => Navigator.pop(context),
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
                    hintStyle: TextStyle(color: secondaryTextColor),
                    border: InputBorder.none,
                  ),
                  style: TextStyle(color: textColor),
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
                          child: Text('Удалить', style: TextStyle(color: textColor)),
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
                        child: Text('Сохранить', style: TextStyle(color: Colors.white)),
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
      if (currentUserId == null) {
        debugPrint('Save note failed: No authenticated user');
        return;
      }

      debugPrint('Saving note for user: $currentUserId, target: $targetUserId');
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

      if (mounted) {
        setState(() {
          _userNotes[targetUserId] = noteText;
        });
        debugPrint('Note saved successfully');
      }
    } catch (e) {
      debugPrint('Save note error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
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
      if (currentUserId == null) {
        debugPrint('Delete note failed: No authenticated user');
        return;
      }

      debugPrint('Deleting note for user: $currentUserId, target: $targetUserId');
      await Supabase.instance.client
          .from('user_notes')
          .delete()
          .eq('user_id', currentUserId)
          .eq('target_user_id', targetUserId);

      if (mounted) {
        setState(() {
          _userNotes.remove(targetUserId);
        });
        debugPrint('Note deleted successfully');
      }
    } catch (e) {
      debugPrint('Delete note error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;
    final secondaryTextColor = isLightTheme ? Colors.black54 : Colors.white70;
    final buttonTextColor = widget.themeNotifier.value == AppThemes.darkTheme
        ? Colors.white
        : widget.themeNotifier.value.primaryColor;

    return DefaultTabController(
      initialIndex: 0,
      length: 2,
      child: Scaffold(
        backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
          elevation: 0,
          title: Row(
            children: [
              Text(
                userProfile?['username'] ?? 'Профиль',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ThemeData>(
                icon: Icon(Icons.color_lens, color: textColor),
                color: widget.themeNotifier.value.cardColor,
                onSelected: (ThemeData newTheme) => _toggleTheme(newTheme),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: AppThemes.lightTheme,
                    child: Text('Светлая тема', style: TextStyle(color: textColor)),
                  ),
                  PopupMenuItem(
                    value: AppThemes.darkTheme,
                    child: Text('Темная тема', style: TextStyle(color: textColor)),
                  ),
                  PopupMenuItem(
                    value: AppThemes.pinkTheme,
                    child: Text('Розовая тема', style: TextStyle(color: textColor)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.menu, color: textColor, size: 28),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => LoginScreen(themeNotifier: widget.themeNotifier)),
                );
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: fetchUserData,
          child: userProfile == null
              ? Center(child: CircularProgressIndicator(color: textColor))
              : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _showChangeAvatarDialog(),
                        onLongPress: () => _showUserNoteDialog(
                            userProfile?['id'] ?? '', userProfile?['username'] ?? 'Пользователь'),
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                gradient: _userNotes.containsKey(userProfile?['id'])
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
                                  '${userProfile?['avatar_url']}?timestamp=${DateTime.now().millisecondsSinceEpoch}',
                                )
                                    : null,
                                radius: 40,
                                backgroundColor: Colors.grey[200],
                              ),
                            ),
                            if (_userNotes.containsKey(userProfile?['id']))
                              Positioned(
                                top: -30,
                                child: GestureDetector(
                                  onTap: () => _showUserNoteDialog(
                                      userProfile?['id'] ?? '', userProfile?['username'] ?? 'Пользователь'),
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
                                      _userNotes[userProfile?['id']]!.length > 10
                                          ? '${_userNotes[userProfile?['id']]!.substring(0, 10)}...'
                                          : _userNotes[userProfile?['id']]!,
                                      style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            if (_userNotes.containsKey(userProfile?['id']))
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
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userProfile?['bio'] ?? 'Биография не указана',
                              style: TextStyle(
                                fontSize: 14,
                                color: secondaryTextColor,
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
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Посты',
                            style: TextStyle(
                              fontSize: 14,
                              color: secondaryTextColor,
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
                                userId: userProfile?['id'] ?? '',
                                isFollowers: true,
                                themeNotifier: widget.themeNotifier,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            _isUpdating
                                ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(textColor),
                              ),
                            )
                                : Text(
                              (userProfile?['followers_count'] ?? 0).toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Подписчики',
                              style: TextStyle(
                                fontSize: 14,
                                color: secondaryTextColor,
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
                                userId: userProfile?['id'] ?? '',
                                isFollowers: false,
                                themeNotifier: widget.themeNotifier,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            _isUpdating
                                ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(textColor),
                              ),
                            )
                                : Text(
                              (userProfile?['subscriptions_count'] ?? 0).toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Подписки',
                              style: TextStyle(
                                fontSize: 14,
                                color: secondaryTextColor,
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
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showEditProfileDialog(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: widget.themeNotifier.value.colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isLightTheme ? Colors.grey.shade300 : Colors.grey.shade700,
                              ),
                            ),
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Center(
                              child: Text(
                                'Редактировать профиль',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: textColor,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StatisticsScreen(
                                  userId: userProfile?['id'] ?? '',
                                  themeNotifier: widget.themeNotifier,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: widget.themeNotifier.value.colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isLightTheme ? Colors.grey.shade300 : Colors.grey.shade700,
                              ),
                            ),
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Center(
                              child: Text(
                                'Статистика',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: textColor,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TabBar(
                  labelColor: textColor,
                  unselectedLabelColor: secondaryTextColor,
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
                      Column(
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: widget.themeNotifier.value.cardColor,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onPressed: () => _showUploadPhotoDialog(context),
                            child: Text(
                              'Добавить фото',
                              style: TextStyle(color: buttonTextColor),
                            ),
                          ),
                          Expanded(
                            child: uploadedPhotos.isEmpty
                                ? Center(
                              child: Text(
                                'Нет фотографий',
                                style: TextStyle(color: textColor),
                              ),
                            )
                                : Scrollbar(
                              controller: _photoScrollController,
                              thumbVisibility: true,
                              child: GridView.builder(
                                controller: _photoScrollController,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  childAspectRatio: 1,
                                  crossAxisSpacing: 2,
                                  mainAxisSpacing: 2,
                                ),
                                itemCount: uploadedPhotos.length,
                                itemBuilder: (context, index) {
                                  final photoUrl = uploadedPhotos[index]['url'];
                                  return GestureDetector(
                                    onLongPress: () => isCurrentUserProfile
                                        ? _showDeletePhotoDialog(uploadedPhotos[index]['id'])
                                        : null,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => PhotoDetailScreen(
                                            imageUrl: photoUrl,
                                            timePosted: 'Время публикации: ${DateTime.parse(uploadedPhotos[index]['created_at']).toLocal().toString()}',
                                            initialLikes: 0,
                                            username: userProfile?['username'] ?? 'Имя не указано',
                                            photoId: uploadedPhotos[index]['id'],
                                            description: uploadedPhotos[index]['description'] ?? 'Нет описания',
                                            themeNotifier: widget.themeNotifier,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      color: Colors.grey[200],
                                      child: Image.network(
                                        photoUrl,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Center(
                                            child: CircularProgressIndicator(
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                  (loadingProgress.expectedTotalBytes ?? 1)
                                                  : null,
                                              color: textColor,
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          debugPrint('Photo load error: $error for URL: $photoUrl');
                                          return Center(
                                            child: Icon(
                                              Icons.broken_image,
                                              color: textColor,
                                              size: 50,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: widget.themeNotifier.value.cardColor,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onPressed: () => _showUploadVideoDialog(context),
                            child: Text(
                              'Добавить видео',
                              style: TextStyle(color: buttonTextColor),
                            ),
                          ),
                          Expanded(
                            child: uploadedVideos.isEmpty
                                ? Center(
                              child: Text(
                                'Нет видео',
                                style: TextStyle(color: textColor),
                              ),
                            )
                                : Scrollbar(
                              controller: _videoScrollController,
                              thumbVisibility: true,
                              child: // Inside the GridView.builder for videos in the build method
                              GridView.builder(
                                controller: _videoScrollController,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  childAspectRatio: 1,
                                  crossAxisSpacing: 2,
                                  mainAxisSpacing: 2,
                                ),
                                itemCount: uploadedVideos.length,
                                itemBuilder: (context, index) {
                                  final videoUrl = uploadedVideos[index]['url'];
                                  return GestureDetector(
                                    onLongPress: () => isCurrentUserProfile
                                        ? _showDeleteVideoDialog(uploadedVideos[index]['id'])
                                        : null,
                                    onTap: () {
                                      final videoId = uploadedVideos[index]['id'];
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => MyVideoPlayerScreen(
                                            videoUrl: videoUrl,
                                            videoId: videoId,
                                            username: userProfile?['username'] ?? 'Имя не указано', // Pass username
                                            description: uploadedVideos[index]['description'] ?? '', // Pass description
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      color: Colors.grey[200],
                                      child: FutureBuilder<Uint8List?>(
                                        future: generateThumbnail(videoUrl),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.waiting) {
                                            return Center(child: CircularProgressIndicator(color: textColor));
                                          } else if (snapshot.hasError || !snapshot.hasData) {
                                            debugPrint('Thumbnail error: ${snapshot.error} for URL: $videoUrl');
                                            return Center(
                                              child: Icon(Icons.broken_image, color: textColor, size: 50),
                                            );
                                          } else {
                                            return Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                Image.memory(
                                                  snapshot.data!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    debugPrint('Thumbnail image error: $error for URL: $videoUrl');
                                                    return Center(
                                                      child: Icon(
                                                        Icons.broken_image,
                                                        color: textColor,
                                                        size: 50,
                                                      ),
                                                    );
                                                  },
                                                ),
                                                Center(
                                                  child: Icon(
                                                    Icons.play_circle_outline,
                                                    color: Colors.white.withOpacity(0.8),
                                                    size: 30,
                                                  ),
                                                ),
                                              ],
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                              )
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
      ),
    );
  }
}