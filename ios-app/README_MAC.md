# מעבר לאפל: צעדים על המאק

הפרויקט הזה עוטף את האתר (https://set-app-e0r6.onrender.com) באפליקציית אייפון עם Capacitor.
האפליקציה טוענת את האתר החי, כך שעדכוני קוד ממשיכים להגיע בלי להעלות גרסה חדשה לחנות.

## לפני המאק (לעשות עכשיו)
1. לפתוח חשבון Apple Developer Program (99 דולר לשנה), סוג Individual: https://developer.apple.com/programs/enroll/
2. שם החבילה (Bundle ID) נקבע: `com.setapp.workout` (כבר מוגדר ב-`capacitor.config.json`, שדה appId). אי אפשר לשנות אותו אחרי העלאה ל-App Store.
3. לוודא שכתובות המדיניות עובדות: https://set-app-e0r6.onrender.com/privacy ו-https://set-app-e0r6.onrender.com/terms

## על המאק (הדרך המהירה)
1. להתקין Xcode מה-App Store ולפתוח אותו פעם אחת (לאשר תנאים).
2. להתקין Node: `brew install node`.
3. `git clone https://github.com/oriii0638-eng/set-app1.git && cd set-app1/ios-app`
4. `bash build-on-mac.sh`  (מתקין הכול, יוצר את פרויקט iOS, אייקונים, ופותח את Xcode)
5. ב-Xcode: Signing & Capabilities ← Team (החשבון שלך), Bundle Identifier `com.setapp.workout`, ולהוסיף Capability בשם **In-App Purchase**.
6. להריץ על סימולטור ועל אייפון אמיתי ולבדוק: התחברות, אימון, החלפת תרגיל, סרטונים, מחיקת חשבון, רכישה (Sandbox).

## תשלום דרך Apple (In-App Purchase)
המנוי והליווי האישי נרכשים בתוך האפליקציה דרך Apple. השרת מאמת כל רכישה (`/api/iap/verify`) ומקבל חידושים וביטולים מ-Apple (`/api/iap/notify`). באתר (לא באפליקציה) נשארת בקשת ההפעלה הידנית.

### ב-App Store Connect (לפני בדיקת תשלום)
1. Business ← Agreements: לחתום על **Paid Apps Agreement**, ולמלא פרטי בנק ומס. בלי זה אי אפשר למכור.
2. My Apps ← סט ← Monetization ← Subscriptions: ליצור **שתי קבוצות מנויים נפרדות**, כדי שאפשר יהיה להחזיק את שני המנויים יחד:
   - קבוצה "סט מנוי": מוצר `com.setapp.workout.monthly`, משך חודש, מחיר 35 ₪ (או השלב הקרוב ביותר ש-Apple מציעה).
   - קבוצה "סט ליווי אישי": מוצר `com.setapp.workout.coach`, משך חודש, מחיר 220 ₪ (או השלב הקרוב).
   - לכל מוצר: Display Name ותיאור בעברית, ותמונת מסך של מסך הרכישה (לאישור).
3. App Information ← App Store Server Notifications: כתובת Production וגם Sandbox, גרסה **V2**:
   `https://set-app-e0r6.onrender.com/api/iap/notify`
4. Users and Access ← Sandbox ← Testers: ליצור מבחן (מייל שלא רשום ל-Apple ID אחר).
5. אחרי שהמוצרים במצב Ready to Submit: לצרף אותם לגרסת האפליקציה בהגשה הראשונה.

### בדיקה (Sandbox)
- באייפון: הגדרות ← App Store ← Sandbox Account ← להתחבר עם המבחן.
- באפליקציה: לבצע רכישה. מנוי חודשי ב-Sandbox מתחדש כל כמה דקות, לבדוק גם חידוש וגם "שחזור רכישות".
- ב-Render אפשר לעבור על הלוגים ולראות את `/api/iap/verify`.
- אם הרכישה לא מופיעה: לוודא שמזהי המוצרים זהים לחלוטין, ושה-Bundle ID הוא `com.setapp.workout`.

## בעיות שצפויות
- **התראות:** האתר שולח התראות Web Push. באפליקציה עטופה צריך רישום native (APNs) ושינוי בשרת. אם אין, אפשר להשיק בלי התראות.
- **Face ID / Passkey:** דורש בדיקה בתוך האפליקציה, ואולי הגדרת Associated Domains והוספת קובץ apple-app-site-association בשרת.
- **תשלום:** הוגדר דרך Apple IAP לשני המוצרים (ראה למעלה). Apple גובה עמלה (15% בתוכנית עסקים קטנים עד מיליון דולר בשנה, אחרת 30%). חובה שיהיה כפתור "שחזור רכישות" וקישורי תנאים ופרטיות במסך המנוי, והם כבר קיימים.
- **תוסף התשלום:** `@capgo/native-purchases` (StoreKit 2). אם `npx cap sync` מתלונן על Swift Package, לשלוח לי את השגיאה.
- **דחייה אפשרית (4.2):** אפליקציה שהיא רק אתר עטוף עלולה להידחות. כדאי להציג יכולות native.

## ב-App Store Connect
1. My Apps ← New App: שם "סט", שפה ראשית עברית, Bundle ID, SKU.
2. קטגוריה: Health & Fitness.
3. כתובת מדיניות פרטיות: https://set-app-e0r6.onrender.com/privacy
4. App Privacy: להצהיר על המידע שנאסף (אימייל, שם, נתוני בריאות וכושר, תוכן משתמש).
5. דירוג גיל, תיאור, מילות מפתח, צילומי מסך (מהסימולטור, גדלי האייפון שהחנות מבקשת).
6. Review Notes: להוסיף שם משתמש וסיסמה לחשבון בדיקה, ולהסביר איפה מוחקים חשבון (פרופיל ← מחיקת חשבון).
7. מנויים: לפי הסעיף "תשלום דרך Apple" למעלה. ב-Review Notes להוסיף שהרכישה נבדקת עם חשבון Sandbox.
8. ב-Xcode: Product ← Archive ← Distribute App ← App Store Connect. אחרי העלאה לבדוק ב-TestFlight ואז Submit for Review.
