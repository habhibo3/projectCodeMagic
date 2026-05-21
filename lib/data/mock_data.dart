import '../models/entry.dart';

class MockData {
  static List<ContestEntry> getEntries() {
    return [
      ContestEntry(
        id: '1',
        userId: 'u1',
        userName: 'James from USA',
        userAvatar: 'https://i.pravatar.cc/150?u=1',
        countryFlag: '🇺🇸',
        contentUrl: 'https://images.unsplash.com/photo-1516280440614-37939bbacd81',
        type: 'image',
        caption: 'Amazing tradition! 🎤',
        totalVotes: 0,
        ratingStars: 5,
      ),
      ContestEntry(
        id: '2',
        userId: 'u2',
        userName: 'Lan from Vietnam',
        userAvatar: 'https://i.pravatar.cc/150?u=2',
        countryFlag: '🇻🇳',
        contentUrl: 'https://images.unsplash.com/photo-1533174072545-7a4b6ad7a6c3',
        type: 'image',
        caption: 'Proud of our culture! 🇻🇳',
        totalVotes: 0,
        ratingStars: 4,
      ),
      ContestEntry(
        id: '3',
        userId: 'u3',
        userName: 'Wei from China',
        userAvatar: 'https://i.pravatar.cc/150?u=3',
        countryFlag: '🇨🇳',
        contentUrl: 'https://images.unsplash.com/photo-1521737711867-e3b97375f902',
        type: 'image',
        caption: '👍👍👍',
        totalVotes: 0,
        ratingStars: 5,
      ),
      ContestEntry(
        id: '4',
        userId: 'u4',
        userName: 'Sophie from France',
        userAvatar: 'https://i.pravatar.cc/150?u=4',
        countryFlag: '🇫🇷',
        contentUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9',
        type: 'image',
        caption: 'Magnifique! 🇫🇷',
        totalVotes: 0,
        ratingStars: 4,
      ),
      ContestEntry(
        id: '5',
        userId: 'u5',
        userName: 'Yuki from Japan',
        userAvatar: 'https://i.pravatar.cc/150?u=5',
        countryFlag: '🇯🇵',
        contentUrl: '',
        type: 'text',
        caption: 'すばらしい伝統です！👏',
        totalVotes: 0,
        ratingStars: 5,
      ),
    ];
  }

  static List<ContestModel> getContests() {
    return [
      ContestModel(
        id: 'c1',
        title: 'The Next Star Talent Contest',
        subtitle: 'Show us your talent and be the next star!',
        description:
            'Welcome to the biggest talent discovery platform on FeastVote! Submit your performance video and let the world decide who the next global star is. Open to all music genres, dance styles, comedy acts, and spoken word artists.',
        rules:
            '1. Submit one original video (max 3 mins)\n2. No copyrighted music without license\n3. One entry per user\n4. Voting is open to all registered users\n5. Rankings reset every 10 seconds based on momentum',
        prize:
            '🥇 1st Place: \$5,000 + Recording Contract\n🥈 2nd Place: \$2,000\n🥉 3rd Place: \$500\n🎁 All finalists: FeastVote Pro subscription (1 year)',
        schedule:
            '📅 Submission Open: May 10 – May 20, 2026\n🗳️ Public Voting: May 21 – May 31, 2026\n🏆 Winners Announced: June 1, 2026',
        image: 'https://images.unsplash.com/photo-1516280440614-37939bbacd81',
        category: 'Music',
        type: 'Official',
        participantCount: 128,
        totalVotes: 3600,
        rating: 4.7,
        reviewCount: 239,
        endsIn: '7 days',
      ),
      ContestModel(
        id: 'c2',
        title: 'Global Dance Off',
        subtitle: 'Bring your best moves to the global stage.',
        description:
            'The Global Dance Off is FeastVote\'s premier dance competition. From hip-hop to classical ballet, every style is welcome. Show the world your rhythm, creativity, and passion for dance!',
        rules:
            '1. Video must be at least 60 seconds\n2. Original choreography required\n3. Group entries (max 4 people) allowed\n4. No explicit content\n5. Audience votes determine the winner',
        prize:
            '🥇 1st Place: \$3,000 + Professional Dance Showcase\n🥈 2nd Place: \$1,000\n🥉 3rd Place: \$300',
        schedule:
            '📅 Submission Open: May 15 – May 25, 2026\n🗳️ Public Voting: May 26 – June 5, 2026\n🏆 Winners Announced: June 7, 2026',
        image: 'https://images.unsplash.com/photo-1533174072545-7a4b6ad7a6c3',
        category: 'Dance',
        type: 'Public',
        participantCount: 74,
        totalVotes: 1800,
        rating: 4.5,
        reviewCount: 110,
        endsIn: '12 days',
      ),
      ContestModel(
        id: 'c3',
        title: 'Comedy Night Live',
        subtitle: 'Make us laugh and win the grand prize!',
        description:
            'Think you\'re funny? Prove it! Comedy Night Live is looking for the next big comedy star. Stand-up, sketches, improv — all formats welcome. Make the audience laugh the most to claim your crown.',
        rules:
            '1. Max video length: 5 minutes\n2. No hate speech or discriminatory content\n3. Original material only\n4. Audience voting determines rankings\n5. Judge panel selects the top 3 from audience top 10',
        prize:
            '🥇 1st Place: \$2,500 + Comedy Club Booking\n🥈 2nd Place: \$750\n🥉 3rd Place: \$250',
        schedule:
            '📅 Submission Open: May 18 – May 28, 2026\n🗳️ Public Voting: May 29 – June 8, 2026\n🏆 Winners Announced: June 10, 2026',
        image: 'https://images.unsplash.com/photo-1585699324551-f6c309eedeca',
        category: 'Comedy',
        type: 'Official',
        participantCount: 56,
        totalVotes: 980,
        rating: 4.8,
        reviewCount: 88,
        endsIn: '15 days',
      ),
    ];
  }
}
