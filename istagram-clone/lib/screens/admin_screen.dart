import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../instagram/login_screen.dart';
import 'admin_user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminScreen extends StatelessWidget {
  final ValueNotifier<ThemeData> themeNotifier;

  const AdminScreen({Key? key, required this.themeNotifier}) : super(key: key);

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen(themeNotifier: themeNotifier)),
            (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при выходе: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Администратор'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Пользователи'),
              const Tab(text: 'Жалобы на фото'),
              const Tab(text: 'Жалобы на видео'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _confirmLogout(context),
              tooltip: 'Выйти из аккаунта',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminScreen(themeNotifier: themeNotifier),
                ),
              ),
              tooltip: 'Обновить',
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildUsersTab(context),
            _buildPhotoReportsTab(context),
            _buildVideoReportsTab(context),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение выхода'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _signOut(context);
    }
  }

  // ... (остальной код остается без изменений)
  Widget _buildUsersTab(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: fetchUserProfiles(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'Нет пользователей для отображения',
              style: TextStyle(
                color: themeNotifier.value.textTheme.bodyLarge?.color,
              ),
            ),
          );
        }

        final users = snapshot.data!;

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return _buildUserCard(context, user);
          },
        );
      },
    );
  }

  Widget _buildPhotoReportsTab(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: fetchPhotoReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'Нет жалоб на фото',
              style: TextStyle(
                color: themeNotifier.value.textTheme.bodyLarge?.color,
              ),
            ),
          );
        }

        final reports = snapshot.data!;

        return ListView.builder(
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            return _buildPhotoReportCard(context, report);
          },
        );
      },
    );
  }

  Widget _buildVideoReportsTab(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: fetchVideoReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'Нет жалоб на видео',
              style: TextStyle(
                color: themeNotifier.value.textTheme.bodyLarge?.color,
              ),
            ),
          );
        }

        final reports = snapshot.data!;

        return ListView.builder(
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            return _buildVideoReportCard(context, report);
          },
        );
      },
    );
  }

  Widget _buildUserCard(BuildContext context, Map<String, dynamic> user) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminUserProfileScreen(
                userId: user['id'],
                themeNotifier: themeNotifier,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Hero(
                tag: 'avatar_${user['id']}',
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: CachedNetworkImageProvider(
                    user['avatar_url'] ?? 'https://via.placeholder.com/150',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['username'] ?? 'Без имени',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: themeNotifier.value.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user['email'] ?? 'Нет email',
                      style: TextStyle(
                        color: themeNotifier.value.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _confirmDeleteUser(context, user['id']),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoReportCard(BuildContext context, Map<String, dynamic> report) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: CachedNetworkImageProvider(
                    report['reporter_avatar'] ?? 'https://via.placeholder.com/150',
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  report['reporter_username'] ?? 'Аноним',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: themeNotifier.value.textTheme.bodyLarge?.color,
                  ),
                ),
                const Spacer(),
                Text(
                  '${DateTime.parse(report['created_at']).difference(DateTime.now()).inDays.abs()} д. назад',
                  style: TextStyle(
                    color: themeNotifier.value.textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Причина: ${report['reason']}',
              style: TextStyle(
                color: themeNotifier.value.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 12),
            CachedNetworkImage(
              imageUrl: report['photo_url'],
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _resolvePhotoReport(context, report['id'], false),
                  child: const Text('Отклонить'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _resolvePhotoReport(context, report['id'], true),
                  child: const Text('Удалить фото', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoReportCard(BuildContext context, Map<String, dynamic> report) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: CachedNetworkImageProvider(
                    report['reporter_avatar'] ?? 'https://via.placeholder.com/150',
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  report['reporter_username'] ?? 'Аноним',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: themeNotifier.value.textTheme.bodyLarge?.color,
                  ),
                ),
                const Spacer(),
                Text(
                  '${DateTime.parse(report['created_at']).difference(DateTime.now()).inDays.abs()} д. назад',
                  style: TextStyle(
                    color: themeNotifier.value.textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Причина: ${report['reason']}',
              style: TextStyle(
                color: themeNotifier.value.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Uint8List?>(
              future: generateThumbnail(report['video_url']),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  );
                } else if (snapshot.hasError || !snapshot.hasData) {
                  return Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(child: Icon(Icons.error)),
                  );
                } else {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.memory(
                        snapshot.data!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      const Icon(Icons.play_arrow, size: 50, color: Colors.white),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _resolveVideoReport(context, report['id'], false),
                  child: const Text('Отклонить'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _resolveVideoReport(context, report['id'], true),
                  child: const Text('Удалить видео', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteUser(BuildContext context, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение удаления'),
        content: const Text('Вы уверены, что хотите удалить этого пользователя?'),
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
      await deleteUser(userId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пользователь удалён')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AdminScreen(themeNotifier: themeNotifier),
        ),
      );
    }
  }

  Future<void> _resolvePhotoReport(BuildContext context, String reportId, bool deletePhoto) async {
    try {
      if (deletePhoto) {
        final report = await Supabase.instance.client
            .from('photo_reports')
            .select('photo_id')
            .eq('id', reportId)
            .single();

        await Supabase.instance.client
            .from('user_photos')
            .delete()
            .eq('id', report['photo_id']);
      }

      await Supabase.instance.client
          .from('photo_reports')
          .delete()
          .eq('id', reportId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(deletePhoto ? 'Фото удалено' : 'Жалоба отклонена')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AdminScreen(themeNotifier: themeNotifier),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _resolveVideoReport(BuildContext context, String reportId, bool deleteVideo) async {
    try {
      if (deleteVideo) {
        final report = await Supabase.instance.client
            .from('video_reports')
            .select('video_id')
            .eq('id', reportId)
            .single();

        await Supabase.instance.client
            .from('user_videos')
            .delete()
            .eq('id', report['video_id']);
      }

      await Supabase.instance.client
          .from('video_reports')
          .delete()
          .eq('id', reportId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(deleteVideo ? 'Видео удалено' : 'Жалоба отклонена')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AdminScreen(themeNotifier: themeNotifier),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<List<dynamic>> fetchUserProfiles() async {
    final response = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('is_deleted', false);
    return response;
  }

  Future<List<dynamic>> fetchPhotoReports() async {
    final response = await Supabase.instance.client
        .from('photo_reports')
        .select('''
          id,
          reason,
          created_at,
          photo_id,
          user_photos!photo_reports_photo_id_fkey(photo_url),
          profiles!photo_reports_reported_by_fkey(username, avatar_url)
        ''')
        .order('created_at', ascending: false);

    return response.map((report) {
      return {
        'id': report['id'],
        'reason': report['reason'],
        'created_at': report['created_at'],
        'photo_id': report['photo_id'],
        'photo_url': report['user_photos']['photo_url'],
        'reporter_username': report['profiles']['username'],
        'reporter_avatar': report['profiles']['avatar_url'],
      };
    }).toList();
  }

  Future<List<dynamic>> fetchVideoReports() async {
    final response = await Supabase.instance.client
        .from('video_reports')
        .select('''
          id,
          reason,
          created_at,
          video_id,
          user_videos!video_reports_video_id_fkey(video_url),
          profiles!video_reports_reported_by_fkey(username, avatar_url)
        ''')
        .order('created_at', ascending: false);

    return response.map((report) {
      return {
        'id': report['id'],
        'reason': report['reason'],
        'created_at': report['created_at'],
        'video_id': report['video_id'],
        'video_url': report['user_videos']['video_url'],
        'reporter_username': report['profiles']['username'],
        'reporter_avatar': report['profiles']['avatar_url'],
      };
    }).toList();
  }

  Future<void> deleteUser(String userId) async {
    await Supabase.instance.client
        .from('profiles')
        .update({'is_deleted': true})
        .eq('id', userId);
  }

  Future<Uint8List?> generateThumbnail(String videoUrl) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        quality: 75,
      );
    } catch (e) {
      print("Error generating thumbnail: $e");
      return null;
    }
  }
}