# מעבר לאפל: צעדים על המאק

הפרויקט הזה עוטף את האתר (https://set-app-e0r6.onrender.com) באפליקציית אייפון עם Capacitor.
האפליקציה טוענת את האתר החי, כך שעדכוני קוד ממשיכים להגיע בלי להעלות גרסה חדשה לחנות.

## לפני המאק (לעשות עכשיו)
1. לפתוח חשבון Apple Developer Program (99 דולר לשנה), סוג Individual: https://developer.apple.com/programs/enroll/
2. שם החבילה (Bundle ID) נקבע: `com.setapp.workout` (כבר מוגדר ב-`capacitor.config.json`, שדה appId). אי אפשר לשנות אותו אחרי העלאה ל-App Store.
3. לוודא שכתובת מדיניות הפרטיות עובדת: https://set-app-e0r6.onrender.com/privacy

## על המאק
1. להתקין Xcode מה-App Store, ואז `xcode-select --install`.
2. להתקין Node (`brew install node`) ו-git.
3. `git clone https://github.com/oriii0638-eng/set-app1.git && cd set-app1/ios-app`
4. `npm install`
5. `npx cap add ios`  (יוצר את תיקיית ios)
6. `npm run assets`  (יוצר אייקונים ומסך פתיחה מהקבצים בתיקיית assets)
7. `npm run sync` ואז `npm run open`  (פותח את Xcode)
8. ב-Xcode: לבחור את הפרויקט App ← Signing & Capabilities ← Team (החשבון שלך), לוודא Bundle Identifier.
9. להריץ על סימולטור ועל אייפון אמיתי ולבדוק: התחברות, אימון, החלפת תרגיל, סרטונים, מחיקת חשבון.

## בעיות שצפויות
- **התראות:** האתר שולח התראות Web Push. באפליקציה עטופה צריך רישום native (APNs) ושינוי בשרת. אם אין, אפשר להשיק בלי התראות.
- **Face ID / Passkey:** דורש בדיקה בתוך האפליקציה, ואולי הגדרת Associated Domains והוספת קובץ apple-app-site-association בשרת.
- **תשלום:** מנוי דיגיטלי באפליקציה דורש לרוב רכישה מתוך האפליקציה (In-App Purchase) של Apple. ליווי אישי אנושי אולי חריג. לבדוק מול הנחיות Apple (3.1.1 ו-3.1.3) לפני הגשה.
- **דחייה אפשרית (4.2):** אפליקציה שהיא רק אתר עטוף עלולה להידחות. כדאי להציג יכולות native.

## ב-App Store Connect
1. My Apps ← New App: שם "סט", שפה ראשית עברית, Bundle ID, SKU.
2. קטגוריה: Health & Fitness.
3. כתובת מדיניות פרטיות: https://set-app-e0r6.onrender.com/privacy
4. App Privacy: להצהיר על המידע שנאסף (אימייל, שם, נתוני בריאות וכושר, תוכן משתמש).
5. דירוג גיל, תיאור, מילות מפתח, צילומי מסך (מהסימולטור, גדלי האייפון שהחנות מבקשת).
6. Review Notes: להוסיף שם משתמש וסיסמה לחשבון בדיקה, ולהסביר איפה מוחקים חשבון (פרופיל ← מחיקת חשבון).
7. מנוי (אם נכנסים ל-IAP): ליצור Subscription Group בשם "סט", מוצר חודשי, ולהסכים ל-Paid Apps Agreement.
8. ב-Xcode: Product ← Archive ← Distribute App ← App Store Connect. אחרי העלאה לבדוק ב-TestFlight ואז Submit for Review.
