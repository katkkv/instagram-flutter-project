import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:newinstagramclone/screens/my_video_player_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/photo_detail_screen.dart';
import '../screens/user_profile_screen.dart';

class SearchScreen extends StatefulWidget {
  final ValueNotifier<ThemeData> themeNotifier;

  const SearchScreen({Key? key, required this.themeNotifier}) : super(key: key);

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String searchTerm = '';
  List<dynamic> allMedia = [];
  List<dynamic> userProfiles = [];
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchAllMedia();
    fetchAllUserProfiles();
    _searchFocusNode.addListener(() {
      setState(() {
        _isSearching = _searchFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> fetchAllMedia({int retryCount = 0}) async { // Reduced retries to 0 for now
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Paginate with a smaller limit
      const limit = 10; // Reduced from 20 to 10
      final photoResponse = await Supabase.instance.client
          .from('user_photos')
          .select('id, user_id, photo_url, created_at, description')
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(Duration(seconds: 15)); // Reduced timeout

      final videoResponse = await Supabase.instance.client
          .from('user_videos')
          .select('id, user_id, video_url, created_at, description')
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(Duration(seconds: 15));

      debugPrint('Photos fetched: ${photoResponse.length}');
      debugPrint('Videos fetched: ${videoResponse.length}');

      List<dynamic> mediaList = [...photoResponse, ...videoResponse];

      if (mediaList.isEmpty) {
        debugPrint('No media available in user_photos or user_videos');
        setState(() {
          _errorMessage = 'Нет доступных медиа';
          _isLoading = false;
        });
        return;
      }

      // Batch fetch profiles
      final userIds = mediaList.map((media) => media['user_id'] as String).toSet().toList();
      debugPrint('Fetching profiles for ${userIds.length} user IDs');
      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', userIds) // Use in filter for batch query
          .timeout(Duration(seconds: 10));

      // Create a map for quick lookup
      final profileMap = {
        for (var profile in profileResponse)
          profile['id']: {
            'username': profile['username'] ?? 'Unknown',
            'avatar_url': profile['avatar_url'] ?? '',
          }
      };

      final combinedMedia = mediaList.map((media) {
        final userId = media['user_id'];
        final profile = profileMap[userId] ?? {'username': 'Unknown', 'avatar_url': ''};
        return {
          ...media,
          'username': profile['username'],
          'avatar_url': profile['avatar_url'],
          'likes_count': 0,
        };
      }).toList();

      debugPrint('Combined media count: ${combinedMedia.length}');
      setState(() {
        allMedia = combinedMedia;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching media: $e');
      setState(() {
        _errorMessage = 'Ошибка загрузки медиа: ${e.toString().contains('57014') ? 'Таймаут запроса' : e}';
        _isLoading = false;
      });
    }
  }

  Future<void> fetchAllUserProfiles() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, username, avatar_url')
          .order('username', ascending: true)
          .limit(50)
          .timeout(Duration(seconds: 30));

      debugPrint('Profiles fetched: ${response.length}');
      if (response.isNotEmpty) {
        setState(() {
          userProfiles = response;
        });
      }
    } catch (e) {
      debugPrint('Error fetching profiles: $e');
    }
  }

  List<dynamic> filterUserProfiles() {
    if (searchTerm.isEmpty) {
      return [];
    } else {
      return userProfiles.where((profile) {
        final username = profile['username'] as String;
        return username.toLowerCase().contains(searchTerm.toLowerCase());
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final random = Random();
    final shuffledMedia = List.from(allMedia)..shuffle(random);
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    return Scaffold(
      backgroundColor: isLightTheme ? Colors.white : Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: isLightTheme ? Colors.white : Colors.black,
        elevation: 0,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: isLightTheme ? Colors.grey[200] : Colors.grey[800],
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: isLightTheme ? Colors.grey.withOpacity(0.2) : Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            focusNode: _searchFocusNode,
            onChanged: (value) {
              setState(() {
                searchTerm = value;
              });
            },
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.search,
                color: isLightTheme ? Colors.grey[600] : Colors.grey[400],
              ),
              hintText: 'Поиск',
              border: InputBorder.none,
              hintStyle: TextStyle(
                color: isLightTheme ? Colors.grey[600] : Colors.grey[400],
                fontSize: 16,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            ),
            style: TextStyle(
              color: isLightTheme ? Colors.black : Colors.white,
              fontSize: 16,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(color: textColor),
      )
          : _errorMessage != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: fetchAllMedia,
              style: ElevatedButton.styleFrom(
                backgroundColor: isLightTheme ? Colors.blue : Colors.blue[300],
                foregroundColor: Colors.white,
              ),
              child: const Text('Повторить'),
            ),
          ],
        ),
      )
          : searchTerm.isEmpty
          ? RefreshIndicator(
        onRefresh: fetchAllMedia,
        color: textColor,
        child: allMedia.isEmpty
            ? Center(
          child: Text(
            'Нет медиа для отображения',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        )
            : _buildExploreGrid(shuffledMedia, isLightTheme),
      )
          : _buildSearchResults(isLightTheme),
    );
  }

  Widget _buildSearchResults(bool isLightTheme) {
    final filteredUsers = filterUserProfiles();
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    return ListView.builder(
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final user = filteredUsers[index];
        return ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: isLightTheme ? Colors.grey[300] : Colors.grey[800],
            backgroundImage: user['avatar_url']?.isNotEmpty ?? false
                ? NetworkImage(user['avatar_url'])
                : null,
            child: user['avatar_url']?.isNotEmpty ?? false
                ? null
                : const Icon(Icons.person, color: Colors.white),
          ),
          title: Text(
            user['username'],
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Text(
            '@${user['username'].toLowerCase()}',
            style: TextStyle(
              color: isLightTheme ? Colors.grey[600] : Colors.grey[400],
              fontSize: 14,
            ),
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(
                  userId: user['id'],
                  themeNotifier: widget.themeNotifier,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExploreGrid(List<dynamic> media, bool isLightTheme) {
    final random = Random();
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    return MasonryGridView.builder(
      gridDelegate: const SliverSimpleGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
      ),
      itemCount: media.length,
      padding: const EdgeInsets.all(4.0),
      itemBuilder: (context, index) {
        final item = media[index];
        final heightMultiplier = 1.0 + random.nextDouble() * 0.8;
        final isVideo = item['video_url'] != null;

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => isVideo
                    ? MyVideoPlayerScreen(
                  videoUrl: item['video_url'] ?? '',
                  videoId: item['id'],
                  username: item['username'],
                  description: item['description'] ?? '',
                )
                    : PhotoDetailScreen(
                  imageUrl: item['photo_url'] ?? '',
                  timePosted: item['created_at'],
                  initialLikes: item['likes_count'],
                  username: item['username'],
                  photoId: item['id'],
                  description: item['description'] ?? '',
                  themeNotifier: widget.themeNotifier,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.all(2.0),
            height: 120 * heightMultiplier,
            decoration: BoxDecoration(
              color: isLightTheme ? Colors.grey[200] : Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: isLightTheme ? Colors.grey.withOpacity(0.2) : Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  isVideo
                      ? Image.asset(
                    'assets/images/video_placeholder.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('Video placeholder error: $error');
                      return _buildErrorPlaceholder(isLightTheme, textColor);
                    },
                  )
                      : item['photo_url']?.isNotEmpty ?? false
                      ? Image.network(
                    item['photo_url'],
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
                              : null,
                          color: isLightTheme ? Colors.grey[600] : Colors.grey[400],
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('Photo load error for ${item['photo_url']}: $error');
                      return _buildErrorPlaceholder(isLightTheme, textColor);
                    },
                  )
                      : _buildErrorPlaceholder(isLightTheme, textColor),
                  if (isVideo)
                    const Center(
                      child: Icon(
                        Icons.play_circle_filled,
                        color: Colors.white,
                        size: 40,
                        shadows: [
                          Shadow(
                            blurRadius: 4,
                            color: Colors.black54,
                            offset: Offset(0, 2),
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
    );
  }

  Widget _buildErrorPlaceholder(bool isLightTheme, Color textColor) {
    return Container(
      color: isLightTheme ? Colors.grey[300] : Colors.grey[800],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Статическое изображение из assets
            Image.asset(
              'assets/img/img.png', // Укажите правильный путь к вашему изображению
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 8),

          ],
        ),
      ),
    );
  }
}