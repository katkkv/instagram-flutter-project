import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionService {
  static Future<void> toggleSubscription(String currentUserId, String targetUserId, bool isSubscribed) async {
    try {
      if (isSubscribed) {
        // Отписываемся
        await Supabase.instance.client
            .from('followers')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', targetUserId);

        // Уменьшаем количество подписчиков у пользователя
        await Supabase.instance.client
            .from('profiles')
            .update({'followers_count': (await getFollowersCount(targetUserId)) - 1})
            .eq('id', targetUserId);

        // Уменьшаем количество подписок у текущего пользователя
        await Supabase.instance.client
            .from('profiles')
            .update({'subscriptions_count': (await getSubscriptionsCount(currentUserId)) - 1})
            .eq('id', currentUserId);
      } else {
        // Подписываемся
        await Supabase.instance.client
            .from('followers')
            .insert({
          'follower_id': currentUserId,
          'following_id': targetUserId,
        });

        // Увеличиваем количество подписчиков у пользователя
        await Supabase.instance.client
            .from('profiles')
            .update({'followers_count': (await getFollowersCount(targetUserId)) + 1})
            .eq('id', targetUserId);

        // Увеличиваем количество подписок у текущего пользователя
        await Supabase.instance.client
            .from('profiles')
            .update({'subscriptions_count': (await getSubscriptionsCount(currentUserId)) + 1})
            .eq('id', currentUserId);
      }
    } catch (error) {
      print('Error updating subscription: $error');
    }
  }

  static Future<int> getFollowersCount(String userId) async {
    final response = await Supabase.instance.client
        .from('profiles')
        .select('followers_count')
        .eq('id', userId)
        .single();
    return response['followers_count'] ?? 0;
  }

  static Future<int> getSubscriptionsCount(String userId) async {
    final response = await Supabase.instance.client
        .from('profiles')
        .select('subscriptions_count')
        .eq('id', userId)
        .single();
    return response['subscriptions_count'] ?? 0;
  }
}