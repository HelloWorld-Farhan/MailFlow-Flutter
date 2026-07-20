# How to Add Test Users for Google OAuth (MailFlow)

Because the MailFlow application's Google Cloud project is currently in **"Testing"** mode (and not published to production), Google restricts OAuth authentication only to email addresses that have been explicitly added to the **Test Users** list in the Google Cloud Console. 

If you try to log in with an email address that is not on this list, Google will show an **"Access Blocked: authorization error"** or "User not added to test users" message.

Follow these step-by-step instructions to add a new testing email ID so that it can be used within the MailFlow app.

---

## Step-by-Step Process

### 1. Log in to Google Cloud Console
1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Log in using the Google Account that **owns** or administers the MailFlow project (usually your primary developer email).

### 2. Select Your Project
1. In the top navigation bar (next to the Google Cloud logo), click on the **Project Dropdown**.
2. Select your MailFlow project from the list.

### 3. Navigate to the OAuth Consent Screen
1. Open the left-hand navigation menu (the hamburger icon `≡` in the top left).
2. Go to **APIs & Services** > **OAuth consent screen**.

### 4. Locate the "Test Users" Section
1. On the OAuth consent screen page, scroll down until you see the **Test users** section.
2. This section will show a list of all emails currently authorized to test the app.
3. Click the **+ ADD USERS** button.

### 5. Add the New Email Address
1. A side panel or modal will appear asking for email addresses.
2. Type in the **exact Gmail address** of the user you want to add (e.g., `example.tester@gmail.com`). 
3. You can add multiple emails by separating them with a comma.
4. Click the **SAVE** button at the bottom of the panel.

### 6. Verify the User is Added
1. The new email address should now appear in the list under the "Test users" section.
2. *(Note: The maximum number of test users allowed while in testing mode is 100).*

---

## What to do on the Phone (Testing the App)

Once the email is added to the Google Cloud Console:
1. Open the **MailFlow** app on your phone.
2. Go to the **Schedule New Email** screen.
3. Enter the newly added email address in the **Sender Email** field.
4. Click **Authenticate with Google**.
5. The Google login screen will appear. Select or log into the newly added email address.
6. Google will now successfully grant access, and the app will authenticate without throwing any authorization errors!

> **Important Note:** Because the app is not verified by Google, the test user might see a warning screen saying *"Google hasn't verified this app."* The user must click **Advanced** at the bottom left, and then click **Go to [App Name] (unsafe)** to proceed with the authentication.
