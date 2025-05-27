import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../screens/comments_screen.dart';
import '../screens/user_profile_screen.dart';
import '../screens/photo_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key, required this.themeNotifier}) : super(key: key);
  final ValueNotifier<ThemeData> themeNotifier;

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _photos = [];
  late Future<List<Map<String, dynamic>>> _storiesFuture;
  final Map<String, bool> _likedPhotos = {};
  final Map<String, int> _likesCount = {};
  final Map<String, int> _commentCounts = {};
  final PageController _storyPageController = PageController();
  StreamSubscription<List<Map<String, dynamic>>>? _photoSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _likesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _commentsSubscription;

  @override
  void initState() {
    super.initState();
    _storiesFuture = fetchStoriesForSubscribedUsers();
    loadLikedPhotos();
    _initializePhotos();
    _subscribeToPhotos();
    _subscribeToLikes();
    _subscribeToComments();
  }

  @override
  void dispose() {
    _storyPageController.dispose();
    _photoSubscription?.cancel();
    _likesSubscription?.cancel();
    _commentsSubscription?.cancel();
    super.dispose();
  }

  void updatePhotoState(String photoId, int likes, bool isLiked, int comments) {
    if (mounted) {
      setState(() {
        _likesCount[photoId] = likes;
        _likedPhotos[photoId] = isLiked;
        _commentCounts[photoId] = comments;
        final photoIndex = _photos.indexWhere((p) => p['id'] == photoId);
        if (photoIndex != -1) {
          _photos[photoIndex]['likes_count'] = likes;
          _photos[photoIndex]['comments_count'] = comments;
        }
      });
      _saveLikedPhotos();
      print('Updated photo state: photoId=$photoId, likes=$likes, isLiked=$isLiked, comments=$comments');
    }
  }

  Future<void> _initializePhotos() async {
    final photos = await fetchPhotosWithUsernames();
    if (mounted) {
      setState(() {
        _photos = photos;
      });
    }
  }

  void _subscribeToPhotos() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      print('No authenticated user for photo subscription');
      return;
    }

    print('Subscribing to user_photos stream');
    _photoSubscription = Supabase.instance.client
        .from('user_photos')
        .stream(primaryKey: ['id'])
        .listen((List<Map<String, dynamic>> photos) async {
      print('Received photo stream update with ${photos.length} photos');
      for (final newPhoto in photos) {
        final photoUserId = newPhoto['user_id'] as String?;
        final createdAt = newPhoto['created_at'] as String?;
        final description = newPhoto['description'] as String?;
        print('New photo ID: ${newPhoto['id']}, user_id: $photoUserId, created_at: $createdAt, description: $description');

        if (photoUserId == null) continue;

        final subscriptionsResponse = await Supabase.instance.client
            .from('subscriptions')
            .select('following_id')
            .eq('follower_id', user.id)
            .eq('following_id', photoUserId);

        if (subscriptionsResponse.isNotEmpty) {
          final usernameResponse = await Supabase.instance.client
              .from('profiles')
              .select('username')
              .eq('id', photoUserId)
              .maybeSingle();

          final commentsCountResponse = await Supabase.instance.client
              .from('comments')
              .select('id')
              .eq('photo_id', newPhoto['id']);

          final totalLikesResponse = await Supabase.instance.client
              .from('likes')
              .select('user_id')
              .eq('photo_id', newPhoto['id']);

          final isLikedResponse = await Supabase.instance.client
              .from('likes')
              .select()
              .eq('photo_id', newPhoto['id'])
              .eq('user_id', user.id)
              .maybeSingle();

          final photoData = {
            'id': newPhoto['id'],
            'user_id': photoUserId,
            'photo_url': newPhoto['photo_url'] ?? '',
            'created_at': createdAt,
            'description': description,
            'username': usernameResponse?['username'] ?? 'Имя пользователя',
            'likes_count': totalLikesResponse.length,
            'comments_count': commentsCountResponse.length,
          };

          if (mounted && createdAt != null) {
            setState(() {
              if (!_photos.any((p) => p['id'] == photoData['id'])) {
                _photos.insert(0, photoData);
                _likesCount[photoData['id']] = photoData['likes_count'];
                _likedPhotos[photoData['id']] = isLikedResponse != null;
                _commentCounts[photoData['id']] = photoData['comments_count'];
                _photos.sort((a, b) => DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at'])));
                print('Added photo: photoId=${photoData['id']}, likes=${photoData['likes_count']}, comments=${photoData['comments_count']}');
              }
            });
            _saveLikedPhotos();
          }
        }
      }
    }, onError: (error) {
      print('Photo stream error: $error');
    });
  }

  void _subscribeToLikes() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      print('No authenticated user for likes subscription');
      return;
    }

    print('Subscribing to likes stream');
    _likesSubscription?.cancel();
    final photoIdsToUpdate = <String>{};
    Timer? debounceTimer;

    _likesSubscription = Supabase.instance.client
        .from('likes')
        .stream(primaryKey: ['id'])
        .listen((List<Map<String, dynamic>> likes) {
      print('Received likes stream update with ${likes.length} likes');
      photoIdsToUpdate.addAll(
        likes
            .map((like) => like['photo_id'] as String?)
            .where((id) => id != null && _photos.any((p) => p['id'] == id))
            .cast<String>(),
      );

      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 500), () async {
        for (final photoId in photoIdsToUpdate) {
          final likesCountResponse = await Supabase.instance.client
              .from('likes')
              .select('user_id')
              .eq('photo_id', photoId);
          final isLikedResponse = await Supabase.instance.client
              .from('likes')
              .select()
              .eq('photo_id', photoId)
              .eq('user_id', user.id)
              .maybeSingle();

          final newLikesCount = likesCountResponse.length;
          final newIsLiked = isLikedResponse != null;

          if (mounted && (_likesCount[photoId] != newLikesCount || _likedPhotos[photoId] != newIsLiked)) {
            updatePhotoState(
              photoId,
              newLikesCount,
              newIsLiked,
              _commentCounts[photoId] ?? 0,
            );
            print('Updated likes via stream: photoId=$photoId, likes=$newLikesCount, isLiked=$newIsLiked');
          }
        }
        photoIdsToUpdate.clear();
      });
    }, onError: (error) {
      print('Likes stream error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка потока лайков: $error')),
        );
      }
    });
  }

  void _subscribeToComments() {
    print('Subscribing to comments stream');
    _commentsSubscription = Supabase.instance.client
        .from('comments')
        .stream(primaryKey: ['id'])
        .listen((List<Map<String, dynamic>> comments) async {
      print('Received comments stream update with ${comments.length} comments');
      final photoIds = _photos.map((p) => p['id'] as String).toSet();
      for (final photoId in photoIds) {
        final commentsCountResponse = await Supabase.instance.client
            .from('comments')
            .select('id')
            .eq('photo_id', photoId);

        if (mounted) {
          setState(() {
            _commentCounts[photoId] = commentsCountResponse.length;
            final photoIndex = _photos.indexWhere((p) => p['id'] == photoId);
            if (photoIndex != -1) {
              _photos[photoIndex]['comments_count'] = commentsCountResponse.length;
            }
            print('Comments updated: photoId=$photoId, commentCount=${commentsCountResponse.length}');
          });
        }
      }
    }, onError: (error) {
      print('Comments stream error: $error');
    });
  }

  Future<void> loadLikedPhotos() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      print('No authenticated user for loading liked photos');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final likesResponse = await Supabase.instance.client
          .from('likes')
          .select('photo_id')
          .eq('user_id', user.id);
      final dbLikedPhotos = Set<String>.from(likesResponse.map((like) => like['photo_id']));

      if (mounted) {
        setState(() {
          _likedPhotos.clear();
          for (var photoId in dbLikedPhotos) {
            _likedPhotos[photoId] = true;
          }
        });
      }

      await prefs.setString('likedPhotos', json.encode(_likedPhotos));
      print('Loaded likedPhotos: $_likedPhotos');
    } catch (e) {
      print('Error loading liked photos: $e');
    }
  }

  Future<void> _saveLikedPhotos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('likedPhotos', json.encode(_likedPhotos));
    print('Saved likedPhotos to SharedPreferences: $_likedPhotos');
  }

  Future<List<Map<String, dynamic>>> fetchPhotosWithUsernames() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];

      final subscriptionsResponse = await Supabase.instance.client
          .from('subscriptions')
          .select('following_id')
          .eq('follower_id', user.id);

      final subscribedUserIds = subscriptionsResponse
          .map((sub) => sub['following_id'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();

      if (subscribedUserIds.isEmpty) return [];

      final userPhotosResponse = await Supabase.instance.client
          .from('user_photos')
          .select('id, user_id, photo_url, created_at, description')
          .inFilter('user_id', subscribedUserIds)
          .order('created_at', ascending: false)
          .limit(20);

      List<Map<String, dynamic>> photos = List<Map<String, dynamic>>.from(userPhotosResponse);

      if (photos.isEmpty) return [];

      photos.sort((a, b) => DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at'])));

      final usernamesResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, username');

      final Map<String, String> userMap = {
        for (var user in usernamesResponse)
          if (user['id'] != null && user['username'] != null)
            user['id'] as String: user['username'] as String,
      };

      for (var photo in photos) {
        final userId = photo['user_id'] as String?;
        photo['username'] = userMap[userId] ?? 'Имя пользователя';

        final commentsCountResponse = await Supabase.instance.client
            .from('comments')
            .select('id')
            .eq('photo_id', photo['id']);
        photo['comments_count'] = commentsCountResponse.length;
        _commentCounts[photo['id']] = commentsCountResponse.length;

        final totalLikesResponse = await Supabase.instance.client
            .from('likes')
            .select('user_id')
            .eq('photo_id', photo['id']);
        photo['likes_count'] = totalLikesResponse.length;
        _likesCount[photo['id']] = totalLikesResponse.length;

        final isLikedResponse = await Supabase.instance.client
            .from('likes')
            .select()
            .eq('photo_id', photo['id'])
            .eq('user_id', user.id)
            .maybeSingle();
        _likedPhotos[photo['id']] = isLikedResponse != null;

        print('Photo ID: ${photo['id']}, likes_count: ${photo['likes_count']}, isLiked: ${_likedPhotos[photo['id']]}, comments_count: ${photo['comments_count']}');
      }

      // Clear stale entries
      _likesCount.removeWhere((key, value) => !photos.any((p) => p['id'] == key));
      _likedPhotos.removeWhere((key, value) => !photos.any((p) => p['id'] == key));
      _commentCounts.removeWhere((key, value) => !photos.any((p) => p['id'] == key));

      return photos;
    } catch (e) {
      print('Error fetching photos: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchStoriesForSubscribedUsers() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];

      final subscriptionsResponse = await Supabase.instance.client
          .from('subscriptions')
          .select('following_id')
          .eq('follower_id', user.id);

      final subscribedUserIds = subscriptionsResponse
          .map((sub) => sub['following_id'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();

      if (subscribedUserIds.isEmpty) return [];

      final notesResponse = await Supabase.instance.client
          .from('user_notes')
          .select('*')
          .inFilter('user_id', subscribedUserIds)
          .order('created_at', ascending: false);

      print('Fetched stories: $notesResponse');

      if (notesResponse.isEmpty) return [];

      final profilesResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', subscribedUserIds);

      final profilesMap = {
        for (var profile in profilesResponse)
          profile['id'] as String: {
            'username': profile['username'] as String? ?? 'User',
            'avatar_url': profile['avatar_url'] as String?,
          }
      };

      return notesResponse.map<Map<String, dynamic>>((note) {
        final userId = note['user_id'] as String;
        final userData = profilesMap[userId] ?? {'username': 'User', 'avatar_url': null};

        return {
          'id': note['id'],
          'user_id': userId,
          'note_text': note['note_text'] as String? ?? '',
          'username': userData['username'] as String,
          'avatar_url': userData['avatar_url'] as String?,
          'created_at': note['created_at'] as String?,
        };
      }).toList();
    } catch (e) {
      print('Error fetching stories: $e');
      return [];
    }
  }

  Future<void> _refreshContent() async {
    await _initializePhotos();
    setState(() {
      _storiesFuture = fetchStoriesForSubscribedUsers();
    });
    await _storiesFuture; // Ensure stories are fetched before completing
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Контент обновлен')),
      );
    }
  }

  void _showFullScreenStory(BuildContext context, List<Map<String, dynamic>> stories, int initialIndex) {
    print('Opening story viewer with initialIndex=$initialIndex, stories count=${stories.length}');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _StoryViewer(
          stories: stories,
          initialIndex: initialIndex,
          themeNotifier: widget.themeNotifier,
        ),
      ),
    ).then((_) {
      print('Returned from story viewer');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;
    final secondaryTextColor = isLightTheme ? Colors.black54 : Colors.white70;

    return Scaffold(
      backgroundColor: isLightTheme ? Colors.white : Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        elevation: 0,
        backgroundColor: isLightTheme ? Colors.white : Colors.black,
        title: const SizedBox(
          height: 50,
          width: 120,
          child: Image(image: AssetImage('assets/img/logo.png')),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshContent,
        child: Column(
          children: [
            SizedBox(
              height: 100,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _storiesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: textColor));
                  }

                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    print('No stories available: error=${snapshot.error}, data=${snapshot.data}');
                    return const SizedBox.shrink();
                  }

                  final stories = snapshot.data!;
                  print('Rendering ${stories.length} stories');
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: stories.length,
                    itemBuilder: (context, index) {
                      final story = stories[index];
                      return GestureDetector(
                        onTap: () => _showFullScreenStory(context, stories, index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: 80,
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isLightTheme
                                        ? [Colors.purpleAccent, Colors.pinkAccent, Colors.orangeAccent]
                                        : [Colors.purple, Colors.pink, Colors.orange],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: isLightTheme ? Colors.grey.withOpacity(0.3) : Colors.black.withOpacity(0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 30,
                                  backgroundColor: isLightTheme ? Colors.grey[200] : Colors.grey[800],
                                  child: ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: story['avatar_url'] ?? '',
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Image.asset(
                                        'assets/img/story.png',
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                      ),
                                      errorWidget: (context, url, error) {
                                        print('Error loading avatar: $error');
                                        return Image.asset(
                                          'assets/img/story.png',
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                story['username']?.toString() ?? 'User',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  color: textColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                maxLines: 1,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Expanded(
              child: _photos.isEmpty
                  ? Center(
                child: Text(
                  'Нет постов.',
                  style: TextStyle(fontFamily: 'Roboto', color: textColor, fontSize: 16),
                ),
              )
                  : ListView.builder(
                itemCount: _photos.length,
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  return PhotoCardWidget(
                    photo: photo,
                    themeNotifier: widget.themeNotifier,
                    isLiked: _likedPhotos[photo['id']] ?? false,
                    likesCount: _likesCount[photo['id']] ?? photo['likes_count'] ?? 0,
                    commentCount: _commentCounts[photo['id']] ?? photo['comments_count'] ?? 0,
                    onLikeToggled: (isLiked, newLikesCount) {
                      setState(() {
                        _likedPhotos[photo['id']] = isLiked;
                        _likesCount[photo['id']] = newLikesCount;
                        final photoIndex = _photos.indexWhere((p) => p['id'] == photo['id']);
                        if (photoIndex != -1) {
                          _photos[photoIndex]['likes_count'] = newLikesCount;
                        }
                      });
                      _saveLikedPhotos();
                    },
                    onCommentChanged: (count) {
                      setState(() {
                        _commentCounts[photo['id']] = count;
                        final photoIndex = _photos.indexWhere((p) => p['id'] == photo['id']);
                        if (photoIndex != -1) {
                          _photos[photoIndex]['comments_count'] = count;
                        }
                      });
                    },
                    onPhotoTapped: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PhotoDetailScreen(
                            imageUrl: photo['photo_url'],
                            timePosted: photo['created_at'],
                            initialLikes: _likesCount[photo['id']] ?? photo['likes_count'] ?? 0,
                            username: photo['username'],
                            photoId: photo['id'],
                            description: photo['description'] ?? '',
                            themeNotifier: widget.themeNotifier,
                            onLikeChanged: (photoId, likes, isLiked) {
                              updatePhotoState(
                                  photoId, likes, isLiked, _commentCounts[photoId] ?? photo['comments_count']);
                            },
                            onCommentChanged: (photoId, comments) {
                              updatePhotoState(photoId, _likesCount[photoId] ?? photo['likes_count'],
                                  _likedPhotos[photoId] ?? false, comments);
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryViewer extends StatefulWidget {
  final List<Map<String, dynamic>> stories;
  final int initialIndex;
  final ValueNotifier<ThemeData> themeNotifier;

  const _StoryViewer({
    required this.stories,
    required this.initialIndex,
    required this.themeNotifier,
  });

  @override
  _StoryViewerState createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  int _currentIndex = 0;
  Timer? _storyTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        print('Story timer completed, moving to next story: index=$_currentIndex');
        _nextStory();
      }
    });

    _startStoryTimer();
  }

  @override
  void dispose() {
    print('Disposing _StoryViewerState');
    _storyTimer?.cancel();
    _animationController.stop();
    _animationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _startStoryTimer() {
    print('Starting story timer for index=$_currentIndex');
    _storyTimer?.cancel();
    _animationController.reset();
    _animationController.forward();
    _storyTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        print('Story timer triggered, moving to next story: index=$_currentIndex');
        _nextStory();
      }
    });
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      if (mounted) {
        setState(() {
          _currentIndex++;
          print('Moving to next story: index=$_currentIndex');
          _pageController.animateToPage(
            _currentIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          _startStoryTimer();
        });
      }
    } else {
      print('No more stories, closing viewer');
      Navigator.pop(context);
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      if (mounted) {
        setState(() {
          _currentIndex--;
          print('Moving to previous story: index=$_currentIndex');
          _pageController.animateToPage(
            _currentIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          _startStoryTimer();
        });
      }
    }
  }

  void _onTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < screenWidth / 3) {
      print('Tapped left, going to previous story');
      _previousStory();
    } else if (details.globalPosition.dx > 2 * screenWidth / 3) {
      print('Tapped right, going to next story');
      _nextStory();
    } else {
      print('Tapped center, pausing story');
      _storyTimer?.cancel();
      _animationController.stop();
    }
  }

  void _onTapUp(TapUpDetails details) {
    print('Resuming story timer');
    _startStoryTimer();
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;
    final backgroundColor = isLightTheme ? Colors.white : Colors.black87;

    print('Building _StoryViewer for index=$_currentIndex');

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.stories.length,
              itemBuilder: (context, index) {
                final story = widget.stories[index];
                print('Rendering story index=$index, username=${story['username']}');
                return Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isLightTheme
                                    ? [Colors.purpleAccent, Colors.pinkAccent, Colors.orangeAccent]
                                    : [Colors.purple, Colors.pink, Colors.orange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: isLightTheme ? Colors.grey.withOpacity(0.3) : Colors.black.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 50,
                              child: ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: story['avatar_url'] ?? 'https://via.placeholder.com/150',
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => CircularProgressIndicator(color: textColor),
                                  errorWidget: (context, url, error) {
                                    print('Error loading avatar: $error');
                                    return ClipOval(
                                      child: Image.asset(
                                        'assets/img/story.png',
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            story['username']?.toString() ?? 'User',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              color: textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: isLightTheme ? Colors.grey.withOpacity(0.5) : Colors.black.withOpacity(0.5),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isLightTheme ? Colors.grey[100] : Colors.grey[900],
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: isLightTheme ? Colors.grey.withOpacity(0.3) : Colors.black.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              story['note_text']?.toString() ?? 'Нет текста',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                color: textColor,
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              onPageChanged: (index) {
                if (mounted) {
                  setState(() {
                    _currentIndex = index;
                    print('Page changed to index=$index');
                    _startStoryTimer();
                  });
                }
              },
            ),
          ),
          Positioned(
            top: 40,
            left: 10,
            right: 10,
            child: Row(
              children: List.generate(
                widget.stories.length,
                    (index) => Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 4,
                    child: index == _currentIndex
                        ? AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, _) => LinearProgressIndicator(
                        value: _animationController.value,
                        backgroundColor: Colors.grey.withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isLightTheme ? Colors.purpleAccent : Colors.pink,
                        ),
                      ),
                    )
                        : Container(
                      color: index < _currentIndex
                          ? (isLightTheme ? Colors.purpleAccent : Colors.pink)
                          : Colors.grey.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 10,
            child: IconButton(
              icon: Icon(Icons.close, color: textColor, size: 30),
              onPressed: () {
                print('Closing story viewer');
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoCardWidget extends StatefulWidget {
  final Map<String, dynamic> photo;
  final ValueNotifier<ThemeData> themeNotifier;
  final bool isLiked;
  final int likesCount;
  final int commentCount;
  final Function(bool, int) onLikeToggled;
  final Function(int) onCommentChanged;
  final VoidCallback onPhotoTapped;

  const PhotoCardWidget({
    Key? key,
    required this.photo,
    required this.themeNotifier,
    required this.isLiked,
    required this.likesCount,
    required this.commentCount,
    required this.onLikeToggled,
    required this.onCommentChanged,
    required this.onPhotoTapped,
  }) : super(key: key);

  @override
  _PhotoCardWidgetState createState() => _PhotoCardWidgetState();
}

class _PhotoCardWidgetState extends State<PhotoCardWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late bool _isLiked;
  late int _likesCount;
  bool _isLiking = false;
  bool _isReporting = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;
    _likesCount = widget.likesCount;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleLikeToggle() async {
    if (_isLiking) return;

    setState(() {
      _isLiking = true;
      _isLiked = !_isLiked;
      _likesCount = _likesCount + (_isLiked ? 1 : -1);
      widget.onLikeToggled(_isLiked, _likesCount); // Notify parent immediately
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        print('handleLikeToggle: Пользователь не аутентифицирован');
        setState(() {
          _isLiking = false;
          _isLiked = !_isLiked;
          _likesCount = _likesCount + (_isLiked ? 1 : -1);
          widget.onLikeToggled(_isLiked, _likesCount);
        });
        return;
      }

      final photoId = widget.photo['id'] as String;
      final response = await Supabase.instance.client
          .from('likes')
          .select()
          .eq('photo_id', photoId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null) {
        await Supabase.instance.client
            .from('likes')
            .delete()
            .eq('id', response['id']);
      } else {
        await Supabase.instance.client.from('likes').insert({
          'user_id': user.id,
          'photo_id': photoId,
        });
      }

      final likesCountResponse = await Supabase.instance.client
          .from('likes')
          .select('user_id')
          .eq('photo_id', photoId);

      final isLikedResponse = await Supabase.instance.client
          .from('likes')
          .select()
          .eq('photo_id', photoId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isLiked = isLikedResponse != null;
          _likesCount = likesCountResponse.length;
        });
        widget.onLikeToggled(_isLiked, _likesCount);
        _animationController.forward().then((_) => _animationController.reverse());
        print('Like toggled: photoId=$photoId, likes=$_likesCount, isLiked=$_isLiked');
      }
    } catch (e) {
      print('Ошибка при переключении лайка: $e');
      if (mounted) {
        setState(() {
          _isLiking = false;
          _isLiked = !_isLiked;
          _likesCount = _likesCount + (_isLiked ? 1 : -1);
          widget.onLikeToggled(_isLiked, _likesCount);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при лайке: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLiking = false;
        });
      }
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
        'photo_id': widget.photo['id'],
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
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
          title: Text(
            'Пожаловаться на фото',
            style: TextStyle(fontFamily: 'Roboto', color: textColor),
          ),
          content: TextField(
            controller: reasonController,
            decoration: InputDecoration(
              hintText: 'Причина жалобы',
              hintStyle: TextStyle(fontFamily: 'Roboto', color: textColor.withOpacity(0.6)),
            ),
            style: TextStyle(fontFamily: 'Roboto', color: textColor),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена', style: TextStyle(fontFamily: 'Roboto', color: textColor)),
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
                style: TextStyle(fontFamily: 'Roboto', color: _isReporting ? Colors.grey : Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showOptionsMenu() {
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
                  style: TextStyle(fontFamily: 'Roboto', color: textColor),
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
                  style: TextStyle(fontFamily: 'Roboto', color: textColor),
                ),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = widget.themeNotifier.value.brightness == Brightness.light;
    final textColor = isLightTheme ? Colors.black87 : Colors.white;
    final secondaryTextColor = isLightTheme ? Colors.black54 : Colors.white70;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: isLightTheme ? Colors.white : Colors.grey[900],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(
                        userId: widget.photo['user_id'],
                        themeNotifier: widget.themeNotifier,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.photo['username']?.toString() ?? 'Имя пользователя',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert, color: textColor),
                onPressed: _showOptionsMenu,
              ),
            ],
          ),
          GestureDetector(
            onTap: widget.onPhotoTapped,
            onDoubleTap: _handleLikeToggle,
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  widget.photo['photo_url']?.toString() ?? '',
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
                  errorBuilder: (context, error, stackTrace) {
                    print('Error loading photo: $error');
                    return Container(
                      color: Colors.grey[300],
                      child: const Center(child: Icon(Icons.error, color: Colors.red)),
                    );
                  },
                ),
              ),
            ),
          ),
          if (widget.photo['description'] != null && widget.photo['description'].isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Описание: ',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: widget.photo['description']?.toString(),
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        color: textColor,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _isLiking ? null : _handleLikeToggle,
                      child: _isLiking
                          ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : ScaleTransition(
                        scale: _scaleAnimation,
                        child: Icon(
                          _isLiked ? Icons.favorite : Icons.favorite_border,
                          color: _isLiked ? Colors.red : textColor,
                          size: 28,
                        ),
                      ),
                    ),


                    const SizedBox(width: 10),
                    IconButton(
                      icon: Icon(Icons.comment, color: textColor, size: 28),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CommentsScreen(
                              photoId: widget.photo['id'],
                              onCommentAdded: (int count) {
                                widget.onCommentChanged(count);
                              },
                              themeNotifier: widget.themeNotifier,
                            ),
                          ),
                        );
                      },
                    ),
                    Text(
                      '${widget.commentCount}',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        color: secondaryTextColor,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}