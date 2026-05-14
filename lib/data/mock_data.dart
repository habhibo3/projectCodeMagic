import '../models/entry.dart';

class MockData {
  static List<ContestEntry> getEntries() {
    return [
      ContestEntry(
        id: '1',
        userId: 'u1',
        userName: 'Alex Rivera',
        userAvatar: 'https://i.pravatar.cc/150?u=1',
        contentUrl: 'https://images.unsplash.com/photo-1542291026-7eec264c27ff',
        type: 'image',
        caption: 'Speed is everything 🏎️',
        totalVotes: 120,
      ),
      ContestEntry(
        id: '2',
        userId: 'u2',
        userName: 'Sarah Chen',
        userAvatar: 'https://i.pravatar.cc/150?u=2',
        contentUrl: 'https://images.unsplash.com/photo-1511367461989-f85a21fda167',
        type: 'image',
        caption: 'Golden hour vibes ✨',
        totalVotes: 85,
      ),
      ContestEntry(
        id: '3',
        userId: 'u3',
        userName: 'Marcus Jordan',
        userAvatar: 'https://i.pravatar.cc/150?u=3',
        contentUrl: 'https://images.unsplash.com/photo-1521737711867-e3b97375f902',
        type: 'image',
        caption: 'Urban explorer 🏙️',
        totalVotes: 42,
      ),
      ContestEntry(
        id: '4',
        userId: 'u4',
        userName: 'Elena Petrova',
        userAvatar: 'https://i.pravatar.cc/150?u=4',
        contentUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9',
        type: 'image',
        caption: 'Simplicity is key 🌿',
        totalVotes: 67,
      ),
      ContestEntry(
        id: '5',
        userId: 'u5',
        userName: 'Philosopher Mike',
        userAvatar: 'https://i.pravatar.cc/150?u=5',
        contentUrl: '',
        type: 'text',
        caption: 'The only limit is your mind. Keep pushing. 🚀',
        totalVotes: 15,
      ),
    ];
  }
}
