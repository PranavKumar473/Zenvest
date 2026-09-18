package com.example.financial_clarity

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class NotificationSyncService : NotificationListenerService() {
    companion object {
        private const val TAG = "NotificationSyncService"
        var instance: NotificationSyncService? = null
        var notificationListener: NotificationListener? = null
    }

    interface NotificationListener {
        fun onNotificationReceived(packageName: String, title: String, text: String, timestamp: Long)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "NotificationSyncService created")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance == this) {
            instance = null
        }
        Log.d(TAG, "NotificationSyncService destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName
        
        // Filter to capture only PhonePe, Google Pay, and Paytm notifications
        val targetPackages = listOf(
            "com.phonepe.app",
            "com.google.android.apps.nbu.paisa.user",
            "net.one97.paytm"
        )
        
        if (!targetPackages.contains(packageName)) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getString("android.title", "")
        val text = extras.getCharSequence("android.text", "").toString()
        val timestamp = sbn.postTime

        Log.d(TAG, "Payment notification from $packageName: title=$title, text=$text")

        notificationListener?.onNotificationReceived(packageName, title, text, timestamp)
    }
}
