class AboutFeature {
  final String emoji;
  final String title;
  final String desc;
  const AboutFeature(this.emoji, this.title, this.desc);
}

class AboutData {
  AboutData._();

  static const String longDescription =
      'PARSAVIP یک کلاینت VPN مدرن، سریع و امن است که با تمرکز روی حریم خصوصی و تجربه کاربری طراحی شده. این اپلیکیشن از پروتکل‌های SS، VLESS، VMess و Trojan پشتیبانی می‌کند و به صورت هوشمند بهترین سرور را بر اساس پینگ انتخاب می‌کند.';

  static const List<AboutFeature> features = [
    AboutFeature('🚀', 'سرعت بالا', 'اتصال سریع با هسته مدرن'),
    AboutFeature('🔒', 'حریم خصوصی', 'بدون ذخیره لاگ یا اطلاعات شخصی'),
    AboutFeature('🌍', 'سرورهای متعدد', 'پشتیبانی از ده‌ها سرور جهانی'),
    AboutFeature('🎨', 'رابط کاربری مدرن', 'طراحی زیبا با انیمیشن‌های نرم'),
    AboutFeature('⚡', 'انتخاب هوشمند', 'اتصال خودکار به سریع‌ترین سرور'),
    AboutFeature('🛡️', 'امنیت پیشرفته', 'رمزنگاری AES-256 و ChaCha20'),
  ];
}
