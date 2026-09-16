class FaqItem {
  final String question;
  final String answer;
  const FaqItem(this.question, this.answer);
}

const List<FaqItem> faqList = [
  FaqItem('PARSAVIP چیست؟', 'یک کلاینت VPN سریع و امن که از پروتکل‌های SS، VLESS، VMess و Trojan پشتیبانی می‌کند.'),
  FaqItem('چطور بهترین سرور را انتخاب کنم؟', 'دکمه «تست پینگ» را بزنید تا همه سرورها تست شوند، سپس «Best Server» را بزنید.'),
  FaqItem('رمز ادمین چیست؟', 'رمز ادمین به صورت هش‌شده ذخیره می‌شود و قابل خواندن از APK نیست.'),
  FaqItem('آیا اطلاعات من ذخیره می‌شود؟', 'خیر. همه چیز به صورت محلی روی دستگاه شما ذخیره می‌شود.'),
  FaqItem('چطور کانفیگ جدید اضافه کنم؟', 'وارد پنل ادمین شوید و «افزودن سرور» را انتخاب کنید.'),
  FaqItem('اتصال قطع می‌شود، چه کنم؟', 'سرور دیگری را امتحان کنید یا MTU را کم کنید.'),
];
