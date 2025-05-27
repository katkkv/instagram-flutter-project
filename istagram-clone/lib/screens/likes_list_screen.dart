import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LikesListScreen extends StatelessWidget {
  final List<String> likedUsers; // Список ID пользователей, поставивших лайк

  LikesListScreen({required this.likedUsers});

  Future<List<Map<String, String>>> fetchUserDetails() async {
    List<Map<String, String>> userDetails = [];

    try {
      // Запрос к базе данных для получения данных пользователей из таблицы 'profiles'
      for (var userId in likedUsers) {
        final response = await Supabase.instance.client
            .from('profiles') // Используем таблицу 'profiles'
            .select('username') // Выбираем username и avatar_url
            .eq('id', userId) // Условие для получения пользователя по ID
            .single(); // Ожидаем один результат

        if (response != null) {
          userDetails.add({
            'username': response['username'] ?? 'Неизвестно', // Если нет имени, показываем 'Неизвестно'// Если нет аватара, показываем пустую строку
          });
        }
      }
    } catch (e) {
      print('Ошибка при загрузке данных пользователей: $e');
    }

    return userDetails;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Пользователи, которые лайкнули', style: TextStyle(color: Colors.white)),
      ),
      body: FutureBuilder<List<Map<String, String>>>( // Используем FutureBuilder для асинхронной загрузки данных
        future: fetchUserDetails(), // Получаем данные пользователей
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator()); // Показываем индикатор загрузки
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Нет пользователей, которые лайкнули.'));
          }

          List<Map<String, String>> userDetails = snapshot.data!;

          return ListView.builder(
            itemCount: userDetails.length,
            itemBuilder: (context, index) {
              return ListTile(
                contentPadding: const EdgeInsets.all(10),
                leading: CircleAvatar(
                  radius: 25, // Радиус для аватара
                  backgroundImage: NetworkImage(userDetails[index]['avatar_url']!), // Изображение аватара
                  backgroundColor: Colors.grey[300], // Цвет фона, если аватара нет
                ),
                title: Text(
                  userDetails[index]['username']!, // Имя пользователя
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Пользователь'), // Подпись для дополнительной информации
              );
            },
          );
        },
      ),
    );
  }
}
