import 'package:flutter/material.dart';
import 'package:newinstagramclone/instagram/profile_scree.dart';
import 'package:newinstagramclone/instagram/reels_screen.dart';
import 'package:newinstagramclone/instagram/search_screen.dart';
import 'package:newinstagramclone/instagram/home_screen.dart';

class MainScreen extends StatefulWidget {
  final Map<String, dynamic>? userProfile;
  final ValueNotifier<ThemeData> themeNotifier;
  final int initialIndex;

  const MainScreen({
    Key? key,
    this.userProfile,
    required this.themeNotifier,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;
  late List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _widgetOptions = [
      HomeScreen(themeNotifier: widget.themeNotifier),
      SearchScreen(themeNotifier: widget.themeNotifier),
      ReelsScreen(themeNotifier: widget.themeNotifier),
      ProfileScreen(
        userProfile: widget.userProfile,
        themeNotifier: widget.themeNotifier,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeNotifier.value;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: Icon(
                _selectedIndex == 0 ? Icons.home : Icons.home_outlined,
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _selectedIndex == 1 ? Icons.search : Icons.search_outlined,
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _selectedIndex == 2
                    ? Icons.video_library
                    : Icons.video_library_outlined,
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: CircleAvatar(
                radius: 14,
                backgroundImage: widget.userProfile?['avatar_url'] != null
                    ? NetworkImage(widget.userProfile!['avatar_url'])
                    : null,
                child: widget.userProfile?['avatar_url'] == null
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
              label: '',
            ),
          ],
          backgroundColor: isDark ? Colors.black : Colors.white,
          selectedItemColor: isDark ? Colors.white : Colors.black,
          unselectedItemColor: isDark ? Colors.grey[600] : Colors.grey[500],
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          elevation: 0,
          showSelectedLabels: false,
          showUnselectedLabels: false,
        ),
      ),
    );
  }
}