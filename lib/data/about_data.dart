class AboutFeature {
  final String emoji;
  final String title;
  final String desc;
  const AboutFeature(this.emoji, this.title, this.desc);
}

class AboutData {
  AboutData._();
  static const String longDescription =
      'PARSAVIP یک کلاینت VPN مدرن، سریع و امن است. از پروتکل‌های SS، VLESS، VMess و Trojan پشتیبانی می‌کند و به صورت هوشمند بهترین سرور را انتخاب می‌کند.';

  static const List<AboutFeature> features = [
    AboutFeature('🚀', 'سرعت بالا', 'اتصال سریع'),
    AboutFeature('🔒', 'حریم خصوصی', 'بدون ذخیره لاگ'),
    AboutFeature('🌍', 'سرورهای متعدد', 'ده‌ها سرور جهانی'),
    AboutFeature('🎨', 'رابط کاربری مدرن', 'طراحی زیبا'),
    AboutFeature('⚡', 'انتخاب هوشمند', 'اتصال به بهترین سرور'),
    AboutFeature('🛡️', 'امنیت پیشرفته', 'رمزنگاری قوی'),
  ];
}
