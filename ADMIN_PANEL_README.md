# Admin Panel - Contest Live Platform

## Overview
A comprehensive web-based admin panel for managing the Contest Live real-time ranking platform.

## Features

### 1. Dashboard Overview
- Real-time platform statistics
- Total users, contests, posts, and votes
- Active contests count
- Banned users tracking
- Quick action buttons

### 2. User Management
- View all users with search functionality
- User details display (profile, location, subscription)
- Ban users permanently
- Suspend users with configurable duration (1 hour, 1 day, 1 week, 1 month)
- Delete users (removes all associated data)
- Role management (Admin, Judge, Contestant, Voter)
- Subscription level tracking (Free/Premium)

### 3. Contest Management
- Create new contests
- Edit existing contests
- Delete contests (with warning about data loss)
- View contest details
- Contest status tracking (Active/Ended)
- Participant and vote statistics
- Category and type management

### 4. Content Moderation
- View all posts with content preview
- View all contest entries
- Flag inappropriate content with reasons
- Delete posts and entries
- Content type badges (Video, Image, Text)
- Visibility scope tracking
- Engagement metrics (likes, comments, votes)

### 5. Analytics Dashboard
- Platform overview with growth metrics
- Vote trends visualization (7-day chart)
- Top contests by votes
- Top voters by activity
- Real-time data refresh
- Percentage change indicators

### 6. Anti-Cheat System
- System status monitoring
- Rate limiting configuration
- Suspicious activity detection
- Flagged users management
- Activity log viewing
- Automatic flagging thresholds
- IP tracking (status display)

## Performance Optimizations

### Caching System
- Implemented in-memory caching service
- Configurable TTL (Time To Live) for different data types
- Automatic cache expiration cleanup
- Stream-based cache watching
- Cache statistics tracking

### Cache Configuration
- **Contests**: 5-minute TTL
- **Entries**: 2-minute TTL (more frequent updates)
- **User Profiles**: 10-minute TTL
- Automatic cleanup every 30 minutes

### Anti-Cheat Measures
- Vote rate limiting (100 votes/day per user)
- Vote cooldown (1 second between votes)
- Suspicious vote threshold (50 votes/hour)
- Auto-ban threshold (3 flags)
- Vote attempt tracking
- Suspicious activity flagging

## Access

### Web Navigation
The admin panel is accessible from the web sidebar navigation:
1. Click "Admin Panel" in the sidebar
2. Requires admin role (role: 'admin' in Firestore)

### Role-Based Access
- Admin users have full access to all features
- Role is stored in Firestore user document
- Check using `AdminService.isAdmin(userId)`

## File Structure

```
lib/
├── data/
│   ├── admin_service.dart          # Admin-specific Firebase operations
│   ├── cache_service.dart          # In-memory caching system
│   └── firebase_service.dart       # Enhanced with caching
├── screens/
│   ├── admin_dashboard_screen.dart      # Main dashboard
│   ├── admin_users_screen.dart          # User management
│   ├── admin_contests_screen.dart       # Contest management
│   ├── admin_moderation_screen.dart     # Content moderation
│   ├── admin_analytics_screen.dart      # Analytics dashboard
│   └── admin_anticheat_screen.dart      # Anti-cheat system
└── main.dart                        # Updated with admin route
```

## Usage

### Setting Admin Role
To make a user an admin, set their role in Firestore:
```dart
await _adminService.setAdminRole(userId, true);
```

### Checking Admin Status
```dart
final isAdmin = await _adminService.isAdmin(userId);
```

### Cache Management
```dart
// Get cached data
final data = _cache.get<List<ContestModel>>('contests');

// Set data with TTL
_cache.set('key', data, ttl: Duration(minutes: 5));

// Clear expired entries
_cache.clearExpired();

// Clear all cache
_cache.clear();
```

## Future Enhancements

### Potential Additions
- Email notifications for flagged content
- Bulk user operations
- Export analytics data (CSV/PDF)
- Custom date range analytics
- Real-time activity monitoring
- IP-based blocking
- Device fingerprinting
- Advanced fraud detection algorithms
- A/B testing framework
- Feature flags management

## Security Considerations

### Current Implementation
- Role-based access control
- Firestore security rules (to be configured)
- Rate limiting on voting
- Suspicious activity tracking

### Recommended Enhancements
- Implement Firebase Security Rules
- Add 2FA for admin access
- Audit logging for admin actions
- IP whitelisting for admin panel
- Session timeout for admin sessions
- Encryption for sensitive data

## Performance Metrics

### Cache Hit Rates
- Monitor cache effectiveness using `_cache.size` and `_cache.expiredCount`
- Adjust TTL values based on usage patterns
- Consider implementing cache warming for frequently accessed data

### Database Optimization
- Use composite indexes for frequently queried fields
- Implement pagination for large datasets
- Consider using Firestore offline persistence
- Optimize real-time listener usage

## Troubleshooting

### Admin Panel Not Showing
- Verify user has 'admin' role in Firestore
- Check Firebase initialization
- Ensure web platform is being used

### Cache Issues
- Cache automatically clears expired entries
- Manual cache clear: `_cache.clear()`
- Check TTL configuration in FirebaseService

### Anti-Cheat False Positives
- Review vote thresholds in AdminAntiCheatScreen
- Adjust rate limits based on platform usage
- Reset user flags if needed

## Support

For issues or questions:
1. Check Firebase console for errors
2. Review cache service logs
3. Verify user roles and permissions
4. Check network connectivity
