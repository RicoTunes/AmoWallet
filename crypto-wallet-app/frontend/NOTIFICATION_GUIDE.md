# Notification System Guide

## Features Implemented

✅ **Notification Bell** - Added to the top-right of the dashboard
✅ **Unread Badge** - Shows count of unread notifications
✅ **Sound Alerts** - Plays different sounds for different notification types
✅ **Visual Notifications** - System notifications with vibration
✅ **Notification Panel** - Swipe-up panel showing all notifications
✅ **Mark as Read** - Tap to mark individual notifications as read
✅ **Dismiss** - Swipe left to delete individual notifications
✅ **Clear All** - Button to clear all notifications at once

## Notification Types

1. **Incoming Transaction** - Blue icon, incoming.mp3 sound
2. **Transaction Confirmed** - Green check icon, success.mp3 sound
3. **Transaction Failed** - Red error icon, error.mp3 sound
4. **Swap Completed** - Green success icon, success.mp3 sound
5. **Price Alert** - Gray info icon, notification.mp3 sound
6. **Warning** - Orange warning icon, warning.mp3 sound

## How to Use in Your Code

### Show a notification:

```dart
import 'package:crypto_wallet_pro/services/notification_service.dart';

final notificationService = NotificationService();

// Incoming transaction
await notificationService.showIncomingTransaction(
  amount: '0.5',
  currency: 'BTC',
  from: '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb',
);

// Transaction confirmed
await notificationService.showTransactionConfirmed(
  amount: '100',
  currency: 'USDT',
  txHash: '0x123...abc',
);

// Transaction failed
await notificationService.showTransactionFailed(
  amount: '50',
  currency: 'ETH',
  reason: 'Insufficient gas',
);

// Swap completed
await notificationService.showSwapCompleted(
  fromAmount: '1',
  fromCurrency: 'ETH',
  toAmount: '3500',
  toCurrency: 'USDT',
);

// Price alert
await notificationService.showPriceAlert(
  currency: 'BTC',
  price: '65000',
  change: '+5.2',
);

// Custom notification
await notificationService.showNotification(
  title: 'Custom Alert',
  message: 'This is a custom notification',
  type: NotificationType.info,
);
```

## Integration Points

### Where to add notifications in your app:

1. **Wallet Service** (`lib/services/wallet_service.dart`):
   - After receiving transactions
   - When transactions are confirmed
   - When transactions fail

2. **Swap Page** (`lib/presentation/pages/swap/swap_page.dart`):
   - After successful swaps
   - When swaps fail

3. **Send Page** (`lib/presentation/pages/send/send_page.dart`):
   - After sending transactions
   - When send fails

4. **Market Service** (`lib/services/market_service.dart`):
   - For price alerts when price crosses thresholds

## Sound Files

Add these MP3 files to `assets/sounds/`:
- `notification.mp3` - General notification
- `incoming.mp3` - Incoming transaction
- `success.mp3` - Success/confirmation
- `error.mp3` - Error/failed
- `warning.mp3` - Warning

Free sound resources:
- https://mixkit.co/free-sound-effects/notification/
- https://freesound.org/
- https://www.zapsplat.com/

## Testing

The app shows a demo notification 2 seconds after loading the dashboard. You can test it by:

1. Restart the app
2. Wait 2 seconds
3. Check the notification bell (should show badge "1")
4. Tap the bell to see the notification panel

## Next Steps

To make notifications fully functional:

1. **Add sound files** to `assets/sounds/` directory
2. **Integrate with backend** to listen for real transactions
3. **Add WebSocket connection** for real-time transaction updates
4. **Set up price alerts** in settings
5. **Request notification permissions** on first launch

## Permissions

The app already requests these Android permissions:
- `POST_NOTIFICATIONS` - Show notifications
- `VIBRATE` - Vibration feedback
- `WAKE_LOCK` - Wake device for important notifications
